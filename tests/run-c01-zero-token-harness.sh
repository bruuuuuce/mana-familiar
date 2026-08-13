#!/usr/bin/env bash
# Deterministic C01 producer→consumer proof. It creates and removes one
# temporary target repository and never invokes a model or network service.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mana_root="${MANA_ROOT:-}"
usage() { echo "Usage: tests/run-c01-zero-token-harness.sh [--mana-root <path>]" >&2; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mana-root) mana_root="${2:-}"; [ -n "$mana_root" ] || { usage; exit 2; }; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
if [ -z "$mana_root" ]; then
  candidate="$root/../mana"
  if [ -d "$candidate/.git" ]; then
    remote="$(git -C "$candidate" remote get-url origin 2>/dev/null || true)"
    case "$remote" in *github.com/bruuuuuce/mana.git) mana_root="$candidate" ;; esac
  fi
fi
[ -n "$mana_root" ] || { echo 'ERROR: Mana root not found; set MANA_ROOT or pass --mana-root' >&2; exit 2; }
mana_root="$(cd "$mana_root" 2>/dev/null && pwd -P)" || { echo 'ERROR: unreadable Mana root' >&2; exit 2; }
remote="$(git -C "$mana_root" remote get-url origin 2>/dev/null || true)"
case "$remote" in *github.com/bruuuuuce/mana.git) ;; *) echo "ERROR: not a Mana repository: $mana_root" >&2; exit 2 ;; esac
[ -x "$mana_root/scripts/bootstrap-project.sh" ] || { echo 'ERROR: Mana bootstrap path missing' >&2; exit 4; }
command -v flutter >/dev/null || { echo 'ERROR: flutter is required' >&2; exit 5; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mana-c01.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/src"
git -C "$project" init -q
git -C "$project" config user.name Mana
git -C "$project" config user.email mana@example.invalid
printf '%s\n' 'class Stale {}' > "$project/src/Stale.java"
printf '%s\n' 'class Missing {}' > "$project/src/Missing.java"
git -C "$project" add src
git -C "$project" commit -qm c01-source
head="$(git -C "$project" rev-parse HEAD)"

"$mana_root/scripts/bootstrap-project.sh" --project-root "$project" --mana-root "$mana_root" --no-jira-env >/dev/null
"$mana_root/scripts/mana-workspace.sh" init --root "$project" --feature FEAT-1 >/dev/null
mkdir -p "$project/.mana/sessions/session-1/validation" "$project/.mana/features/FEAT-1/evidence/verification/run-passed" "$project/.mana/features/FEAT-1/evidence/verification/run-failed" "$project/.mana/features/FEAT-1/evidence/repair/repair-1" "$project/.mana/runtime/events" "$project/.mana/learning/candidates"
printf '%s\n' 'workspace_type: session' 'workspace_id: session-1' > "$project/.mana/sessions/session-1/manifest.yaml"
printf '%s\n' '# Readiness' > "$project/.mana/sessions/session-1/validation/review.md"
printf '%s\n' '{"schemaVersion":"2","kind":"verification-result","runId":"run-passed","overallResult":"passed"}' > "$project/.mana/features/FEAT-1/evidence/verification/run-passed/result.json"
printf '%s\n' '{"schemaVersion":"2","kind":"verification-result","runId":"run-failed","overallResult":"failed"}' > "$project/.mana/features/FEAT-1/evidence/verification/run-failed/result.json"
printf '%s\n' '{"schemaVersion":"1","kind":"repair-attempt-result","attemptId":"repair-1","attemptStatus":"blocked"}' > "$project/.mana/features/FEAT-1/evidence/repair/repair-1/result.json"
printf '%s\n' '{"executionId":"run-history-1","timestamp":"2024-01-01T00:00:00Z","eventType":"profile.failed"}' > "$project/.mana/runtime/events/run-history-1.jsonl"
printf '%s\n' '{"schemaVersion":"2","kind":"user-context-candidate","candidateId":"learning-deadbeef","status":"candidate"}' > "$project/.mana/learning/candidates/learning-deadbeef.json"
printf '%s\n' '{not json' > "$project/.mana/legacy.json"
printf '%s\n' '{"schema":"future.inspect/v99"}' > "$project/.mana/future.json"

journey="$("$project/mana" journey create --title 'C01 Journey' --start-kind code --start-value Stale --termination-kind runtime_effect --termination-condition observed --revision "$head")"
stale_node="$("$project/mana" journey add-node "$journey" --kind code)"
missing_node="$("$project/mana" journey add-node "$journey" --kind code)"
"$project/mana" journey add-anchor "$journey" --node "$stale_node" --revision 0000000000000000000000000000000000000000 --path src/Stale.java --start-line 1 --end-line 1 --symbol Stale >/dev/null
"$project/mana" journey add-anchor "$journey" --node "$missing_node" --revision "$head" --path src/Missing.java --start-line 1 --end-line 1 --symbol Missing >/dev/null
"$project/mana" journey add-concept-occurrence "$journey" --concept-id cpt_001 --subject "$stale_node" >/dev/null
direct="$tmp/c01-journey.json"
"$project/mana" journey materialize "$journey" > "$direct"
rm "$project/src/Missing.java"

before="$(find "$project/.mana" -type f -exec shasum -a 256 {} + | LC_ALL=C sort)"
"$project/mana" inspect project --json > "$tmp/project.json"
"$project/mana" inspect artifacts --json > "$tmp/catalog.json"
after="$(find "$project/.mana" -type f -exec shasum -a 256 {} + | LC_ALL=C sort)"
[ "$before" = "$after" ] || { echo 'ERROR: inspect wrote beneath .mana' >&2; exit 6; }
! grep -Fq "$project" "$tmp/project.json" "$tmp/catalog.json" || { echo 'ERROR: inspect leaked absolute project path' >&2; exit 6; }

for run in 1 2; do
  echo "==> C01 Familiar consumer pass $run"
  (
    cd "$root"
    flutter pub get --offline
    C01_PROJECT_ROOT="$project" C01_DIRECT_ARTIFACT="$direct" \
      flutter test --no-pub test/c01_zero_token_e2e_test.dart
  )
done
echo 'C01 Mana-to-Familiar zero-token harness passed'
