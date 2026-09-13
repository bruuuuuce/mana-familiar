import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


def _runner_module():
    path = Path(__file__).with_name("run-c03-human-feedback-harness.py")
    spec = importlib.util.spec_from_file_location("c03_human_feedback_runner", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class C03HumanFeedbackRunnerTest(unittest.TestCase):
    def test_declared_long_profiles_are_paced_and_scoped_to_producer_api(self):
        runner = _runner_module()

        self.assertEqual(runner.C03_PROFILES["desktop-long"]["minimumDurationSeconds"], 20 * 60)
        self.assertEqual(runner.C03_PROFILES["soak"]["minimumDurationSeconds"], 60 * 60)
        self.assertEqual(
            runner.C03_PROFILES["desktop-long"]["seeds"]
            * runner.C03_PROFILES["desktop-long"]["actions"],
            300,
        )
        self.assertEqual(
            runner.C03_PROFILES["soak"]["seeds"] * runner.C03_PROFILES["soak"]["actions"],
            1000,
        )
        self.assertAlmostEqual(
            runner.action_interval_seconds(150, 20 * 60) * (150 - 1),
            20 * 60,
        )
        self.assertEqual(runner.action_interval_seconds(1, 60), 60)

    def test_atomic_evidence_replaces_complete_json_only(self):
        runner = _runner_module()
        with tempfile.TemporaryDirectory() as raw:
            destination = Path(raw) / "manifest.json"
            runner.write_json_atomically(destination, {"status": "running"})
            self.assertEqual(json.loads(destination.read_text()), {"status": "running"})

            runner.write_json_atomically(destination, {"status": "passed", "count": 1})
            self.assertEqual(
                json.loads(destination.read_text()),
                {"status": "passed", "count": 1},
            )
            self.assertEqual(list(Path(raw).glob(".*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
