#!/usr/bin/env bash
# Native macOS acceptance for the process-per-window model used by Familiar.
#
# This is deliberately not a widget test: it launches two real Runner
# processes, verifies that macOS can focus each one, then closes one with the
# native Close Window shortcut and terminates the other with Quit.  It leaves
# a compact, payload-free evidence bundle behind on success and failure.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/macos/Build/Products/Debug/Mana Familiar.app"
project_root="$root"
evidence_dir=""
preferences_root=""
mana_root=""
story_start_fixture=""

usage() {
  cat <<'EOF'
Usage: tests/run-macos-native-window-e2e.sh [--app APP] [--project-root DIR] [--mana-root DIR] [--preferences-root DIR] [--story-start-fixture FILE] [--evidence-dir DIR]

The caller must grant this shell Accessibility permission (System Settings >
Privacy & Security > Accessibility). The permission is required to exercise
real focus and the native Cmd-W/Cmd-Q lifecycle, rather than killing a test
process from the shell.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) app="$2"; shift 2 ;;
    --project-root) project_root="$2"; shift 2 ;;
    --mana-root) mana_root="$2"; shift 2 ;;
    --preferences-root) preferences_root="$2"; shift 2 ;;
    --story-start-fixture) story_start_fixture="$2"; shift 2 ;;
    --evidence-dir) evidence_dir="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

fail() { echo "macOS native E2E failed: $*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail 'this gate requires macOS'
[ -d "$app" ] || fail "app bundle not found: $app (run: flutter build macos --debug)"
[ -d "$project_root" ] || fail "project root not found: $project_root"
[ -z "$story_start_fixture" ] || [ -x "$story_start_fixture" ] || fail "Story Start fixture is not executable: $story_start_fixture"

if [ -z "$evidence_dir" ]; then
  evidence_dir="$root/build/native-e2e/macos-$(date +%s)"
fi
mkdir -p "$evidence_dir"
app_executable="$app/Contents/MacOS/$(defaults read "$app/Contents/Info" CFBundleExecutable)"
[ -x "$app_executable" ] || fail "app executable not found: $app_executable"

# Both Runner processes observe the same project. Their independent session
# identifiers and a temporary preferences root prevent draft/recents leakage
# between windows or into the user's application support directory.
created_preferences_root=""
if [ -z "$preferences_root" ]; then
  preferences_root="$(mktemp -d "${TMPDIR:-/tmp}/mana-familiar-native-e2e.XXXXXX")"
  created_preferences_root="$preferences_root"
fi
mkdir -p "$preferences_root"
first_pid=""
second_pid=""
cleanup() {
  for pid in "$first_pid" "$second_pid"; do
    [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  done
  [ -z "$created_preferences_root" ] || rm -rf "$created_preferences_root"
}
trap cleanup EXIT

wait_for_process() {
  local pid="$1"
  local deadline=$((SECONDS + 30))
  while [ "$SECONDS" -lt "$deadline" ]; do
    kill -0 "$pid" 2>/dev/null || fail "Runner process $pid exited before creating its window"
    if osascript -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to count windows" \
      >"$evidence_dir/windows-$pid.txt" 2>"$evidence_dir/accessibility-$pid.err"; then
      [ "$(cat "$evidence_dir/windows-$pid.txt")" -ge 1 ] && return
    fi
    sleep 1
  done
  cat "$evidence_dir/accessibility-$pid.err" >&2 || true
  fail "Runner process $pid did not expose a native window; grant Accessibility to this shell"
}

focus_and_assert() {
  local pid="$1"
  osascript \
    -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to set frontmost to true" \
    -e "tell application \"System Events\" to return frontmost of (first application process whose unix id is $pid)" \
    >"$evidence_dir/focus-$pid.txt" 2>>"$evidence_dir/accessibility-$pid.err" || fail "could not focus native window for $pid"
  [ "$(tr -d '[:space:]' < "$evidence_dir/focus-$pid.txt")" = true ] || fail "native window $pid did not become frontmost"
}

send_native_action() {
  local pid="$1" action="$2" label="$3"
  local attempt count=1
  for attempt in 1 2 3; do
    focus_and_assert "$pid"
    case "$action" in
      close)
        osascript -e 'tell application "System Events" to key code 13 using command down' \
          >>"$evidence_dir/native-actions.log" 2>>"$evidence_dir/accessibility-$pid.err" || fail 'could not send native Cmd-W'
        ;;
      quit)
        osascript -e 'tell application "System Events" to key code 12 using command down' \
          >>"$evidence_dir/native-actions.log" 2>>"$evidence_dir/accessibility-$pid.err" || fail 'could not send native Cmd-Q'
        ;;
      *) fail "unknown native lifecycle action: $action" ;;
    esac
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
      count=0
    else
      count="$(osascript -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to count windows" \
        2>>"$evidence_dir/accessibility-$pid.err" || printf 1)"
    fi
    printf '%s\n' "$count" >"$evidence_dir/windows-after-$label-$pid-attempt-$attempt.txt"
    [ "$count" -eq 0 ] && break
  done
  cp "$evidence_dir/windows-after-$label-$pid-attempt-$attempt.txt" \
    "$evidence_dir/windows-after-$label-$pid.txt"
  wait_for_exit "$pid"
}

wait_for_exit() {
  local pid="$1"
  local deadline=$((SECONDS + 15))
  while [ "$SECONDS" -lt "$deadline" ]; do
    # A direct child remains visible to kill(2) as a zombie until this shell
    # reaps it. Treat that as a completed native termination, then wait to
    # release the PID instead of misreporting a successful Cmd-W/Cmd-Q.
    local state
    # `ps` returns non-zero after the child has gone away. Preserve that
    # expected state under `set -e` so the check below can classify it.
    state="$(ps -o stat= -p "$pid" 2>/dev/null || true)"
    state="${state//[[:space:]]/}"
    if [ -z "$state" ] || [[ "$state" == Z* ]]; then
      wait "$pid" 2>/dev/null || true
      return
    fi
    sleep 1
  done
  fail "Runner process $pid survived native lifecycle action"
}

report_digest() {
  local report="$1"
  if command -v sha256sum >/dev/null; then
    sha256sum "$report" | awk '{print "sha256:"$1}'
  else
    shasum -a 256 "$report" | awk '{print "sha256:"$1}'
  fi
}

run_regenerations() {
  [ -n "$story_start_fixture" ] || return 0
  local report="$project_root/.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md"
  local current records
  records="$(jq -cn --argjson generation 0 --arg digest "$initial_report_revision" '[{generation:$generation,reportRevision:$digest}]')"
  for generation in 1 2 3 4 5; do
    "$story_start_fixture" --project-root "$project_root" --generation "$generation" \
      >"$evidence_dir/generation-$generation.out" 2>"$evidence_dir/generation-$generation.err" || fail "Story Start regeneration R$generation failed"
    current="$(report_digest "$report")"
    if [ "$generation" -eq 1 ]; then
      [ "$current" = "$initial_report_revision" ] || fail 'R1 was not deterministic'
    else
      [ "$current" != "$initial_report_revision" ] || fail "R$generation did not publish a changed report"
    fi
    records="$(jq -cn --argjson records "$records" --argjson generation "$generation" --arg digest "$current" '$records + [{generation:$generation,reportRevision:$digest}]')"
    # The directory watcher has a 750 ms debounce. A focused live Runner after
    # each publication proves that native lifecycle/focus remains intact while
    # the Observatory receives external Story Start changes.
    sleep 1
    focus_and_assert "$first_pid"
    focus_and_assert "$second_pid"
  done
  jq -cn --argjson generations "$records" '{schemaVersion:"mana.familiar.native-regenerations/v1",generations:$generations}' \
    >"$evidence_dir/regenerations.json"
}

initial_report_revision=""
prepare_initial_generation() {
  [ -n "$story_start_fixture" ] || return 0
  local report="$project_root/.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md"
  "$story_start_fixture" --project-root "$project_root" --generation 0 \
    >"$evidence_dir/generation-0.out" 2>"$evidence_dir/generation-0.err" || fail 'initial Story Start fixture publication failed'
  [ -f "$report" ] || fail 'initial Story Start report is missing'
  initial_report_revision="$(report_digest "$report")"
}

first_arguments=(--project-root "$project_root" --preferences-root "$preferences_root" --window-session native-e2e-A)
second_arguments=(--project-root "$project_root" --preferences-root "$preferences_root" --window-session native-e2e-B)
if [ -n "$mana_root" ]; then
  first_arguments+=(--mana-root "$mana_root")
  second_arguments+=(--mana-root "$mana_root")
fi

prepare_initial_generation
"$app_executable" "${first_arguments[@]}" >"$evidence_dir/runner-one.out" 2>"$evidence_dir/runner-one.err" &
first_pid=$!
wait_for_process "$first_pid"

second_run=0
launch_second() {
  local suffix=""
  [ "$second_run" -eq 0 ] || suffix="-restart-$second_run"
  "$app_executable" "${second_arguments[@]}" >"$evidence_dir/runner-two$suffix.out" 2>"$evidence_dir/runner-two$suffix.err" &
  second_pid=$!
  wait_for_process "$second_pid"
}
launch_second

# Focus must move in both directions; this catches a second process opening
# behind the first one as well as a broken Window-menu/Exposé registration.
focus_and_assert "$first_pid"
focus_and_assert "$second_pid"
run_regenerations

# Restart B three times under the same session namespace. This exercises the
# production Close and Quit actions against live native windows, while proving
# that neither action can terminate the unrelated A process.
lifecycle_records='[]'
for action in close quit close; do
  previous_pid="$second_pid"
  send_native_action "$second_pid" "$action" "restart-$((second_run + 1))-$action"
  second_pid=""
  kill -0 "$first_pid" 2>/dev/null || fail "${action}ing the second window terminated the first process"
  second_run=$((second_run + 1))
  launch_second
  focus_and_assert "$second_pid"
  lifecycle_records="$(jq -cn --argjson records "$lifecycle_records" --argjson restart "$second_run" --arg action "$action" --arg previous "$previous_pid" --arg current "$second_pid" '$records + [{restart:$restart,action:$action,previousPid:$previous,currentPid:$current,session:"native-e2e-B"}]')"
done

# Finish the live B window with the native Close action. A remains independently
# focusable until its final Quit below.
final_second_pid="$second_pid"
send_native_action "$second_pid" close final-close
second_pid=""
kill -0 "$first_pid" 2>/dev/null || fail 'closing the second window terminated the first process'
focus_and_assert "$first_pid"
jq -cn --argjson restarts "$lifecycle_records" --arg final "$final_second_pid" \
  '{schemaVersion:"mana.familiar.native-lifecycle/v1",restarts:$restarts,finalSecondPid:$final}' \
  >"$evidence_dir/lifecycle.json"

# Cmd-Q validates the real application termination path, including Flutter
# dispose and the draft-store flush it invokes.
send_native_action "$first_pid" quit final-quit
first_pid=""

printf '%s\n' "passed" >"$evidence_dir/result.txt"
printf 'macOS native multi-window E2E passed: %s\n' "$evidence_dir"
