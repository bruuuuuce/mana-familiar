#!/usr/bin/env python3
"""Capture synthetic evidence, observe in an isolated bundle, then compare locally."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REAL_VARIANTS = ("desktop-light", "compact-dark")
CONTRACT_VERSION = "2.0"
OBSERVER_SCHEMA = {"$id": "mana-agentic-ux-observation-2.0", "type": "object", "additionalProperties": False,
 "required": ["contract_version", "summary", "answers", "findings", "limitations"], "properties": {
 "contract_version": {"type": "string", "enum": [CONTRACT_VERSION]},
 "summary": {"type": "string"},
 "answers": {"type": "array", "items": {"type": "object", "additionalProperties": False,
  "required": ["checkpoint", "answer", "certainty", "visible_evidence", "evidence_location", "observed", "readability", "answerability", "actionability", "visible_contradiction"], "properties": {
   "checkpoint": {"type": "string"}, "answer": {"type": "string"},
    "certainty": {"type": "string", "enum": ["certain", "uncertain", "not_determinable"]},
   "visible_evidence": {"type": "string"}, "evidence_location": {"type": "string"},
   "observed": {"type": "object", "additionalProperties": False, "required": ["status", "identity", "cause", "action"], "properties": {"status": {"type": ["string", "null"]}, "identity": {"type": ["string", "null"]}, "cause": {"type": ["string", "null"]}, "action": {"type": ["string", "null"]}}},
   "readability": {"type": "object", "additionalProperties": False, "required": ["essential_segment", "location", "completeness"], "properties": {"essential_segment": {"type": "string"}, "location": {"type": "string"}, "completeness": {"type": "string", "enum": ["fully_visible", "partially_visible", "not_determinable"]}}},
   "answerability": {"type": "string", "enum": ["answered", "not_determinable"]},
   "actionability": {"type": "string", "enum": ["actionable", "not_actionable", "not_applicable", "not_determinable"]},
   "visible_contradiction": {"type": "boolean"}}}},
 "findings": {"type": "array", "items": {"type": "object", "additionalProperties": False,
  "required": ["checkpoint", "severity", "observation", "user_impact", "source"], "properties": {
   "checkpoint": {"type": "string"}, "severity": {"type": "string", "enum": ["minor", "major", "critical"]},
   "observation": {"type": "string"}, "user_impact": {"type": "string"}, "source": {"type": "string", "enum": ["observer"]}}}},
 "limitations": {"type": "array", "items": {"type": "string"}}}}

def write_json(path, value): Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
def sha256(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_execution_plan(output, labels):
    """Freeze planned identities before any model process starts."""
    write_json(output / "execution-plan.json", {"contract_version": CONTRACT_VERSION,
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "requested_configuration": observer_configuration(),
        "runs": [{"sequence": index, "label": label, "attempt": 1 if "-run" not in label else int(label.rsplit("run", 1)[1])} for index, label in enumerate(labels, 1)]})

def write_snapshots(output):
    tracked = [path for path in output.iterdir() if path.is_file() and (path.suffix in (".png", ".json", ".md") or path.name.endswith(".schema.json"))]
    write_json(output / "snapshots.json", {"contract_version": CONTRACT_VERSION, "files": {path.name: sha256(path) for path in sorted(tracked)}})

def source_hashes():
    paths = (ROOT / "tests/run-agentic-ux.py", ROOT / "tests/ux-review-prompt.md", ROOT / "lib/presentation/project_observatory_page.dart", ROOT / "test/agentic_ux_test.dart", ROOT / "test/agentic_ux_calibration_test.dart")
    return {str(path.relative_to(ROOT)): sha256(path) for path in paths if path.is_file()}

def validate_observation(value, ids):
    """Checks shape/references only; it does not prove evidence is visually true."""
    if not isinstance(value, dict) or set(value) != set(OBSERVER_SCHEMA["properties"]) or value.get("contract_version") != CONTRACT_VERSION: raise ValueError("Missing, unexpected, or incompatible observation fields")
    if not isinstance(value["summary"], str) or not value["summary"].strip(): raise ValueError("Missing observation summary")
    answers = value["answers"]
    if not isinstance(answers, list) or len(answers) != len(ids) or {x.get("checkpoint") for x in answers if isinstance(x, dict)} != set(ids): raise ValueError("Observer did not assess every checkpoint exactly once")
    for x in answers:
        if set(x) != {"checkpoint", "answer", "certainty", "visible_evidence", "evidence_location", "observed", "readability", "answerability", "actionability", "visible_contradiction"}: raise ValueError("Malformed observation answer")
        observed, readability = x["observed"], x["readability"]
        if (x["certainty"] not in ("certain", "uncertain", "not_determinable") or x["answerability"] not in ("answered", "not_determinable") or x["actionability"] not in ("actionable", "not_actionable", "not_applicable", "not_determinable") or not isinstance(x["visible_contradiction"], bool) or not all(isinstance(x[k], str) and x[k].strip() for k in ("answer", "visible_evidence", "evidence_location")) or not isinstance(observed, dict) or set(observed) != {"status", "identity", "cause", "action"} or not all(value is None or isinstance(value, str) for value in observed.values()) or not isinstance(readability, dict) or set(readability) != {"essential_segment", "location", "completeness"} or readability.get("completeness") not in ("fully_visible", "partially_visible", "not_determinable") or not all(isinstance(readability.get(key), str) and readability[key].strip() for key in ("essential_segment", "location"))): raise ValueError("Observation answer lacks valid visible evidence")
    if not isinstance(value["findings"], list) or not isinstance(value["limitations"], list): raise ValueError("Invalid observation collections")
    for x in value["findings"]:
        if not isinstance(x, dict) or set(x) != {"checkpoint", "severity", "observation", "user_impact", "source"} or x["checkpoint"] not in ids or x["severity"] not in ("minor", "major", "critical") or x["source"] != "observer" or not all(isinstance(x[k], str) and x[k].strip() for k in ("observation", "user_impact")): raise ValueError("Malformed finding")
    if not all(isinstance(x, str) for x in value["limitations"]): raise ValueError("Invalid limitations")

def _normal(value): return re.sub(r"[^\w]+", " ", value.casefold()).strip()

def _text_supports(answer, expected):
    """Free-text validation supplements, never replaces, canonical fields.

    It deliberately recognizes bilingual concepts and rejects a nearby negation
    (for example, 'not approved' is not evidence of approval).
    """
    answer = _normal(answer)
    aliases = expected.get("text_aliases", [])
    if not aliases: return True
    for alias in aliases:
        phrase = _normal(alias)
        if phrase and phrase in answer:
            negated = any(marker + " " + phrase in answer for marker in ("not", "non", "nessun", "without"))
            if not negated: return True
    return False

def _deduplicated_findings(findings, checkpoint):
    rank = {"minor": 1, "major": 2, "critical": 3}
    selected = [finding for finding in findings if finding["checkpoint"] == checkpoint]
    return max(selected, key=lambda item: rank[item["severity"]], default=None)

CANONICAL_ALIASES = {
    "blocked": ("blocked", "bloccato", "bloccata"),
    "unknown": ("unknown", "sconosciuto", "no review information", "could not provide review", "non disponibili informazioni di review"),
    "not_determinable": ("not determinable", "cannot be determined", "non determinabile", "attention data may be stale"),
    "healthy": ("healthy", "nothing needs attention", "nessuna attenzione"),
    "approved": ("approved", "approvato", "approvata"),
    "duplicate_charge": ("duplicate charge", "duplicato", "payment verification failed"),
    "inspect_retry_evidence": ("inspect retry evidence", "inspect the retry", "ispezionare le prove", "ispezionare.*tentativo"),
}

def _canonical_value_matches(actual, expected):
    if isinstance(expected, list): return any(_canonical_value_matches(actual, candidate) for candidate in expected)
    if actual == expected: return True
    if actual is None or expected is None: return False
    actual_normal = _normal(actual)
    for alias in CANONICAL_ALIASES.get(expected, (expected,)):
        alias_normal = _normal(alias)
        if alias_normal in actual_normal: return True
    return False

def compare_observation(observation, oracle):
    """Compare immutable observation to an oracle that never entered its bundle.

    A semantic answer can match while the independent fidelity/readability
    assessment is false.  That is deliberately a failed checkpoint, not a
    compensating average.
    """
    if oracle.get("contract_version") not in (None, CONTRACT_VERSION): raise ValueError("Incompatible oracle contract")
    answers = {x["checkpoint"]: x for x in observation["answers"]}; checks = []; observed_defects = []; comparison_defects = []
    defect_ids = {x["checkpoint"] for x in oracle["checkpoints"] if x.get("must_raise_finding")}
    for expected in oracle["checkpoints"]:
        answer = answers[expected["checkpoint"]]
        canonical = expected.get("canonical", {})
        canonical_match = all(_canonical_value_matches(answer["observed"].get(field), value) for field, value in canonical.items())
        text_match = _text_supports(answer["answer"], expected)
        readability_expected = expected.get("readability", "fully_visible")
        readability_match = answer["readability"]["completeness"] == readability_expected
        answerability_expected = expected.get("answerability", "answered")
        actionability_expected = expected.get("actionability", "not_applicable")
        answerability_match = answer["answerability"] == answerability_expected
        actionability_match = answer["actionability"] == actionability_expected
        producer = expected.get("producer", {})
        fidelity_violations = [field for field, value in producer.items() if value is not None and not _canonical_value_matches(answer["observed"].get(field), value)]
        fidelity_expected = expected.get("producer_fidelity", "faithful")
        fidelity_actual = "contradictory" if fidelity_violations else "faithful"
        fidelity_match = fidelity_actual == fidelity_expected
        check = {"checkpoint": expected["checkpoint"], "expected": expected.get("expected", "structured checkpoint"), "answer": answer["answer"], "certainty": answer["certainty"], "canonical": {"expected": canonical, "actual": answer["observed"], "matched": canonical_match}, "free_text": {"matched": text_match}, "information_fidelity": {"expected": fidelity_expected, "actual": fidelity_actual, "matched": fidelity_match, "producer_fields": fidelity_violations}, "readability": {"expected": readability_expected, "actual": answer["readability"]["completeness"], "essential_segment": answer["readability"]["essential_segment"], "location": answer["readability"]["location"], "matched": readability_match}, "answerability": {"expected": answerability_expected, "actual": answer["answerability"], "matched": answerability_match}, "actionability": {"expected": actionability_expected, "actual": answer["actionability"], "matched": actionability_match}}
        if expected.get("must_raise_finding"):
            finding = _deduplicated_findings(observation["findings"], expected["checkpoint"])
            found = finding is not None
            expected_severity = expected.get("severity", "major")
            check["observed_defect_detected"] = found
            check["detected_at_least_major"] = bool(finding and finding["severity"] in ("major", "critical"))
            check["expected_severity"] = expected_severity
            check["observed_severity"] = finding["severity"] if finding else None
            observed_defects.append(found)
            # The comparison can establish a hidden-producer contradiction or
            # an explicitly partial essential segment even if the observer did
            # not phrase a finding. This is intentionally distinct from the
            # observer's own finding metric above.
            comparison_defects.append(bool(fidelity_violations) or answer["readability"]["completeness"] == "partially_visible" or answer["visible_contradiction"])
        checks.append(check)
    false_alarm_checks = []
    for check in checks:
        finding = _deduplicated_findings(observation["findings"], check["checkpoint"])
        # A wrong answer is not automatically a false alarm. Count a structured
        # false alarm only when the observer positively asserts a visible
        # contradiction on a control that has none; otherwise a bad answer is
        # retained as a failed recognition without double counting it.
        structured_wrong = answer["visible_contradiction"]
        if check["checkpoint"] not in defect_ids and (finding or structured_wrong):
            false_alarm_checks.append({"checkpoint": check["checkpoint"], "severity": finding["severity"] if finding else ("major" if structured_wrong else None), "source": "observer" if finding else "structured_comparison"})
    false_alarms = len(false_alarm_checks)
    severe_false_alarms = sum(1 for item in false_alarm_checks if item["severity"] in ("major", "critical"))
    correct_recognized = sum(1 for check in checks if check["checkpoint"] not in defect_ids and check["canonical"]["matched"] and check["free_text"]["matched"] and check["information_fidelity"]["matched"] and check["readability"]["matched"] and check["answerability"]["matched"] and check["actionability"]["matched"] and check["checkpoint"] not in {x["checkpoint"] for x in false_alarm_checks})
    not_evaluable = sum(1 for answer in answers.values() if answer["certainty"] == "not_determinable")
    severity_disagreements = sum(1 for check in checks if check.get("observed_defect_detected") and check["observed_severity"] != check["expected_severity"])
    serious = [check["checkpoint"] for check in checks if not check["canonical"]["matched"] or not check["free_text"]["matched"] or not check["information_fidelity"]["matched"] or not check["readability"]["matched"] or not check["answerability"]["matched"] or not check["actionability"]["matched"] or (check.get("observed_defect_detected") is False)]
    return {"contract_version": CONTRACT_VERSION, "checks": checks, "passed": not serious and not_evaluable == 0 and severe_false_alarms == 0, "correct_controls_recognized": correct_recognized, "defects_observed": sum(observed_defects), "defects_detected": sum(comparison_defects), "defects_detected_at_least_major": sum(1 for check in checks if check.get("detected_at_least_major")), "defects_missed": len(observed_defects)-sum(observed_defects), "false_alarms": false_alarms, "severe_false_alarms": severe_false_alarms, "false_alarm_details": false_alarm_checks, "not_evaluable": not_evaluable, "technical_errors": 0, "severity_disagreements": severity_disagreements, "serious_failures": serious}

def observer_prompt():
    return (ROOT / "tests/ux-review-prompt.md").read_text()

def make_observer_bundle(output, manifest, label):
    # The agent gets an opaque directory too: neither a case/viewport label nor
    # a semantic image name is a capability or a hint. Its actual working
    # directory is outside the evidence directory, so the oracle and source
    # checkout are not ancestors of the observer workspace. A byte-identical
    # archive remains in evidence for audit after the temporary runtime bundle
    # is removed.
    archive = output / f"observer-input-{secrets.token_hex(12)}"; archive.mkdir()
    bundle = Path(tempfile.mkdtemp(prefix="mana-ux-observer-"))
    neutral = {"contract_version": CONTRACT_VERSION, "checkpoints": []}
    for i, frame in enumerate(manifest["frames"], 1):
        checkpoint, opaque = f"c{i:02d}", f"frame-{i:02d}.png"
        shutil.copy2(output / frame["image"], bundle / opaque)
        shutil.copy2(output / frame["image"], archive / opaque)
        neutral["checkpoints"].append({"checkpoint": checkpoint, "image": opaque, "question": frame["question"]})
    for target in (bundle, archive):
        write_json(target / "manifest.json", neutral); write_json(target / "observation.schema.json", OBSERVER_SCHEMA)
    allowed = {"manifest.json", "observation.schema.json", *(x["image"] for x in neutral["checkpoints"])}
    if {path.name for path in bundle.iterdir()} != allowed: raise RuntimeError("Observer bundle contains a non-permitted file")
    write_json(output / f"{label}.delivery.json", {"runtime_directory": bundle.name, "archive": archive.name, "files": {name: sha256(archive / name) for name in allowed}})
    return bundle, neutral

def observer_configuration():
    """Only forward explicit settings; never silently replace CLI defaults."""
    return {"model": os.environ.get("CODEX_MODEL"), "reasoning": os.environ.get("CODEX_REASONING_EFFORT")}

def _append_execution(output, event):
    path = output / "execution-events.jsonl"
    with path.open("a") as stream: stream.write(json.dumps(event, ensure_ascii=False) + "\n")

def run_observer(output, manifest, label):
    if not shutil.which("codex"): raise RuntimeError("Agent requested but Codex CLI is unavailable")
    bundle, neutral = make_observer_bundle(output, manifest, label); result_file = output / f"{label}.observation.json"
    if result_file.exists(): raise RuntimeError("Refusing to reuse an observer output")
    command = ["codex", "exec", "--sandbox", "read-only", "--ephemeral", "--skip-git-repo-check", "--cd", str(bundle), "--output-schema", str(bundle / "observation.schema.json"), "--output-last-message", str(result_file)]
    config = observer_configuration()
    if config["model"]: command += ["--model", config["model"]]
    if config["reasoning"]: command += ["--config", f'model_reasoning_effort="{config["reasoning"]}"']
    for item in neutral["checkpoints"]: command += ["--image", str(bundle / item["image"])]
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    with (output / f"{label}.agent.log").open("w") as log:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, text=True, cwd=bundle, start_new_session=True)
        _append_execution(output, {"event": "started", "label": label, "sequence": None, "started_at": started, "pid": process.pid, "bundle": bundle.name, "requested_configuration": config})
        try:
            process.communicate(observer_prompt()+"\n"+json.dumps(neutral), timeout=300)
        except subprocess.TimeoutExpired:
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=10)
            _append_execution(output, {"event": "timeout", "label": label, "finished_at": dt.datetime.now(dt.timezone.utc).isoformat(), "pid": process.pid, "terminated": process.poll() is not None})
            raise RuntimeError(f"Observer timed out and was terminated; inspect {label}.agent.log")
    _append_execution(output, {"event": "finished", "label": label, "finished_at": dt.datetime.now(dt.timezone.utc).isoformat(), "pid": process.pid, "returncode": process.returncode, "raw_observation": result_file.name if result_file.is_file() else None})
    if process.returncode or not result_file.is_file(): raise RuntimeError(f"Observer failed; inspect {label}.agent.log")
    value = json.loads(result_file.read_text()); validate_observation(value, {x["checkpoint"] for x in neutral["checkpoints"]})
    neutral["input_hashes"] = {item["image"]: sha256(bundle / item["image"]) for item in neutral["checkpoints"]}
    return value, neutral

def capture(flutter, output, fonts, test_file):
    env = dict(os.environ, UX_EVIDENCE_DIR=str(output), UX_FONT_DIR=str(fonts.resolve()))
    log = output / f"{Path(test_file).stem}.flutter.log"
    with log.open("w") as stream: result = subprocess.run([flutter, "test", "--no-pub", test_file], cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
    if result.returncode: raise RuntimeError(f"Capture failed; inspect {log.name}")

def command_output(command):
    result = subprocess.run(command, text=True, capture_output=True)
    return result.stdout.strip() if result.returncode == 0 else "unavailable"

def metric_line(comparison):
    return (f"correct controls recognized {comparison['correct_controls_recognized']}; "
            f"defects observed {comparison['defects_observed']}; comparison defects detected {comparison['defects_detected']}; defects missed {comparison['defects_missed']}; "
            f"false alarms {comparison['false_alarms']}; not evaluable {comparison['not_evaluable']}; "
            f"technical errors {comparison['technical_errors']}; severity disagreements {comparison['severity_disagreements']}")

def aggregate(entries):
    keys = ("correct_controls_recognized", "defects_observed", "defects_detected", "defects_detected_at_least_major", "defects_missed", "false_alarms", "severe_false_alarms", "not_evaluable", "technical_errors", "severity_disagreements")
    total = {key: 0 for key in keys}
    for entry in entries:
        for key in keys: total[key] += entry["comparison"][key]
    total["runs"] = len(entries)
    total["checkpoints"] = sum(len(entry["comparison"]["checks"]) for entry in entries)
    return total

def agent_execution_metadata(output):
    """Use persisted starts, not alphabetic log names, as run order."""
    events_path = output / "execution-events.jsonl"
    events = [json.loads(line) for line in events_path.read_text().splitlines() if line.strip()] if events_path.is_file() else []
    starts = [event for event in events if event.get("event") == "started"]
    finishes = {event["label"]: event for event in events if event.get("event") in ("finished", "timeout")}
    runs = []
    for sequence, start in enumerate(starts, 1):
        label = start["label"]
        log = output / f"{label}.agent.log"
        if not log.is_file(): continue
        text = log.read_text(errors="replace")
        def field(pattern):
            match = re.search(pattern, text, re.MULTILINE)
            return match.group(1).strip() if match else "unavailable"
        observation = output / f"{label}.observation.json"
        token = re.search(r"tokens used\s*\n([\d,]+)", text)
        finish = finishes.get(label, {})
        runs.append({"sequence": sequence, "label": label, "log": log.name,
                     "raw_observation": observation.name if observation.is_file() else None,
                     "raw_observation_sha256": sha256(observation) if observation.is_file() else None,
                     "model": field(r"^model:\s*(.+)$"), "reasoning": field(r"^reasoning effort:\s*(.+)$"),
                     "session_id": field(r"^session id:\s*(.+)$"), "pid": start.get("pid"),
                     "started_at": start.get("started_at"), "finished_at": finish.get("finished_at"),
                     "returncode": finish.get("returncode"), "requested_configuration": start.get("requested_configuration"),
                     "tokens_used": int(token.group(1).replace(",", "")) if token else None})
    return runs

def write_report(output, report, *, derived_name=None):
    report["totals"] = {"pay42": aggregate(report["pay42"]), "calibration": aggregate(report["calibration"])}
    report["agent_executions"] = agent_execution_metadata(output)
    report_name = derived_name or "report.json"
    write_json(output / report_name, report)
    pay42 = report["totals"]["pay42"]
    calibration = report["totals"]["calibration"]
    executions = report["agent_executions"]
    tokens = sum(run["tokens_used"] or 0 for run in executions)
    models = ", ".join(sorted({run["model"] for run in executions})) or "none"
    reasoning = ", ".join(sorted({run["reasoning"] for run in executions})) or "none"
    rows=["# UX audit report", "", f"Evidence: `{output}`", "", "## Execution trace", "", f"- {len(executions)} observer calls in recorded start order; model: {models}; reasoning: {reasoning}; recorded token usage: {tokens}.", f"- Contract version: {CONTRACT_VERSION}. Each raw observation is preserved before comparison; per-call PID, session, requested/effective configuration, hash and log are in `{report_name}`.", "", "## PAY-42"] + [f"- {x['variant']}: {'match' if x['comparison']['passed'] else 'mismatch'}; {metric_line(x['comparison'])}; raw: [{x['variant']}.observation.json]({x['variant']}.observation.json); images: " + ", ".join(f"[{name}]({name})" for name in x["images"]) for x in report["pay42"]] + ["", "## Calibration", "", "Controlled calibration measures this observer on this small synthetic suite only; it does not prove product usability.", f"- denominator: {calibration['checkpoints']} checkpoint × observation units across {calibration['runs']} completed runs."] + [f"- {x['case']} run {x['run']}: {metric_line(x['comparison'])}; raw: [{x['case']}-run{x['run']}.observation.json]({x['case']}-run{x['run']}.observation.json); image: " + ", ".join(f"[{name}]({name})" for name in x["images"]) for x in report["calibration"]] + ["", "## Conclusions", "", f"- Functional path: {pay42['checkpoints']} PAY-42 checkpoint × observation units were captured; that execution result is separate from UX comparison.", "- Observer metrics distinguish a finding stated by the observer, a producer/readability violation established by the local comparison, and severity agreement. They are informational, never a CI gate.", f"- Calibration has {calibration['checkpoints']} total units, {calibration['correct_controls_recognized']} recognized correct controls, {calibration['defects_detected']} comparison-detected defects, {calibration['defects_missed']} missed observer findings, {calibration['false_alarms']} false alarms, {calibration['severity_disagreements']} severity disagreements and {calibration['not_evaluable']} observer-uncertain units.", "", "A serious missed defect, a severe false alarm, or observer uncertainty fails that observation; no average can turn it into a pass."]
    markdown_name = Path(report_name).with_suffix(".md").name
    (output / markdown_name).write_text("\n".join(rows)+"\n")
    return output / markdown_name

def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--observe", action="store_true", help="Run the explicit model observer"); parser.add_argument("--calibrate", action="store_true", help="Run every controlled fixture twice"); parser.add_argument("--capture-calibration", action="store_true", help="Capture controls without a model"); parser.add_argument("--font-dir", type=Path); parser.add_argument("--render-report", type=Path, metavar="EVIDENCE_DIR", help="Generate a derived report from immutable report.json without a model"); parser.add_argument("--recompare", type=Path, metavar="EVIDENCE_DIR", help="Recompute immutable raw observations with the current comparator, without model calls"); args = parser.parse_args()
    if args.render_report:
        report_path = args.render_report / "report.json"
        if not report_path.is_file(): parser.error("--render-report requires an existing report.json")
        source = json.loads(report_path.read_text())
        if not isinstance(source, dict) or not isinstance(source.get("pay42"), list) or not isinstance(source.get("calibration"), list): parser.error("--render-report requires a complete versioned report")
        derived = f"report-derived-{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
        report = write_report(args.render_report, source, derived_name=derived)
        print(f"Derived report written without changing raw evidence: {report}")
        return 0
    if args.recompare:
        report_path = args.recompare / "report.json"
        if not report_path.is_file(): parser.error("--recompare requires an existing report.json")
        source = json.loads(report_path.read_text())
        if not isinstance(source, dict) or not isinstance(source.get("pay42"), list) or not isinstance(source.get("calibration"), list): parser.error("--recompare requires a complete report")
        recalculated = json.loads(json.dumps(source))
        for entry in recalculated["pay42"]:
            oracle = json.loads((args.recompare / f"{entry['variant']}.oracle.json").read_text())
            entry["comparison"] = compare_observation(entry["observation"], oracle)
        calibration_oracle = json.loads((args.recompare / "calibration.oracle.json").read_text()) if recalculated["calibration"] else {}
        for entry in recalculated["calibration"]:
            entry["comparison"] = compare_observation(entry["observation"], calibration_oracle[entry["case"]])
        provenance = f"provenance-recomputed-{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
        write_json(args.recompare / provenance, {"contract_version": CONTRACT_VERSION, "derived_at": dt.datetime.now(dt.timezone.utc).isoformat(), "source_hashes": source_hashes(), "notice": "Derived after the raw run; it does not alter raw observations or claim an original worktree snapshot."})
        recalculated["recomputed_from"] = {"report": "report.json", "provenance": provenance, "comparator_contract_version": CONTRACT_VERSION, "at": dt.datetime.now(dt.timezone.utc).isoformat()}
        derived = f"report-recomputed-{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
        report = write_report(args.recompare, recalculated, derived_name=derived)
        print(f"Recomputed report written without model calls: {report}")
        return 0
    flutter = shutil.which("flutter")
    if not flutter: parser.error("flutter is not on PATH")
    fonts = args.font_dir or Path(flutter).resolve().parents[1] / "bin/cache/artifacts/material_fonts"
    if not all((fonts/f"Roboto-{x}.ttf").is_file() for x in ("Regular", "Medium", "Bold")) or not (fonts/"MaterialIcons-Regular.otf").is_file(): parser.error("Missing Material fonts; supply --font-dir")
    if (args.observe or args.calibrate) and not shutil.which("codex"): parser.error("agent stages require an authenticated Codex CLI")
    parent = ROOT/"build/ux-audit"; parent.mkdir(parents=True, exist_ok=True); output = Path(tempfile.mkdtemp(prefix="run-", dir=parent)); print(f"Evidence: {output}", flush=True)
    write_json(output/"run-metadata.json", {"contract_version": CONTRACT_VERSION, "created_at": dt.datetime.now(dt.timezone.utc).isoformat(), "code_revision": command_output(["git", "rev-parse", "HEAD"]), "worktree_dirty": bool(command_output(["git", "status", "--porcelain"])), "worktree_status": command_output(["git", "status", "--porcelain"]), "source_hashes": source_hashes(), "python": platform.python_version(), "flutter": flutter, "flutter_version": command_output([flutter, "--version"]), "codex_version": command_output(["codex", "--version"]) if shutil.which("codex") else "not installed", "font_dir": str(fonts), "observer_prompt_sha256": hashlib.sha256(observer_prompt().encode()).hexdigest(), "requested_observer_configuration": observer_configuration(), "token_notice": "Agent stages consume provider tokens; no secrets are written."})
    capture(flutter, output, fonts, "test/agentic_ux_test.dart"); print("PAY-42 deterministic task checks passed; eight screenshots captured.")
    if args.capture_calibration: capture(flutter, output, fonts, "test/agentic_ux_calibration_test.dart"); print("Calibration controls captured; visually inspect their PNGs before model use.")
    if not args.observe and not args.calibrate:
        write_snapshots(output); print("No model run: local capture is complete, visual observation was not requested."); return 0
    if args.calibrate: capture(flutter, output, fonts, "test/agentic_ux_calibration_test.dart")
    labels = ([*REAL_VARIANTS] if args.observe else []) + ([f"control-{number:02d}-run{repeat}" for number in range(1, 9) for repeat in (1, 2)] if args.calibrate else [])
    write_execution_plan(output, labels); write_snapshots(output)
    report = {"contract_version": CONTRACT_VERSION, "pay42": [], "calibration": [], "incomplete": False, "technical_errors": []}
    try:
        if args.observe:
            for variant in REAL_VARIANTS:
                manifest = json.loads((output/f"{variant}.json").read_text()); oracle = json.loads((output/f"{variant}.oracle.json").read_text()); obs, neutral = run_observer(output, manifest, variant)
                report["pay42"].append({"variant": variant, "images": [x["image"] for x in manifest["frames"]], "input_hashes": neutral["input_hashes"], "observation": obs, "comparison": compare_observation(obs, oracle)})
        if args.calibrate:
            oracle = json.loads((output/"calibration.oracle.json").read_text())
            for source in sorted(output.glob("control-*.json")):
                manifest = json.loads(source.read_text())
                for repeat in (1, 2):
                    label=f"{source.stem}-run{repeat}"; obs, neutral=run_observer(output, manifest, label)
                    report["calibration"].append({"case":source.stem,"run":repeat,"images":[x["image"] for x in manifest["frames"]],"input_hashes":neutral["input_hashes"],"observation":obs,"comparison":compare_observation(obs,oracle[source.stem])})
    except Exception as error:
        report["incomplete"] = True; report["technical_errors"].append({"message": str(error), "at": dt.datetime.now(dt.timezone.utc).isoformat()})
        write_snapshots(output); write_report(output, report)
        raise
    write_snapshots(output); write_report(output, report)
    return 0

if __name__ == "__main__":
    try: sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.TimeoutExpired) as error: print(f"Audit incomplete: {error}", file=sys.stderr); sys.exit(2)
