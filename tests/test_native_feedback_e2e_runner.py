import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


RUNNER = Path(__file__).with_name("run-native-feedback-e2e.py")
SPEC = importlib.util.spec_from_file_location("native_feedback_runner", RUNNER)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class NativeFeedbackRunnerTest(unittest.TestCase):
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
            drafts["drafts"][1]["elapsedBeforeDebounceMilliseconds"] = 351
            (directory / "drafts.json").write_text(json.dumps(drafts), encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "draft B"):
                runner.validate_native_evidence(
                    directory,
                    require_ui=True,
                    require_regenerations=False,
                    require_drafts=True,
                )


if __name__ == "__main__":
    unittest.main()
