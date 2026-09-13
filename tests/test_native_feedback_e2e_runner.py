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


if __name__ == "__main__":
    unittest.main()
