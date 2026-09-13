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
                    "uiActionCount": 4,
                    "canonicalThreadId": "thread_1",
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


if __name__ == "__main__":
    unittest.main()
