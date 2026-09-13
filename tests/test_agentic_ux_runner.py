"""Contract tests for the local, model-free UX audit runner."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("ux_runner", Path(__file__).with_name("run-agentic-ux.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def observation(**overrides):
    answer = {
        "checkpoint": "c01", "answer": "La review è sconosciuta.",
        "certainty": "certain", "visible_evidence": "Review status: unknown",
        "evidence_location": "centro della scheda",
        "observed": {"status": "unknown", "identity": "PAY-42", "cause": None, "action": None},
        "readability": {"essential_segment": "Review status: unknown", "location": "centro", "completeness": "fully_visible"},
        "answerability": "answered", "actionability": "not_applicable",
        "visible_contradiction": False,
    }
    value = {"contract_version": runner.CONTRACT_VERSION, "summary": "Stato leggibile.", "answers": [answer], "findings": [], "limitations": ["Cattura sintetica"]}
    value.update(overrides)
    return value


def oracle(**overrides):
    checkpoint = {
        "checkpoint": "c01", "expected": "Review unknown.",
        "canonical": {"status": "unknown", "identity": "PAY-42"},
        "producer": {"status": "unknown"}, "text_aliases": ["unknown", "sconosciuta"],
        "readability": "fully_visible", "answerability": "answered", "actionability": "not_applicable",
    }
    checkpoint.update(overrides)
    return {"contract_version": runner.CONTRACT_VERSION, "checkpoints": [checkpoint]}


class ObserverContractTest(unittest.TestCase):
    def test_complete_observation_and_bilingual_canonical_answer_pass(self):
        value = observation()
        runner.validate_observation(value, {"c01"})
        self.assertTrue(runner.compare_observation(value, oracle())["passed"])

    def test_schema_rejects_old_hidden_fidelity_fields_and_malformed_output(self):
        malformed = observation()
        malformed["answers"][0]["information_fidelity"] = "faithful"
        with self.assertRaises(ValueError): runner.validate_observation(malformed, {"c01"})
        malformed = observation(contract_version="1.0")
        with self.assertRaises(ValueError): runner.validate_observation(malformed, {"c01"})
        malformed = observation(answers=[])
        with self.assertRaises(ValueError): runner.validate_observation(malformed, {"c01"})

    def test_hidden_false_approval_is_a_comparison_fidelity_violation_without_finding(self):
        value = observation()
        value["answers"][0]["answer"] = "La review appare approvata."
        value["answers"][0]["observed"]["status"] = "approved"
        result = runner.compare_observation(value, oracle(
            expected="Approval visible but producer unknown.", canonical={"status": "approved", "identity": "PAY-42"},
            producer={"status": "unknown"}, producer_fidelity="contradictory", text_aliases=["approvata", "approved"], must_raise_finding=True,
        ))
        self.assertTrue(result["checks"][0]["information_fidelity"]["matched"])
        self.assertEqual(result["checks"][0]["information_fidelity"]["producer_fields"], ["status"])
        self.assertEqual(result["defects_detected"], 1)
        self.assertEqual(result["defects_observed"], 0)
        self.assertFalse(result["passed"])

    def test_translation_is_accepted_but_negation_and_token_only_claim_are_rejected(self):
        value = observation()
        value["answers"][0]["answer"] = "Ispezionare le prove del tentativo prima di un’altra revisione."
        value["answers"][0]["observed"]["action"] = "inspect_retry_evidence"
        value["answers"][0]["actionability"] = "actionable"
        action_oracle = oracle(canonical={"status": "unknown", "identity": "PAY-42", "action": "inspect_retry_evidence"}, text_aliases=["ispezionare"], actionability="actionable")
        self.assertTrue(runner.compare_observation(value, action_oracle)["passed"])
        value["answers"][0]["answer"] = "Non ispezionare le prove del tentativo."
        self.assertFalse(runner.compare_observation(value, action_oracle)["checks"][0]["free_text"]["matched"])
        value["answers"][0]["answer"] = "inspect, but do not inspect the evidence"
        self.assertFalse(runner.compare_observation(value, action_oracle)["checks"][0]["free_text"]["matched"])

    def test_clipped_essential_segment_is_detected_even_when_answer_is_guessed(self):
        value = observation()
        value["answers"][0]["observed"]["action"] = "inspect_retry_evidence"
        value["answers"][0]["readability"]["completeness"] = "partially_visible"
        value["answers"][0]["readability"]["essential_segment"] = "Next action: Inspect retry…"
        result = runner.compare_observation(value, oracle(canonical={"status": "unknown", "identity": "PAY-42", "action": "inspect_retry_evidence"}, readability="partially_visible", actionability="not_actionable", must_raise_finding=True))
        self.assertEqual(result["defects_detected"], 1)
        self.assertEqual(result["defects_observed"], 0)
        self.assertFalse(result["passed"])

    def test_minor_finding_is_detection_but_severity_disagreement(self):
        value = observation(findings=[{"checkpoint": "c01", "severity": "minor", "observation": "Action clipped", "user_impact": "May hide action", "source": "observer"}])
        result = runner.compare_observation(value, oracle(must_raise_finding=True, severity="major"))
        self.assertEqual(result["defects_observed"], 1)
        self.assertEqual(result["defects_detected_at_least_major"], 0)
        self.assertEqual(result["severity_disagreements"], 1)

    def test_duplicate_findings_are_deduplicated_and_severe_false_alarm_blocks_pass(self):
        value = observation(findings=[
            {"checkpoint": "c01", "severity": "minor", "observation": "noise", "user_impact": "noise", "source": "observer"},
            {"checkpoint": "c01", "severity": "critical", "observation": "invented", "user_impact": "wrong choice", "source": "observer"},
        ])
        result = runner.compare_observation(value, oracle())
        self.assertEqual(result["false_alarms"], 1)
        self.assertEqual(result["severe_false_alarms"], 1)
        self.assertEqual(result["correct_controls_recognized"], 0)
        self.assertFalse(result["passed"])

    def test_not_determinable_project_health_is_answerable_but_observer_uncertainty_is_not(self):
        value = observation()
        value["answers"][0]["observed"]["status"] = "not_determinable"
        value["answers"][0]["answer"] = "La salute del progetto non è determinabile."
        health = oracle(canonical={"status": "not_determinable", "identity": "PAY-42"}, producer={"status": "not_determinable"}, text_aliases=["determinabile"])
        self.assertTrue(runner.compare_observation(value, health)["passed"])
        value["answers"][0]["certainty"] = "not_determinable"
        self.assertFalse(runner.compare_observation(value, health)["passed"])

    def test_bundle_is_opaque_and_has_no_oracle_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pay-42-secret-name.png").write_bytes(b"synthetic")
            bundle, neutral = runner.make_observer_bundle(root, {"frames": [{"image": "pay-42-secret-name.png", "question": "What is visible?"}]}, "isolated")
            self.assertEqual({path.name for path in bundle.iterdir()}, {"frame-01.png", "manifest.json", "observation.schema.json"})
            self.assertNotEqual(bundle.parent, root, "runtime bundle must not share the oracle parent")
            self.assertEqual(neutral["checkpoints"][0]["checkpoint"], "c01")
            self.assertNotIn("pay-42", (bundle / "manifest.json").read_text().casefold())
            self.assertNotIn("producer", (bundle / "observation.schema.json").read_text().casefold())


if __name__ == "__main__": unittest.main()
