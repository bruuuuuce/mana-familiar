#!/usr/bin/env bash
# Test-only project wrapper for the desktop-long native gate.
#
# The runner copies this file into its synthetic project as `mana`, so the
# production Familiar repository still follows its normal wrapper-preferred
# resolution. Markers are local to that disposable project and select one
# real Mana fault boundary for the next matching command. The wrapper never
# invents a producer response: it execs Mana's actual human-feedback command.
set -euo pipefail

project_root="$(cd "$(dirname "$0")" && pwd -P)"
mana_root="${MANA_FAMILIAR_NATIVE_E2E_MANA_ROOT:-}"
fault_root="$project_root/.native-e2e-faults"

[ -n "$mana_root" ] || {
  echo 'native desktop-long fault wrapper needs MANA_FAMILIAR_NATIVE_E2E_MANA_ROOT' >&2
  exit 64
}
case "${1:-}" in
  inspect)
    # Familiar's normal project-wrapper preference applies to inspect as well.
    # Keep that real producer path intact; only human-feedback receives a
    # one-shot fault marker below.
    shift
    exec "$mana_root/scripts/mana-inspect.sh" --project-root "$project_root" "$@"
    ;;
  human-feedback)
    shift
    ;;
  *)
    echo 'native desktop-long fault wrapper only supports mana inspect and human-feedback' >&2
    exit 64
    ;;
esac
operation="${1:-}"

consume() {
  local name="$1"
  [ -f "$fault_root/$name" ] || return 1
  rm -f "$fault_root/$name"
  return 0
}

case "$operation" in
  reply)
    if consume next-reply-barrier; then
      : > "$fault_root/reply-barrier-entered"
      deadline=$((SECONDS + 60))
      while [ ! -f "$fault_root/reply-barrier-release" ]; do
        [ "$SECONDS" -lt "$deadline" ] || { echo 'native reply barrier timed out' >&2; exit 70; }
        sleep 0.05
      done
      rm -f "$fault_root/reply-barrier-entered" "$fault_root/reply-barrier-release"
    fi
    ;;
  create)
    if consume next-create-after-record; then
      export MANA_HUMAN_FEEDBACK_TEST_ABORT_AFTER_RECORD=1
    elif consume next-create-after-index; then
      export MANA_HUMAN_FEEDBACK_TEST_ABORT_AFTER_CANONICAL_BEFORE_INDEX=1
    elif [ -f "$fault_root/next-create-delay-milliseconds" ]; then
      delay="$(tr -d '[:space:]' < "$fault_root/next-create-delay-milliseconds")"
      rm -f "$fault_root/next-create-delay-milliseconds"
      [[ "$delay" =~ ^[1-9][0-9]*$ ]] || {
        echo 'invalid native desktop-long delay marker' >&2
        exit 64
      }
      /usr/bin/perl -e "select undef, undef, undef, $delay / 1000"
    fi
    ;;
  list|list-history)
    if consume next-read-failure; then
      echo 'native desktop-long injected read failure' >&2
      exit 70
    fi
    ;;
esac

exec "$mana_root/scripts/mana-human-feedback.sh" --project-root "$project_root" "$operation" "${@:2}"
