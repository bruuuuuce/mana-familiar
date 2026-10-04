#!/usr/bin/env bash
# Native macOS acceptance for the process-per-window model used by Familiar.
#
# This is deliberately not a widget test: it launches two real Runner
# processes, verifies that macOS can focus each one, then closes one with the
# native Close Window shortcut and terminates the other with Quit.  It leaves
# a compact, payload-free evidence bundle behind on success and failure.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/macos/Build/Products/Debug/Mana Familiar.app"
project_root="$root"
evidence_dir=""
preferences_root=""
mana_root=""
story_start_fixture=""
ui_driver=""
first_ui_port=""
first_ui_token=""
second_ui_port=""
second_ui_token=""
exercise_decision=false
exercise_drafts=false
exercise_desktop_long=false
skip_regenerations=false
fault_wrapper=""
desktop_long_actions=300
desktop_long_duration_seconds=1200

usage() {
  cat <<'EOF'
Usage: tests/run-macos-native-window-e2e.sh [--app APP] [--project-root DIR] [--mana-root DIR] [--preferences-root DIR] [--story-start-fixture FILE] [--ui-driver FILE --first-ui-port PORT --first-ui-token TOKEN --second-ui-port PORT --second-ui-token TOKEN] [--exercise-decision|--exercise-drafts|--exercise-desktop-long] [--fault-wrapper FILE] [--evidence-dir DIR]

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
    --ui-driver) ui_driver="$2"; shift 2 ;;
    --first-ui-port) first_ui_port="$2"; shift 2 ;;
    --first-ui-token) first_ui_token="$2"; shift 2 ;;
    --second-ui-port) second_ui_port="$2"; shift 2 ;;
    --second-ui-token) second_ui_token="$2"; shift 2 ;;
    --exercise-decision) exercise_decision=true; shift ;;
    --exercise-drafts) exercise_drafts=true; shift ;;
    --exercise-desktop-long) exercise_desktop_long=true; shift ;;
    --skip-regenerations) skip_regenerations=true; shift ;;
    --fault-wrapper) fault_wrapper="$2"; shift 2 ;;
    --desktop-long-actions) desktop_long_actions="$2"; shift 2 ;;
    --desktop-long-duration-seconds) desktop_long_duration_seconds="$2"; shift 2 ;;
    --evidence-dir) evidence_dir="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

fail() {
  echo "macOS native E2E failed: $*" >&2
  [ -z "$evidence_dir" ] || [ ! -d "$evidence_dir" ] || printf 'failure=%s\n' "$*" >> "$evidence_dir/shell-errors.log"
  exit 1
}
[ "$(uname -s)" = Darwin ] || fail 'this gate requires macOS'
[ -d "$app" ] || fail "app bundle not found: $app (run: flutter build macos --debug)"
[ -d "$project_root" ] || fail "project root not found: $project_root"
[ -z "$story_start_fixture" ] || [ -f "$story_start_fixture" ] || fail "Story Start fixture is not a file: $story_start_fixture"
[ -z "$ui_driver" ] || [ -f "$ui_driver" ] || fail "UI driver is not a file: $ui_driver"
[ -z "$fault_wrapper" ] || [ -f "$fault_wrapper" ] || fail "fault wrapper is not a file: $fault_wrapper"
if [ -n "$ui_driver" ]; then
  [ -n "$first_ui_port" ] && [ -n "$first_ui_token" ] && [ -n "$second_ui_port" ] && [ -n "$second_ui_token" ] || fail 'UI driver needs a port and token for both windows'
  [ -n "$mana_root" ] && [ -n "$story_start_fixture" ] || fail 'UI driver needs Mana and a Story Start fixture'
fi
[ "$exercise_desktop_long" = false ] || {
  [ -n "$fault_wrapper" ] || fail 'desktop-long needs the test-only producer fault wrapper'
  [ -n "$mana_root" ] && [ -n "$ui_driver" ] && [ -n "$story_start_fixture" ] || fail 'desktop-long needs Mana, Story Start and the UI driver'
  [[ "$desktop_long_actions" =~ ^[1-9][0-9]*$ ]] && [ "$desktop_long_actions" -ge 300 ] || fail 'desktop-long needs at least 300 UI actions'
  [[ "$desktop_long_duration_seconds" =~ ^[1-9][0-9]*$ ]] && [ "$desktop_long_duration_seconds" -ge 1200 ] || fail 'desktop-long needs at least 1200 seconds'
}

if [ -z "$evidence_dir" ]; then
  evidence_dir="$root/build/native-e2e/macos-$(date +%s)"
fi
mkdir -p "$evidence_dir"
record_unexpected_error() {
  local status="$?"
  # Keep the exact failed shell command in the disposable evidence bundle.
  # Expected producer faults are handled inside the UI driver and therefore do
  # not reach this trap.
  printf 'exit=%s command=%s\n' "$status" "$BASH_COMMAND" \
    >> "$evidence_dir/shell-errors.log"
  exit "$status"
}
trap record_unexpected_error ERR
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
draft_fault_locked_dir=""
cleanup() {
  [ -z "$draft_fault_locked_dir" ] || chmod -R u+w "$draft_fault_locked_dir" 2>/dev/null || true
  for pid in "$first_pid" "$second_pid"; do
    [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  done
  [ -z "$created_preferences_root" ] || rm -rf "$created_preferences_root"
}
trap cleanup EXIT

prepare_fault_wrapper() {
  [ "$exercise_desktop_long" = true ] || return 0
  # The synthetic project deliberately supplies a normal project-local `mana`
  # wrapper. It only selects existing Mana test fault boundaries, then execs
  # the real producer. Product launches never receive this wrapper or env var.
  cp "$fault_wrapper" "$project_root/mana"
  chmod +x "$project_root/mana"
  mkdir -p "$project_root/.native-e2e-faults"
}

wait_for_process() {
  local pid="$1"
  local deadline=$((SECONDS + 90))
  while [ "$SECONDS" -lt "$deadline" ]; do
    kill -0 "$pid" 2>/dev/null || fail "Runner process $pid exited before creating its window"
    if osascript -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to count windows" \
      >"$evidence_dir/windows-$pid.txt" 2>"$evidence_dir/accessibility-$pid.err"; then
      [ "$(cat "$evidence_dir/windows-$pid.txt")" -ge 1 ] && return
    fi
    sleep 1
  done
  cat "$evidence_dir/accessibility-$pid.err" >&2 || true
  fail "Runner process $pid did not expose a native window within 90 seconds; see its Runner and Accessibility logs"
}

focus_and_assert() {
  local pid="$1"
  osascript \
    -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to set frontmost to true" \
    -e 'delay 0.25' \
    -e 'tell application "System Events" to return unix id of first application process whose frontmost is true' \
    >"$evidence_dir/focus-$pid.txt" 2>>"$evidence_dir/accessibility-$pid.err" || fail "could not focus native window for $pid"
  [ "$(tr -d '[:space:]' < "$evidence_dir/focus-$pid.txt")" = "$pid" ] || fail "native window $pid did not become frontmost"
}

epoch_milliseconds() {
  # macOS ships Perl with a high-resolution clock. Avoid starting Python in
  # this pre-debounce path: its cold start can itself exceed the 350 ms
  # interval being measured.
  /usr/bin/perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
}

# Values from the last real AppKit action. They are written into the draft
# evidence so the runner can prove that the close/quit request was issued
# inside the 350 ms draft debounce, rather than relying on process teardown.
native_action_sent_at=""
native_action_path=""
draft_driver_returned_at=""

send_native_action() {
  local pid="$1" action="$2" label="$3" already_focused="${4:-false}"
  local attempt count=1
  for attempt in 1 2 3; do
    if [ "$already_focused" = false ] || [ "$attempt" -gt 1 ]; then
      focus_and_assert "$pid"
    fi
    native_action_sent_at="$(epoch_milliseconds)"
    case "$action" in
      close)
        native_action_path='close-menu'
        osascript \
          -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to click menu item \"Close Window\" of menu \"File\" of menu bar item \"File\" of menu bar 1" \
          >>"$evidence_dir/native-actions.log" 2>>"$evidence_dir/accessibility-$pid.err" || fail 'could not send PID-scoped native Close'
        ;;
      quit)
        native_action_path='quit-menu'
        # The AX menu bar can include Apple before the application menu.
        # Find Quit only inside the owned process, never send a global key.
        osascript \
          -e "tell application \"System Events\" to tell (first application process whose unix id is $pid)" \
          -e 'set quitFound to false' \
          -e 'repeat with barIndex from 1 to count menu bar items of menu bar 1' \
          -e 'try' \
          -e 'click (first menu item of menu 1 of menu bar item barIndex of menu bar 1 whose name starts with "Quit ")' \
          -e 'set quitFound to true' \
          -e 'exit repeat' \
          -e 'end try' \
          -e 'end repeat' \
          -e 'if not quitFound then error "Runner Quit menu command not found"' \
          -e 'end tell' \
          >>"$evidence_dir/native-actions.log" 2>>"$evidence_dir/accessibility-$pid.err" || fail 'could not send PID-scoped native Quit'
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

regeneration_records='[]'
initialize_regeneration_records() {
  [ "$skip_regenerations" = false ] || return 0
  [ -n "$story_start_fixture" ] || return 0
  regeneration_records="$(jq -cn --arg digest "$initial_report_revision" '[{generation:0,reportRevision:$digest}]')"
}

run_regeneration() {
  local generation="$1"
  [ "$skip_regenerations" = false ] || return 0
  [ -n "$story_start_fixture" ] || return 0
  local report="$project_root/.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md"
  local current
  python3 "$story_start_fixture" --mana-root "$mana_root" --project-root "$project_root" --generation "$generation" \
    >"$evidence_dir/generation-$generation.out" 2>"$evidence_dir/generation-$generation.err" || fail "Story Start regeneration R$generation failed"
  current="$(report_digest "$report")"
  if [ "$generation" -eq 1 ]; then
    [ "$current" = "$initial_report_revision" ] || fail 'R1 was not deterministic'
  else
    [ "$current" != "$initial_report_revision" ] || fail "R$generation did not publish a changed report"
  fi
  regeneration_records="$(jq -cn --argjson records "$regeneration_records" --argjson generation "$generation" --arg digest "$current" '$records + [{generation:$generation,reportRevision:$digest}]')"
  # The directory watcher has a 750 ms debounce. A focused live Runner after
  # each publication proves that native lifecycle/focus remains intact while
  # the Observatory receives external Story Start changes.
  sleep 1
  run_ui_driver "$first_ui_port" "$first_ui_token" observe-generation "$current" "$evidence_dir/ui/generation-$generation.json"
}

write_regenerations() {
  [ "$skip_regenerations" = false ] || return 0
  jq -cn --argjson generations "$regeneration_records" '{schemaVersion:"mana.familiar.native-regenerations/v1",generations:$generations}' \
    >"$evidence_dir/regenerations.json"
}

run_regenerations() {
  [ "$skip_regenerations" = false ] || return 0
  for generation in 1 2 3 4 5; do
    run_regeneration "$generation"
  done
  write_regenerations
}

run_ui_driver() {
  local port="$1" token="$2" mode="$3" expected_revision="${4:-}" evidence="$5" draft_label="${6:-}"
  [ -n "$ui_driver" ] || return 0
  # Status settles the mounted widget tree without requiring foreground vsync.
  local driver_status=0
  local arguments=(
    "$ui_driver"
    --port "$port"
    "--token=$token"
    --project-root "$project_root"
    --mana-root "$mana_root"
    --mode "$mode"
    --evidence "$evidence"
  )
  if [ -n "$expected_revision" ]; then
    arguments+=(--expected-revision "$expected_revision")
  fi
  if [ -n "$draft_label" ]; then
    arguments+=(--draft-label "$draft_label")
  fi
  if [ "$#" -gt 6 ]; then
    shift 6
    arguments+=("$@")
  fi
  mkdir -p "$(dirname "$evidence")"
  python3 "${arguments[@]}" >"$evidence.out" 2>"$evidence.err" || driver_status=$?
  if [ "$driver_status" -ne 0 ]; then
    cat "$evidence.err" >&2 || true
    fail "native UI driver $mode failed"
  fi
}

record_pre_debounce_draft_action() {
  local label="$1" action="$2" prepared_evidence="$3" previous_pid="$4" current_pid="$5"
  local prepared elapsed
  prepared="$(jq -er '.preparedEpochMilliseconds' "$prepared_evidence")"
  [ -n "$native_action_sent_at" ] || fail "missing native action time for draft $label"
  elapsed=$((native_action_sent_at - prepared))
  printf 'draft=%s prepared=%s driver_returned=%s native_action=%s path=%s elapsed_ms=%s\n' \
    "$label" "$prepared" "$draft_driver_returned_at" "$native_action_sent_at" "$native_action_path" "$elapsed" \
    >>"$evidence_dir/native-actions.log"
  [ "$elapsed" -ge 0 ] && [ "$elapsed" -le 350 ] || fail "draft $label native $action was not sent before the 350 ms debounce ($elapsed ms)"
  case "$action:$native_action_path" in
    close:close-menu|close:close-shortcut|close:close-menu-fallback|quit:quit-menu|quit:quit-shortcut|quit:quit-menu-fallback) ;;
    *) fail "draft $label used $native_action_path instead of a native $action action" ;;
  esac
  draft_records="$(jq -cn \
    --argjson records "$draft_records" \
    --arg label "$label" \
    --arg action "$action" \
    --arg native_action_path "$native_action_path" \
    --arg previous "$previous_pid" \
    --arg current "$current_pid" \
    --argjson prepared "$prepared" \
    --argjson driver_returned "$draft_driver_returned_at" \
    --argjson sent "$native_action_sent_at" \
    --argjson elapsed "$elapsed" \
    '$records + [{label:$label,action:$action,nativeActionPath:$native_action_path,previousPid:$previous,currentPid:$current,preparedEpochMilliseconds:$prepared,driverReturnedEpochMilliseconds:$driver_returned,nativeActionSentEpochMilliseconds:$sent,elapsedBeforeDebounceMilliseconds:$elapsed}]')"
}

initial_report_revision=""
prepare_initial_generation() {
  [ -n "$story_start_fixture" ] || return 0
  local report="$project_root/.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md"
  python3 "$story_start_fixture" --mana-root "$mana_root" --project-root "$project_root" --generation 0 \
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
if [ -n "$ui_driver" ]; then
  first_arguments+=(
    --initial-artifact file:.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md
    --native-e2e-port "$first_ui_port"
    --native-e2e-token "$first_ui_token"
  )
  second_initial_artifact='file:.mana/features/FEEDBACK-E2E/planning/story-start-implementation-plan-v2.json'
  if [ "$exercise_drafts" = true ] || [ "$exercise_desktop_long" = true ]; then
    second_initial_artifact='file:.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md'
  fi
  second_arguments+=(
    --initial-artifact "$second_initial_artifact"
    --native-e2e-port "$second_ui_port"
    --native-e2e-token "$second_ui_token"
  )
fi

prepare_initial_generation
prepare_fault_wrapper
initialize_regeneration_records
first_run=0
launch_first() {
  local suffix=""
  [ "$first_run" -eq 0 ] || suffix="-restart-$first_run"
  if [ "$exercise_desktop_long" = true ]; then
    MANA_FAMILIAR_NATIVE_E2E_MANA_ROOT="$mana_root" "$app_executable" "${first_arguments[@]}" >"$evidence_dir/runner-one$suffix.out" 2>"$evidence_dir/runner-one$suffix.err" &
  else
    "$app_executable" "${first_arguments[@]}" >"$evidence_dir/runner-one$suffix.out" 2>"$evidence_dir/runner-one$suffix.err" &
  fi
  first_pid=$!
  wait_for_process "$first_pid"
}
launch_first

second_run=0
launch_second() {
  local suffix=""
  [ "$second_run" -eq 0 ] || suffix="-restart-$second_run"
  if [ "$exercise_desktop_long" = true ]; then
    MANA_FAMILIAR_NATIVE_E2E_MANA_ROOT="$mana_root" "$app_executable" "${second_arguments[@]}" >"$evidence_dir/runner-two$suffix.out" 2>"$evidence_dir/runner-two$suffix.err" &
  else
    "$app_executable" "${second_arguments[@]}" >"$evidence_dir/runner-two$suffix.out" 2>"$evidence_dir/runner-two$suffix.err" &
  fi
  second_pid=$!
  wait_for_process "$second_pid"
}
launch_second

# Focus must move in both directions; this catches a second process opening
# behind the first one as well as a broken Window-menu/Exposé registration.
focus_and_assert "$first_pid"
focus_and_assert "$second_pid"
# The debug bridge invokes mounted widget actions. Keep its Runner foreground
# while the driver selects and publishes so AppKit is not allowed to throttle
# its short scroll animation as a background window.
focus_and_assert "$first_pid"
run_ui_driver "$first_ui_port" "$first_ui_token" publish-comment "" "$evidence_dir/ui/comment.json"
if [ "$exercise_decision" = true ]; then
  focus_and_assert "$second_pid"
  run_ui_driver "$second_ui_port" "$second_ui_token" publish-decision "" "$evidence_dir/ui/decision.json"
fi
draft_records='[]'
if [ "$exercise_drafts" = true ]; then
  # A and B intentionally target the same section of the same producer
  # artifact. Distinct window sessions must retain their own text even when a
  # native Close/Quit reaches the Flutter flush handshake before debounce.
  focus_and_assert "$first_pid"
  run_ui_driver "$first_ui_port" "$first_ui_token" prepare-comment-draft "" "$evidence_dir/ui/draft-A-prepared.json" A
  draft_driver_returned_at="$(epoch_milliseconds)"
  previous_first_pid="$first_pid"
  send_native_action "$first_pid" close draft-A-close true
  first_pid=""
  first_run=$((first_run + 1))
  launch_first
  focus_and_assert "$first_pid"
  record_pre_debounce_draft_action A close "$evidence_dir/ui/draft-A-prepared.json" "$previous_first_pid" "$first_pid"
  run_ui_driver "$first_ui_port" "$first_ui_token" observe-comment-draft "" "$evidence_dir/ui/draft-A-restored.json" A

  focus_and_assert "$second_pid"
  run_ui_driver "$second_ui_port" "$second_ui_token" prepare-comment-draft "" "$evidence_dir/ui/draft-B-prepared.json" B
  draft_driver_returned_at="$(epoch_milliseconds)"
  previous_second_draft_pid="$second_pid"
  send_native_action "$second_pid" quit draft-B-quit true
  second_pid=""
  kill -0 "$first_pid" 2>/dev/null || fail 'quitting the B draft window terminated the A process'
  second_run=$((second_run + 1))
  launch_second
  focus_and_assert "$second_pid"
  record_pre_debounce_draft_action B quit "$evidence_dir/ui/draft-B-prepared.json" "$previous_second_draft_pid" "$second_pid"
  run_ui_driver "$second_ui_port" "$second_ui_token" observe-comment-draft "" "$evidence_dir/ui/draft-B-restored.json" B
fi

lifecycle_records='[]'
lifecycle_restart=0
restart_second_lifecycle() {
  local action="$1" previous_pid="$second_pid"
  # Restart B under the same session namespace. This exercises production
  # Close/Quit actions while proving neither can terminate the unrelated A.
  send_native_action "$second_pid" "$action" "restart-$((second_run + 1))-$action"
  second_pid=""
  kill -0 "$first_pid" 2>/dev/null || fail "${action}ing the second window terminated the first process"
  second_run=$((second_run + 1))
  launch_second
  focus_and_assert "$second_pid"
  lifecycle_restart=$((lifecycle_restart + 1))
  lifecycle_records="$(jq -cn --argjson records "$lifecycle_records" --argjson restart "$lifecycle_restart" --arg action "$action" --arg previous "$previous_pid" --arg current "$second_pid" '$records + [{restart:$restart,action:$action,previousPid:$previous,currentPid:$current,session:"native-e2e-B"}]')"
  if [ "$exercise_desktop_long" = true ]; then
    run_ui_driver "$second_ui_port" "$second_ui_token" prepare-long-panel "" "$evidence_dir/ui/desktop-long-panel-B-restart-$lifecycle_restart.json"
  fi
}

long_fault_records='[]'
record_desktop_long_fault() {
  local label="$1" type="$2" first="$3" second="${4:-}"
  long_fault_records="$(jq -cn --argjson records "$long_fault_records" --arg label "$label" --arg type "$type" --arg first "$first" --arg second "$second" '$records + [{label:$label,type:$type,evidence:([$first,$second] | map(select(length > 0)))}]')"
}

remove_feedback_lock() {
  local lock="$project_root/.mana/human-feedback/locks/write.lock"
  local deadline=$((SECONDS + 10))
  while [ -d "$lock" ] && [ "$SECONDS" -lt "$deadline" ]; do
    rmdir "$lock" 2>/dev/null || sleep 0.1
  done
  [ ! -e "$lock" ] || fail 'the documented Mana feedback lock recovery did not complete'
}

run_desktop_long_fault() {
  local ordinal="$1" fault_dir="$project_root/.native-e2e-faults"
  # Faults use the mounted composers themselves. Run them only after a full
  # comment/reply cycle, so they cannot overwrite a scheduled unpublished body.
  case "$ordinal" in
    8|176)
      local label="conflict-$ordinal"
      local evidence="ui/fault-$label.json"
      run_ui_driver "$first_ui_port" "$first_ui_token" fault-conflict "" "$evidence_dir/$evidence" "" \
        --fault-label "$label" --other-port "$second_ui_port" "--other-token=$second_ui_token"
      record_desktop_long_fault "$label" conflict "$evidence"
      ;;
    64|204)
      local label="ack-$ordinal"
      local marker evidence="ui/fault-$label-error.json" recovery="ui/fault-$label-recovered.json"
      marker=next-create-after-record
      [ "$ordinal" -eq 204 ] && marker=next-create-after-index
      : > "$fault_dir/$marker"
      run_ui_driver "$first_ui_port" "$first_ui_token" fault-publish-error "" "$evidence_dir/$evidence" "" \
        --fault-kind ack-loss --fault-label "$label"
      remove_feedback_lock
      run_ui_driver "$first_ui_port" "$first_ui_token" fault-retry-publish "" "$evidence_dir/$recovery" "" \
        --fault-kind ack-loss --fault-label "$label"
      record_desktop_long_fault "$label" ack-loss "$evidence" "$recovery"
      ;;
    96|232)
      local label="read-$ordinal"
      local evidence="ui/fault-$label-error.json" recovery="ui/fault-$label-recovered.json"
      : > "$fault_dir/next-read-failure"
      run_ui_driver "$first_ui_port" "$first_ui_token" fault-read-failure "" "$evidence_dir/$evidence" "" \
        --fault-label "$label"
      run_ui_driver "$first_ui_port" "$first_ui_token" fault-retry-load "" "$evidence_dir/$recovery" "" \
        --fault-label "$label"
      record_desktop_long_fault "$label" read-failure "$evidence" "$recovery"
      ;;
    12|256)
      local label="draft-$ordinal"
      local evidence="ui/fault-$label-error.json" recovery="ui/fault-$label-recovered.json"
      draft_fault_locked_dir="$preferences_root/human-feedback-drafts/native-e2e-A"
      mkdir -p "$draft_fault_locked_dir"
      chmod -R u-w "$draft_fault_locked_dir"
      run_ui_driver "$first_ui_port" "$first_ui_token" fault-publish-error "" "$evidence_dir/$evidence" "" \
        --fault-kind draft-write-failure --fault-label "$label"
      chmod -R u+w "$draft_fault_locked_dir"
      draft_fault_locked_dir=""
      run_ui_driver "$first_ui_port" "$first_ui_token" fault-retry-publish "" "$evidence_dir/$recovery" "" \
        --fault-kind draft-write-failure --fault-label "$label"
      record_desktop_long_fault "$label" draft-write-failure "$evidence" "$recovery"
      ;;
    16|280)
      local label="delayed-$ordinal"
      local evidence="ui/fault-$label.json"
      printf '%s\n' 2000 > "$fault_dir/next-create-delay-milliseconds"
      run_ui_driver "$first_ui_port" "$first_ui_token" fault-delayed-publish "" "$evidence_dir/$evidence" "" \
        --fault-label "$label" --minimum-delay-milliseconds 2000
      record_desktop_long_fault "$label" delayed-create "$evidence"
      ;;
  esac
}

run_desktop_long() {
  local actions_file="$evidence_dir/ui/desktop-long-actions.ndjson"
  local started ended now due delay ordinal slot sequence action port token evidence
  : > "$actions_file"
  run_ui_driver "$second_ui_port" "$second_ui_token" prepare-long-panel "" "$evidence_dir/ui/desktop-long-panel-B.json"
  started="$(epoch_milliseconds)"
  for ((ordinal = 1; ordinal <= desktop_long_actions; ordinal++)); do
    due=$((started + (desktop_long_duration_seconds * 1000 * (ordinal - 1) / (desktop_long_actions - 1))))
    now="$(epoch_milliseconds)"
    delay=$((due - now))
    if [ "$delay" -gt 0 ]; then
      /usr/bin/perl -e "select undef, undef, undef, $delay / 1000"
    fi
    slot=$(((ordinal - 1) % 4))
    sequence=$(((ordinal - 1) / 4 + 1))
    case "$slot" in
      0) action=set-comment ;;
      1) action=publish-comment ;;
      2) action=set-reply ;;
      3) action=publish-reply ;;
    esac
    if [ $((sequence % 2)) -eq 1 ]; then
      port="$first_ui_port"; token="$first_ui_token"
    else
      port="$second_ui_port"; token="$second_ui_token"
    fi
    evidence="$evidence_dir/ui/desktop-long-action-$(printf '%03d' "$ordinal").json"
    run_ui_driver "$port" "$token" desktop-long-action "" "$evidence" "" \
      --long-action "$action" --sequence "$sequence"
    ended="$(epoch_milliseconds)"
    jq -c --argjson ordinal "$ordinal" --argjson due "$due" --argjson completed "$ended" \
      '. + {ordinal:$ordinal,scheduledEpochMilliseconds:$due,completedEpochMilliseconds:$completed}' \
      "$evidence" >> "$actions_file"

    case "$ordinal" in
      50) run_regeneration 1 ;;
      110) run_regeneration 2 ;;
      170) run_regeneration 3 ;;
      230) run_regeneration 4 ;;
      290) run_regeneration 5 ;;
      80) restart_second_lifecycle close ;;
      160) restart_second_lifecycle quit ;;
      240) restart_second_lifecycle close ;;
    esac
    run_desktop_long_fault "$ordinal"
  done
  due=$((started + desktop_long_duration_seconds * 1000))
  now="$(epoch_milliseconds)"
  delay=$((due - now))
  if [ "$delay" -gt 0 ]; then
    /usr/bin/perl -e "select undef, undef, undef, $delay / 1000"
  fi
  ended="$(epoch_milliseconds)"
  write_regenerations
  jq -cn \
    --argjson started "$started" \
    --argjson ended "$ended" \
    --argjson scheduled "$desktop_long_actions" \
    --argjson minimum_duration "$desktop_long_duration_seconds" \
    --argjson faults "$long_fault_records" \
    --slurpfile actions "$actions_file" \
    '{schemaVersion:"mana.familiar.native-desktop-long/v1",status:"passed",startedEpochMilliseconds:$started,endedEpochMilliseconds:$ended,scheduledUiActionCount:$scheduled,minimumDurationSeconds:$minimum_duration,actions:$actions,faults:$faults}' \
    > "$evidence_dir/desktop-long.json"
}

if [ "$exercise_desktop_long" = true ]; then
  run_desktop_long
  [ "$lifecycle_restart" -eq 3 ] || fail 'desktop-long did not execute its three native restarts'
else
  run_regenerations
  for action in close quit close; do
    restart_second_lifecycle "$action"
  done
fi

if [ "$exercise_drafts" = true ]; then
  focus_and_assert "$first_pid"
  run_ui_driver "$first_ui_port" "$first_ui_token" observe-comment-draft "" "$evidence_dir/ui/draft-A-after-B-restarts.json" A
  focus_and_assert "$second_pid"
  run_ui_driver "$second_ui_port" "$second_ui_token" observe-comment-draft "" "$evidence_dir/ui/draft-B-after-restarts.json" B
  jq -cn --argjson drafts "$draft_records" \
    '{schemaVersion:"mana.familiar.native-drafts/v1",drafts:$drafts}' \
    >"$evidence_dir/drafts.json"
fi

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
