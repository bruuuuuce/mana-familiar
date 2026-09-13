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

usage() {
  cat <<'EOF'
Usage: tests/run-macos-native-window-e2e.sh [--app APP] [--project-root DIR] [--evidence-dir DIR]

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
    --evidence-dir) evidence_dir="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

fail() { echo "macOS native E2E failed: $*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail 'this gate requires macOS'
[ -d "$app" ] || fail "app bundle not found: $app (run: flutter build macos --debug)"
[ -d "$project_root" ] || fail "project root not found: $project_root"

if [ -z "$evidence_dir" ]; then
  evidence_dir="$root/build/native-e2e/macos-$(date +%s)"
fi
mkdir -p "$evidence_dir"
app_executable="$app/Contents/MacOS/$(defaults read "$app/Contents/Info" CFBundleExecutable)"
[ -x "$app_executable" ] || fail "app executable not found: $app_executable"

# Separate roots make the two native window titles distinguishable after
# Flutter has delivered the project name to the macOS bridge. The second root
# need not contain generated artifacts: this gate owns window lifecycle, not
# the producer's content contract (covered by C03 and Mana's Story Start gate).
second_project="$(mktemp -d "${TMPDIR:-/tmp}/mana-familiar-native-e2e.XXXXXX")"
first_pid=""
second_pid=""
cleanup() {
  for pid in "$first_pid" "$second_pid"; do
    [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  done
  rm -rf "$second_project"
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

"$app_executable" --project-root "$project_root" >"$evidence_dir/runner-one.out" 2>"$evidence_dir/runner-one.err" &
first_pid=$!
wait_for_process "$first_pid"

"$app_executable" --project-root "$second_project" >"$evidence_dir/runner-two.out" 2>"$evidence_dir/runner-two.err" &
second_pid=$!
wait_for_process "$second_pid"

# Focus must move in both directions; this catches a second process opening
# behind the first one as well as a broken Window-menu/Exposé registration.
focus_and_assert "$first_pid"
focus_and_assert "$second_pid"

# Cmd-W is the production Close Window path installed by AppDelegate. Because
# the application terminates after its last window closes, only Runner two may
# exit here; Runner one must remain alive and focusable.
osascript -e 'tell application "System Events" to key code 13 using command down' \
  >>"$evidence_dir/native-actions.log" 2>>"$evidence_dir/accessibility-$second_pid.err" || fail 'could not send native Cmd-W'
wait_for_exit "$second_pid"
second_pid=""
kill -0 "$first_pid" 2>/dev/null || fail 'closing the second window terminated the first process'
focus_and_assert "$first_pid"

# Cmd-Q validates the real application termination path, including Flutter
# dispose and the draft-store flush it invokes.
osascript -e 'tell application "System Events" to key code 12 using command down' \
  >>"$evidence_dir/native-actions.log" 2>>"$evidence_dir/accessibility-$first_pid.err" || fail 'could not send native Cmd-Q'
wait_for_exit "$first_pid"
first_pid=""

printf '%s\n' "passed" >"$evidence_dir/result.txt"
printf 'macOS native multi-window E2E passed: %s\n' "$evidence_dir"
