import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


RUNNER = Path(__file__).with_name("run-native-feedback-e2e.py")
SPEC = importlib.util.spec_from_file_location("native_feedback_runner", RUNNER)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
UI_SPEC = importlib.util.spec_from_file_location(
    "native_feedback_ui_driver", RUNNER.with_name("run-native-feedback-ui-driver.py")
)
assert UI_SPEC and UI_SPEC.loader
ui_driver = importlib.util.module_from_spec(UI_SPEC)
UI_SPEC.loader.exec_module(ui_driver)


class NativeFeedbackRunnerTest(unittest.TestCase):
    def test_long_composer_rejects_changes_before_publishing(self) -> None:
        status = {"panel": {"composer": {"author": ui_driver.LONG_AUTHOR, "body": "scheduled"}}}
        ui_driver.require_long_composer(status, "scheduled")
        for field in ("author", "body"):
            changed = json.loads(json.dumps(status))
            changed["panel"]["composer"][field] = "external edit"
            with self.assertRaisesRegex(AssertionError, "composer changed"):
                ui_driver.require_long_composer(changed, "scheduled")

    def test_conflict_observation_allows_changed_history_without_relabeling_it(self) -> None:
        thread = {
            "linkState": "changed",
            "entries": [{"author": "Native desktop-long", "body": "reply"}],
        }
        status = {"panel": {"loading": False, "threads": [thread]}}
        arguments = {"body": "reply", "author": "Native desktop-long"}
        self.assertFalse(ui_driver.visible_entry(status, **arguments))
        self.assertTrue(ui_driver.visible_entry(
            status, **arguments, link_states=("valid", "changed")
        ))
        self.assertEqual(thread["linkState"], "changed")
        for state in ("missing", "ambiguous", "unknown"):
            thread["linkState"] = state
            self.assertFalse(ui_driver.visible_entry(
                status, **arguments, link_states=("valid", "changed")
            ))

    def test_shell_passes_dash_prefixed_tokens_without_changing_focus(self) -> None:
        shell = RUNNER.with_name("run-macos-native-window-e2e.sh").read_text(
            encoding="utf-8"
        )
        driver_function = shell.split("run_ui_driver() {", 1)[1].split(
            "\nrecord_pre_debounce_draft_action() {", 1
        )[0]
        script = """
set -euo pipefail
project_root="$1" mana_root="$1" evidence_dir="$1"
first_ui_port=10001 first_pid=42 second_ui_port=10002 second_pid=43
ui_driver="$1/parser.py"
fail() { exit 1; }
focus_and_assert() { exit 99; }
printf 'unchanged\n' > "$project_root/focused"
osascript() { :; }
""" + "\nrun_ui_driver() {" + driver_function + """
run_ui_driver 10001 -primary observe-generation "" "$evidence_dir/driver.json" "" \
  --other-port 10002 --other-token=-secondary
run_ui_driver 10002 -secondary prepare-long-panel "" "$evidence_dir/secondary.json" "" \
  --other-port 10001 --other-token=-primary
"""
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "parser.py").write_text(
                "import argparse, json\n"
                "from pathlib import Path\n"
                "parser = argparse.ArgumentParser()\n"
                "parser.add_argument('--token', required=True)\n"
                "parser.add_argument('--other-token', required=True)\n"
                "parser.add_argument('--port', required=True, type=int)\n"
                "parser.add_argument('--project-root', required=True)\n"
                "args, _ = parser.parse_known_args()\n"
                "expected = 'unchanged'\n"
                "assert (Path(args.project_root) / 'focused').read_text().strip() == expected\n"
                "print(json.dumps([args.token, args.other_token]))\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                ["bash", "-c", script, "token-argument-test", temporary],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            parsed = json.loads((directory / "driver.json.out").read_text())
            self.assertEqual(parsed, ["-primary", "-secondary"])
            secondary = json.loads((directory / "secondary.json.out").read_text())
            self.assertEqual(secondary, ["-secondary", "-primary"])

    def test_shell_dispatches_all_faults_with_scoped_evidence_paths(self) -> None:
        shell = RUNNER.with_name("run-macos-native-window-e2e.sh").read_text(
            encoding="utf-8"
        )
        fault_function = shell.split("run_desktop_long_fault() {", 1)[1].split(
            "\nrun_desktop_long() {", 1
        )[0]
        script = """
set -euo pipefail
project_root="$1"
preferences_root="$1/preferences"
evidence_dir="$1/evidence"
first_ui_port=10001 first_ui_token=primary
second_ui_port=10002 second_ui_token=secondary
mkdir -p "$project_root/.native-e2e-faults"
mkdir -p "$preferences_root/human-feedback-drafts/native-e2e-A/existing/document"
run_ui_driver() {
  printf '%s %s\n' "$3" "${5##*/}"
  case "${5##*/}" in
    fault-draft-*-error.json)
      python3 -c 'import pathlib, stat, sys; assert not (pathlib.Path(sys.argv[1]).stat().st_mode & stat.S_IWUSR)' \
        "$preferences_root/human-feedback-drafts/native-e2e-A/existing/document"
      ;;
    fault-draft-*-recovered.json)
      python3 -c 'import pathlib, stat, sys; assert pathlib.Path(sys.argv[1]).stat().st_mode & stat.S_IWUSR' \
        "$preferences_root/human-feedback-drafts/native-e2e-A/existing/document"
      ;;
  esac
}
record_desktop_long_fault() { :; }
remove_feedback_lock() { :; }
""" + "\nrun_desktop_long_fault() {" + fault_function + """
for ((ordinal = 1; ordinal <= 300; ordinal++)); do
  run_desktop_long_fault "$ordinal"
done
"""
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(
                ["bash", "-c", script, "fault-dispatch-test", temporary],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = []
        for ordinal, kind in (
            (8, "conflict"), (12, "draft"), (16, "delayed"),
            (64, "ack"), (96, "read"), (176, "conflict"),
            (204, "ack"), (232, "read"), (256, "draft"), (280, "delayed"),
        ):
            if kind in ("conflict", "delayed"):
                mode = "fault-conflict" if kind == "conflict" else "fault-delayed-publish"
                expected.append(f"{mode} fault-{kind}-{ordinal}.json")
            else:
                error_mode = "fault-read-failure" if kind == "read" else "fault-publish-error"
                retry_mode = "fault-retry-load" if kind == "read" else "fault-retry-publish"
                expected.extend((
                    f"{error_mode} fault-{kind}-{ordinal}-error.json",
                    f"{retry_mode} fault-{kind}-{ordinal}-recovered.json",
                ))
        self.assertEqual(result.stdout.splitlines(), expected)

    @staticmethod
    def _write_complete_native_evidence(directory: Path) -> None:
        generations = [
            {"generation": 0, "reportRevision": "same"},
            {"generation": 1, "reportRevision": "same"},
            {"generation": 2, "reportRevision": "two"},
            {"generation": 3, "reportRevision": "three"},
            {"generation": 4, "reportRevision": "four"},
            {"generation": 5, "reportRevision": "five"},
        ]
        (directory / "regenerations.json").write_text(
            json.dumps({"generations": generations}), encoding="utf-8"
        )
        (directory / "lifecycle.json").write_text(
            json.dumps(
                {
                    "restarts": [
                        {
                            "restart": 1,
                            "action": "close",
                            "session": "native-e2e-B",
                            "previousPid": 1,
                            "currentPid": 2,
                        },
                        {
                            "restart": 2,
                            "action": "quit",
                            "session": "native-e2e-B",
                            "previousPid": 2,
                            "currentPid": 3,
                        },
                        {
                            "restart": 3,
                            "action": "close",
                            "session": "native-e2e-B",
                            "previousPid": 3,
                            "currentPid": 4,
                        },
                    ]
                }
            ),
            encoding="utf-8",
        )
        ui = directory / "ui"
        ui.mkdir()
        (ui / "comment.json").write_text(
            json.dumps(
                {
                    "status": "passed",
                    "mode": "publish-comment",
                    "inputMode": "flutter-widget-bridge",
                    "uiActionCount": 6,
                    "canonicalThreadId": "thread_1",
                }
            ),
            encoding="utf-8",
        )
        (ui / "decision.json").write_text(
            json.dumps(
                {
                    "status": "passed",
                    "mode": "publish-decision",
                    "inputMode": "flutter-widget-bridge",
                    "uiActionCount": 3,
                    "decisionId": "decision-1",
                    "optionId": "option-a",
                }
            ),
            encoding="utf-8",
        )
        for label, action, after_restart in (
            ("A", "close", "draft-A-after-B-restarts.json"),
            ("B", "quit", "draft-B-after-restarts.json"),
        ):
            body_sha = f"draft-{label.lower()}"
            (ui / f"draft-{label}-prepared.json").write_text(
                json.dumps(
                    {
                        "status": "passed",
                        "mode": "prepare-comment-draft",
                        "draftLabel": label,
                        "bodySha256": body_sha,
                    }
                ),
                encoding="utf-8",
            )
            for name in (f"draft-{label}-restored.json", after_restart):
                (ui / name).write_text(
                    json.dumps(
                        {
                            "status": "passed",
                            "mode": "observe-comment-draft",
                            "draftLabel": label,
                            "bodySha256": body_sha,
                        }
                    ),
                    encoding="utf-8",
                )
        (directory / "drafts.json").write_text(
            json.dumps(
                {
                    "drafts": [
                        {
                            "label": "A",
                            "action": "close",
                            "nativeActionPath": "close-menu-fallback",
                            "previousPid": "10",
                            "currentPid": "11",
                            "preparedEpochMilliseconds": 1,
                            "driverReturnedEpochMilliseconds": 2,
                            "nativeActionSentEpochMilliseconds": 3,
                            "elapsedBeforeDebounceMilliseconds": 25,
                        },
                        {
                            "label": "B",
                            "action": "quit",
                            "nativeActionPath": "quit-shortcut",
                            "previousPid": "12",
                            "currentPid": "13",
                            "preparedEpochMilliseconds": 4,
                            "driverReturnedEpochMilliseconds": 5,
                            "nativeActionSentEpochMilliseconds": 6,
                            "elapsedBeforeDebounceMilliseconds": 30,
                        },
                    ]
                }
            ),
            encoding="utf-8",
        )
        for generation in generations[1:]:
            (ui / f"generation-{generation['generation']}.json").write_text(
                json.dumps(
                    {
                        "status": "passed",
                        "mode": "observe-generation",
                        "document": {
                            "artifactRevision": generation["reportRevision"]
                        },
                    }
                ),
                encoding="utf-8",
            )

    @staticmethod
    def _write_desktop_long_evidence(directory: Path) -> None:
        ui = directory / "ui"
        actions = [
            {
                "status": "passed",
                "mode": "desktop-long-action",
                "inputMode": "flutter-widget-bridge",
                "uiActionCount": 1,
                "ordinal": ordinal,
                "longAction": (
                    "set-comment",
                    "publish-comment",
                    "set-reply",
                    "publish-reply",
                )[(ordinal - 1) % 4],
                "scheduledEpochMilliseconds": ordinal * 4_000,
                "completedEpochMilliseconds": ordinal * 4_000,
            }
            for ordinal in range(1, 301)
        ]
        faults = []
        for kind in (
            "conflict",
            "ack-loss",
            "read-failure",
            "draft-write-failure",
            "delayed-create",
        ):
            for number in (1, 2):
                label = f"{kind}-{number}"
                first = f"ui/long-{label}-first.json"
                evidence = [first]
                first_value = {
                    "status": "passed",
                    "inputMode": "flutter-widget-bridge",
                    "faultKind": kind,
                    "faultLabel": label,
                }
                if kind == "conflict":
                    first_value.update(
                        mode="fault-conflict", canonicalCountsAfterRecovery=[1, 1]
                    )
                elif kind in ("ack-loss", "draft-write-failure"):
                    first_value.update(
                        mode="fault-publish-error",
                        canonicalCountBeforeRecovery=1 if kind == "ack-loss" else 0,
                    )
                    recovered = f"ui/long-{label}-recovered.json"
                    (directory / recovered).write_text(
                        json.dumps(
                            {
                                "status": "passed",
                                "mode": "fault-retry-publish",
                                "inputMode": "flutter-widget-bridge",
                                "faultKind": kind,
                                "faultLabel": label,
                                "canonicalCountAfterRecovery": 1,
                            }
                        ),
                        encoding="utf-8",
                    )
                    evidence.append(recovered)
                elif kind == "read-failure":
                    first_value.update(mode="fault-read-failure")
                    recovered = f"ui/long-{label}-recovered.json"
                    (directory / recovered).write_text(
                        json.dumps(
                            {
                                "status": "passed",
                                "mode": "fault-retry-load",
                                "inputMode": "flutter-widget-bridge",
                                "faultKind": kind,
                                "faultLabel": label,
                            }
                        ),
                        encoding="utf-8",
                    )
                    evidence.append(recovered)
                else:
                    first_value.update(
                        mode="fault-delayed-publish",
                        elapsedMilliseconds=2_000,
                        canonicalCountAfterRecovery=1,
                    )
                (directory / first).write_text(json.dumps(first_value), encoding="utf-8")
                faults.append({"label": label, "type": kind, "evidence": evidence})
        (directory / "desktop-long.json").write_text(
            json.dumps(
                {
                    "schemaVersion": "mana.familiar.native-desktop-long/v1",
                    "status": "passed",
                    "startedEpochMilliseconds": 0,
                    "endedEpochMilliseconds": 1_200_000,
                    "scheduledUiActionCount": 300,
                    "minimumDurationSeconds": 1_200,
                    "actions": actions,
                    "faults": faults,
                }
            ),
            encoding="utf-8",
        )

    def test_writes_json_atomically(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "evidence.json"
            runner.write_json(path, {"status": "passed"})
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                '{\n  "status": "passed"\n}',
            )

    def test_rejects_incomplete_lifecycle_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "regenerations.json").write_text(
                json.dumps(
                    {
                        "generations": [
                            {"generation": 0, "reportRevision": "same"},
                            {"generation": 1, "reportRevision": "same"},
                            {"generation": 2, "reportRevision": "two"},
                            {"generation": 3, "reportRevision": "three"},
                            {"generation": 4, "reportRevision": "four"},
                            {"generation": 5, "reportRevision": "five"},
                        ]
                    }
                ),
                encoding="utf-8",
            )
            (directory / "lifecycle.json").write_text(
                json.dumps({"restarts": []}), encoding="utf-8"
            )
            with self.assertRaisesRegex(AssertionError, "three restarts"):
                runner.validate_native_evidence(directory)

    def test_requires_ui_observation_for_the_full_native_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self._write_complete_native_evidence(directory)
            runner.validate_native_evidence(directory, require_ui=True)

            (directory / "ui" / "generation-5.json").unlink()
            with self.assertRaises(FileNotFoundError):
                runner.validate_native_evidence(directory, require_ui=True)

    def test_accepts_the_separate_decision_smoke_without_regenerations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self._write_complete_native_evidence(directory)
            (directory / "regenerations.json").unlink()
            runner.validate_native_evidence(
                directory,
                require_ui=True,
                require_regenerations=False,
                require_decision=True,
            )

    def test_requires_both_native_draft_recoveries_before_debounce(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self._write_complete_native_evidence(directory)
            (directory / "regenerations.json").unlink()
            runner.validate_native_evidence(
                directory,
                require_ui=True,
                require_regenerations=False,
                require_drafts=True,
            )

            drafts = json.loads((directory / "drafts.json").read_text(encoding="utf-8"))
            drafts["drafts"][1]["nativeActionPath"] = "quit-menu-fallback"
            (directory / "drafts.json").write_text(json.dumps(drafts), encoding="utf-8")
            runner.validate_native_evidence(
                directory,
                require_ui=True,
                require_regenerations=False,
                require_drafts=True,
            )
            drafts["drafts"][1]["elapsedBeforeDebounceMilliseconds"] = 351
            (directory / "drafts.json").write_text(json.dumps(drafts), encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "draft B"):
                runner.validate_native_evidence(
                    directory,
                    require_ui=True,
                    require_regenerations=False,
                    require_drafts=True,
                )

    def test_requires_complete_desktop_long_actions_and_recovery_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self._write_complete_native_evidence(directory)
            self._write_desktop_long_evidence(directory)
            runner.validate_native_evidence(
                directory,
                require_ui=True,
                require_desktop_long=True,
            )

            long = json.loads((directory / "desktop-long.json").read_text(encoding="utf-8"))
            long["actions"][299]["completedEpochMilliseconds"] = -1
            (directory / "desktop-long.json").write_text(json.dumps(long), encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "genuine UI actions"):
                runner.validate_native_evidence(
                    directory,
                    require_ui=True,
                    require_desktop_long=True,
                )


if __name__ == "__main__":
    unittest.main()
