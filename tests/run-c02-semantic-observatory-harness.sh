#!/usr/bin/env bash
# F16 adversarial producer -> semantic client acceptance harness. All observed
# projects are temporary, provider commands are disabled, and output is bounded.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mana_root="${MANA_ROOT:-}"
usage() { echo "Usage: tests/run-c02-semantic-observatory-harness.sh --mana-root <path>" >&2; }
fail() { echo "ERROR: $*" >&2; exit 1; }
acceptance_failures=0
record_failure() {
  echo "ACCEPTANCE FAILURE: $*" >&2
  acceptance_failures=$((acceptance_failures + 1))
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mana-root) mana_root="${2:-}"; [ -n "$mana_root" ] || { usage; exit 2; }; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[ -n "$mana_root" ] || { usage; exit 2; }
mana_root="$(cd "$mana_root" 2>/dev/null && pwd -P)" || fail 'unreadable Mana root'
[ -x "$mana_root/scripts/mana-inspect.sh" ] || fail 'Mana inspect producer is missing'
command -v jq >/dev/null || fail 'jq is required'
command -v flutter >/dev/null || fail 'flutter is required'

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mana-c02.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
outputs="$tmp/outputs"
mkdir -p "$outputs" "$tmp/provider-guard"
for provider in claude codex openai ollama; do
  printf '%s\n' '#!/bin/sh' 'echo "A model/provider command was invoked" >&2' 'exit 97' > "$tmp/provider-guard/$provider"
  chmod +x "$tmp/provider-guard/$provider"
done
export PATH="$tmp/provider-guard:$PATH"

new_project() {
  local name="$1" project="$tmp/$1"
  mkdir -p "$project"
  git -C "$project" init -q
  git -C "$project" config user.name 'Mana F16'
  git -C "$project" config user.email 'mana-f16@example.invalid'
  printf '%s\n' "# $name" > "$project/README.md"
  git -C "$project" add README.md
  git -C "$project" commit -qm initial
  printf '%s\n' "$project"
}

inspect_to() {
  local project="$1" name="$2" operation="$3"
  shift 3
  "$mana_root/scripts/mana-inspect.sh" --project-root "$project" \
    "$operation" "$@" --json > "$outputs/$name.json"
}

validate_response() {
  local file="$1" schema="$2"
  jq -e --arg schema "$schema" '
    type == "object" and .schema == $schema and
    .guarantees.model_calls == 0 and .guarantees.writes == false
  ' "$file" >/dev/null || fail "invalid or non-zero-token response: $(basename "$file")"
  ! grep -Eq '"/(Users|home|private|tmp)/|[A-Za-z]:\\\\' "$file" || \
    fail "absolute path leaked from $(basename "$file")"
}

capture_state() {
  local project="$1" destination="$2"
  (
    cd "$project"
    find -P . -path './.git' -prune -o \( -type f -o -type l \) -print0 |
      LC_ALL=C sort -z |
      while IFS= read -r -d '' path; do
        if [ -L "$path" ]; then
          printf 'link|%s|%s\n' "$path" "$(readlink "$path")"
        else
          stat -f 'file|%N|%m|%z' "$path"
          shasum -a 256 "$path"
        fi
      done
    git status --porcelain=v1
  ) > "$destination"
}

empty="$(new_project empty-uninitialized)"
inspect_to "$empty" empty-project project
inspect_to "$empty" empty-artifacts artifacts
inspect_to "$empty" empty-work-items work-items
validate_response "$outputs/empty-project.json" 'mana.inspect.project/v1'
validate_response "$outputs/empty-artifacts.json" 'mana.inspect.artifacts/v1'
validate_response "$outputs/empty-work-items.json" 'mana.inspect.work-items/v1'
jq -e '.mana.present == false' "$outputs/empty-project.json" >/dev/null || fail 'empty project reported Mana'
jq -e '.artifacts == []' "$outputs/empty-artifacts.json" >/dev/null || fail 'empty catalog is not empty'

context_only="$(new_project shared-context-only)"
mkdir -p "$context_only/.mana/global"
printf '%s\n' '# Architecture' 'Shared context only.' > "$context_only/.mana/global/architecture.md"
inspect_to "$context_only" context-only-work work-items
inspect_to "$context_only" context-only-project-context project-context
validate_response "$outputs/context-only-work.json" 'mana.inspect.work-items/v1'
validate_response "$outputs/context-only-project-context.json" 'mana.inspect.project-context/v1'
jq -e '.work_items == []' "$outputs/context-only-work.json" >/dev/null || fail 'context-only project has work items'
jq -e 'any(.categories[]; .category == "architecture" and (.artifacts|length) == 1)' \
  "$outputs/context-only-project-context.json" >/dev/null || fail 'shared architecture context is missing'

feature_only="$(new_project one-feature)"
mkdir -p "$feature_only/.mana/features/FEATURE-ONLY"
printf '%s\n' 'workspace_type: feature' 'workspace_id: FEATURE-ONLY' 'feature_id: FEATURE-ONLY' \
  > "$feature_only/.mana/features/FEATURE-ONLY/manifest.yaml"
printf '%s\n' '.mana/features/FEATURE-ONLY' > "$feature_only/.mana/active-workspace"
inspect_to "$feature_only" feature-only-work work-items
validate_response "$outputs/feature-only-work.json" 'mana.inspect.work-items/v1'
jq -e '.work_items|length == 1 and .[0].work_item_id == "feature:FEATURE-ONLY"' \
  "$outputs/feature-only-work.json" >/dev/null || fail 'feature-only identity failed'
mkdir -p "$feature_only/.mana/features/MISSING-MANIFEST"
inspect_to "$feature_only" missing-manifest work-item 'feature:MISSING-MANIFEST'
validate_response "$outputs/missing-manifest.json" 'mana.inspect.work-item/v1'
jq -e 'any(.diagnostics[]; .id == "manifest-unavailable") and .work_item.lifecycle.state == "unknown"' \
  "$outputs/missing-manifest.json" >/dev/null || fail 'missing manifest did not remain diagnostic/unknown'

session_only="$(new_project one-session)"
mkdir -p "$session_only/.mana/sessions/session-only"
printf '%s\n' 'workspace_type: session' 'workspace_id: session-only' 'purpose: audit' \
  > "$session_only/.mana/sessions/session-only/manifest.yaml"
inspect_to "$session_only" session-only-work work-items
validate_response "$outputs/session-only-work.json" 'mana.inspect.work-items/v1'
jq -e '.work_items|length == 1 and .[0].work_item_id == "session:session-only" and .[0].lifecycle.state == "unknown"' \
  "$outputs/session-only-work.json" >/dev/null || fail 'session-only conservative semantics failed'

rich="$(new_project full-semantic)"
mkdir -p \
  "$rich/.mana/features/FEAT-ACCEPT" \
  "$rich/.mana/sessions/session-audit" \
  "$rich/.mana/features/FEAT-ACCEPT/context" \
  "$rich/.mana/features/FEAT-ACCEPT/planning" \
  "$rich/.mana/features/FEAT-ACCEPT/decisions" \
  "$rich/.mana/features/FEAT-ACCEPT/evidence/verification/run-failed" \
  "$rich/.mana/features/FEAT-ACCEPT/evidence/verification/run-finished" \
  "$rich/.mana/features/FEAT-ACCEPT/evidence/verification/run-stale" \
  "$rich/.mana/runtime/events" \
  "$rich/.mana/global/team-decisions" \
  "$rich/.mana/learning/journeys/jrn_context"
printf '%s\n' 'workspace_type: feature' 'workspace_id: FEAT-ACCEPT' \
  'feature_id: FEAT-ACCEPT' 'branch: feature/acceptance' 'purpose: acceptance' \
  > "$rich/.mana/features/FEAT-ACCEPT/manifest.yaml"
printf '%s\n' '.mana/features/FEAT-ACCEPT' > "$rich/.mana/active-workspace"
printf '%s\n' 'workspace_type: session' 'workspace_id: session-audit' 'purpose: repository-audit' \
  > "$rich/.mana/sessions/session-audit/manifest.yaml"
printf '%s\n' '# Requirements' '' 'A paragraph with unusual Unicode: λ 日本語 👩🏽‍💻.' '' \
  '| Case | Result |' '| --- | --- |' '| happy | pass |' '' \
  '```dart' 'void main() {}' '```' '' '<script>alert(1)</script>' \
  '[unsafe](javascript:alert(1)) [local](file:///etc/passwd) ![remote](https://example.invalid/pixel.png)' \
  > "$rich/.mana/features/FEAT-ACCEPT/context/story-context.md"
printf '%s\n' '# Plan' '- one' '- two' > "$rich/.mana/features/FEAT-ACCEPT/planning/implementation-plan.md"
printf '%s\n' '| decision | status |' '| --- | --- |' '| retention | needs_owner_review |' \
  > "$rich/.mana/features/FEAT-ACCEPT/decisions/developer-choice-log.md"
printf '%s\n' '{"schemaVersion":"2","kind":"verification-result","runId":"run-failed","overallResult":"failed","generatedAt":"2026-08-14T08:00:00Z"}' \
  > "$rich/.mana/features/FEAT-ACCEPT/evidence/verification/run-failed/result.json"
printf '%s\n' '{"schemaVersion":"2","kind":"verification-result","runId":"run-finished","overallResult":"passed","finishedAt":"2026-08-14T08:30:00Z"}' \
  > "$rich/.mana/features/FEAT-ACCEPT/evidence/verification/run-finished/result.json"
printf '%s\n' '{"schemaVersion":"2","kind":"verification-result","runId":"run-stale","overallResult":"passed","staleness":"stale"}' \
  > "$rich/.mana/features/FEAT-ACCEPT/evidence/verification/run-stale/result.json"
printf '%s\n' \
  '{"eventId":"event-a","timestamp":"2026-08-14T09:00:00Z"}' \
  '{"eventId":"event-b","timestamp":"2026-08-14T09:00:00Z"}' \
  '{"eventId":"missing-time"}' '{malformed' \
  > "$rich/.mana/runtime/events/acceptance.jsonl"
printf '%s\n' '{not json' > "$rich/.mana/features/FEAT-ACCEPT/context/malformed.json"
ln -s /etc/passwd "$rich/.mana/features/FEAT-ACCEPT/context/unsafe-link"
printf '%s\n' '# Architecture' > "$rich/.mana/global/architecture.md"
printf '%s\n' '# Project decision' > "$rich/.mana/global/team-decisions/adr-001.md"
printf '%s\n' '# Integrations' > "$rich/.mana/global/integration-map.md"
printf '%s\n' '# Engineering guards' > "$rich/.mana/global/engineering-guards.md"
printf '%s\n' '# Glossary' > "$rich/.mana/global/domain-glossary.md"
printf '%s\n' '# Learning journey context' > "$rich/.mana/learning/journeys/jrn_context/context.md"
printf '%s\n' '# Testing policy' > "$rich/.mana/global/testing-policy.md"
printf '%s\n' '# Database policy' > "$rich/.mana/global/database-policy.md"

capture_state "$rich" "$tmp/before-state"
inspect_to "$rich" project project
inspect_to "$rich" artifacts artifacts
inspect_to "$rich" work-items work-items
inspect_to "$rich" work-item work-item 'feature:FEAT-ACCEPT'
inspect_to "$rich" project-context project-context
inspect_to "$rich" activity activity
artifact_id="$(jq -r '.sections[]|select(.section_id=="requirements")|.artifacts[0].artifact_id' "$outputs/work-item.json")"
inspect_to "$rich" artifact artifact "$artifact_id"
inspect_to "$rich" source source README.md

validate_response "$outputs/project.json" 'mana.inspect.project/v1'
validate_response "$outputs/artifacts.json" 'mana.inspect.artifacts/v1'
validate_response "$outputs/work-items.json" 'mana.inspect.work-items/v1'
validate_response "$outputs/work-item.json" 'mana.inspect.work-item/v1'
validate_response "$outputs/project-context.json" 'mana.inspect.project-context/v1'
validate_response "$outputs/activity.json" 'mana.inspect.activity/v1'
validate_response "$outputs/artifact.json" 'mana.inspect.artifact/v1'
validate_response "$outputs/source.json" 'mana.inspect.source/v1'

jq -e '
  ([.operations[].name] | contains(["project","artifacts","artifact","source","work-items","work-item","project-context","activity"]))
' "$outputs/project.json" >/dev/null || fail 'FULL_SEMANTIC operations are not advertised'
jq -e '
  ([.work_items[].work_item_id] | sort) == ["feature:FEAT-ACCEPT","session:session-audit"] and
  any(.work_items[]; .work_item_id == "session:session-audit" and .lifecycle.state == "unknown")
' "$outputs/work-items.json" >/dev/null || fail 'feature/session work-item matrix failed'
jq -e '
  any(.attention_items[]; .category == "failed_verification") and
  any(.attention_items[]; .category == "stale_evidence") and
  any(.attention_items[]; .category == "pending_decision") and
  all(.sections[].artifacts[]; .work_item_id == "feature:FEAT-ACCEPT")
' "$outputs/work-item.json" >/dev/null || fail 'attention or ownership semantics failed'
jq -e '
  ([.categories[].category] | sort) == ["architecture","database_policy","engineering_guards","glossary","integrations","learning_journeys","project_decisions","testing_policy"] and
  all(.categories[].artifacts[]; .work_item_id == null and .section_id == null)
' "$outputs/project-context.json" >/dev/null || fail 'project-context category/ownership matrix failed'
jq -e '
  any(.events[]; .timestamp.provenance == "explicit_domain_timestamp") and
  any(.events[]; .timestamp.provenance == "filesystem_mtime_epoch") and
  any(.events[]; (.related_artifact_ids|index("verification:run-finished")) and .timestamp.value == "2026-08-14T08:30:00Z") and
  ([.events[]|select(.event_id == "event-a" or .event_id == "event-b")|.event_id] == ["event-a","event-b"]) and
  (([.events[].event_id]|length) == ([.events[].event_id]|unique|length))
' "$outputs/activity.json" >/dev/null || {
  jq -c '[.events[]|{event_id,timestamp,related_artifact_ids}] | .[0:12]' "$outputs/activity.json" >&2
  record_failure 'activity chronology/provenance matrix failed'
}

for operation in project artifacts work-items project-context activity; do
  inspect_to "$rich" "$operation-repeat" "$operation"
  cmp -s "$outputs/$operation.json" "$outputs/$operation-repeat.json" || \
    fail "$operation response is not byte-deterministic"
done

(
  cd "$root"
  flutter pub get --offline >/dev/null
  C02_PROJECT_ROOT="$rich" C02_MANA_ROOT="$mana_root" C02_OUTPUT_ROOT="$outputs" \
    flutter test --no-pub test/c02_semantic_observatory_e2e_test.dart
)
capture_state "$rich" "$tmp/after-state"
cmp -s "$tmp/before-state" "$tmp/after-state" || fail 'inspect/Familiar changed the observed project'

hostile="$(new_project disappearing-artifact)"
mkdir -p "$hostile/.mana"
printf '%s\n' '# Temporary' > "$hostile/.mana/temporary.md"
printf '%s\n' 'unreadable' > "$hostile/.mana/unreadable.txt"
chmod 000 "$hostile/.mana/unreadable.txt"
if ! "$mana_root/scripts/mana-inspect.sh" --project-root "$hostile" artifacts --json \
  > "$outputs/unreadable-catalog.json" 2> "$tmp/unreadable-error"; then
  [ "$(wc -c < "$tmp/unreadable-error" | tr -d ' ')" -lt 2048 ] || fail 'unreadable-file diagnostic is unbounded'
fi
chmod 600 "$hostile/.mana/unreadable.txt"
inspect_to "$hostile" disappearing-catalog artifacts
temporary_id="$(jq -r '.artifacts[]|select(.path==".mana/temporary.md")|.artifact_id' "$outputs/disappearing-catalog.json")"
mv "$hostile/.mana/temporary.md" "$tmp/temporary-removed.md"
if "$mana_root/scripts/mana-inspect.sh" --project-root "$hostile" artifact "$temporary_id" --json \
  > "$outputs/disappearing-detail.json" 2> "$tmp/disappearing-error"; then
  fail 'removed artifact unexpectedly remained readable'
fi
[ "$(wc -c < "$tmp/disappearing-error" | tr -d ' ')" -lt 2048 ] || fail 'removed-artifact diagnostic is unbounded'

"$mana_root/scripts/validate-inspect-contract.sh" >/dev/null
if [ "$acceptance_failures" -ne 0 ]; then
  echo "C02 completed with $acceptance_failures acceptance failure(s)" >&2
  exit 1
fi
echo 'C02 semantic observatory acceptance harness passed'
