#!/usr/bin/env python3
"""macOS native lifecycle + Story Start regeneration acceptance smoke.

The shell gate owns real macOS windows and Accessibility actions. This runner
owns the isolated synthetic project and the durable audit bundle around it.
It exposes short, separately-scoped smoke profiles. The 20-minute
`desktop-long` profile remains unavailable until the driver can count genuine
UI actions and injected recovery episodes rather than polls.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
import secrets
import socket
import subprocess
import sys
import time
from pathlib import Path


def write_json(path: Path, value: object) -> None:
    temporary = path.with_name(f".{path.name}.{time.time_ns()}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temporary.replace(path)


def repository_state(path: Path) -> dict[str, object]:
    def git(*args: str) -> str | None:
        result = subprocess.run(
            ["git", "-C", str(path), *args], capture_output=True, text=True, check=False
        )
        return result.stdout.strip() if result.returncode == 0 else None

    return {
        "path": str(path),
        "revision": git("rev-parse", "HEAD"),
        "branch": git("branch", "--show-current"),
        "dirty": bool(git("status", "--porcelain")),
    }


def reserve_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def validate_native_evidence(
    native_output: Path,
    *,
    require_ui: bool = False,
    require_regenerations: bool = True,
    require_decision: bool = False,
    require_drafts: bool = False,
) -> list[dict[str, object]]:
    generations: list[dict[str, object]] = []
    if require_regenerations:
        regenerations = json.loads(
            (native_output / "regenerations.json").read_text(encoding="utf-8")
        )
        values = regenerations.get("generations")
        if not isinstance(values, list) or len(values) != 6:
            raise AssertionError("native gate did not record V0 plus five regenerations")
        if values[0]["reportRevision"] != values[1]["reportRevision"]:
            raise AssertionError("R1 was not deterministic")
        if len({entry["reportRevision"] for entry in values[2:]}) != 4:
            raise AssertionError("R2-R5 do not have distinct report revisions")
        generations = values

    lifecycle = json.loads(
        (native_output / "lifecycle.json").read_text(encoding="utf-8")
    )
    restarts = lifecycle.get("restarts")
    if not isinstance(restarts, list) or len(restarts) != 3:
        raise AssertionError("native gate did not record three restarts")
    expected_actions = ["close", "quit", "close"]
    for index, (restart, action) in enumerate(zip(restarts, expected_actions), start=1):
        if not isinstance(restart, dict):
            raise AssertionError("native lifecycle record is malformed")
        if restart.get("restart") != index or restart.get("action") != action:
            raise AssertionError("native lifecycle restart sequence is incomplete")
        if restart.get("session") != "native-e2e-B":
            raise AssertionError("native lifecycle lost the B draft session")
        if restart.get("previousPid") == restart.get("currentPid"):
            raise AssertionError("native restart reused its previous process")
    if require_ui:
        comment = json.loads((native_output / "ui" / "comment.json").read_text(encoding="utf-8"))
        if (
            comment.get("status") != "passed"
            or comment.get("mode") != "publish-comment"
            or comment.get("inputMode") != "flutter-widget-bridge"
            or comment.get("uiActionCount") != 6
            or not isinstance(comment.get("canonicalThreadId"), str)
        ):
            raise AssertionError("native gate did not prove a visible canonical UI comment")
        if require_decision:
            decision = json.loads((native_output / "ui" / "decision.json").read_text(encoding="utf-8"))
            if (
                decision.get("status") != "passed"
                or decision.get("mode") != "publish-decision"
                or decision.get("inputMode") != "flutter-widget-bridge"
                or decision.get("uiActionCount") != 3
                or not isinstance(decision.get("decisionId"), str)
                or not isinstance(decision.get("optionId"), str)
            ):
                raise AssertionError("native gate did not prove a visible canonical UI decision")
        if require_drafts:
            drafts = json.loads((native_output / "drafts.json").read_text(encoding="utf-8"))
            values = drafts.get("drafts")
            if not isinstance(values, list) or len(values) != 2:
                raise AssertionError("native gate did not record two independent draft recoveries")
            expected = (("A", "close"), ("B", "quit"))
            for label, action in expected:
                record = next(
                    (
                        value
                        for value in values
                        if isinstance(value, dict)
                        and value.get("label") == label
                        and value.get("action") == action
                    ),
                    None,
                )
                if (
                    record is None
                    or not isinstance(record.get("previousPid"), str)
                    or not isinstance(record.get("currentPid"), str)
                    or record["previousPid"] == record["currentPid"]
                    or record.get("nativeActionPath")
                    not in ({"close-shortcut", "close-menu-fallback"} if action == "close" else {"quit-shortcut"})
                    or not isinstance(record.get("preparedEpochMilliseconds"), int)
                    or not isinstance(record.get("driverReturnedEpochMilliseconds"), int)
                    or not isinstance(record.get("nativeActionSentEpochMilliseconds"), int)
                    or not record["preparedEpochMilliseconds"]
                    <= record["driverReturnedEpochMilliseconds"]
                    <= record["nativeActionSentEpochMilliseconds"]
                    or not isinstance(record.get("elapsedBeforeDebounceMilliseconds"), int)
                    or not 0 <= record["elapsedBeforeDebounceMilliseconds"] <= 350
                ):
                    raise AssertionError(f"native gate did not recover draft {label} via {action}")
                prepared = json.loads(
                    (native_output / "ui" / f"draft-{label}-prepared.json").read_text(
                        encoding="utf-8"
                    )
                )
                restored = json.loads(
                    (native_output / "ui" / f"draft-{label}-restored.json").read_text(
                        encoding="utf-8"
                    )
                )
                after_name = (
                    "draft-A-after-B-restarts.json"
                    if label == "A"
                    else "draft-B-after-restarts.json"
                )
                after_restarts = json.loads(
                    (native_output / "ui" / after_name).read_text(
                        encoding="utf-8"
                    )
                )
                expected_files = (prepared, restored, after_restarts)
                if (
                    any(value.get("status") != "passed" for value in expected_files)
                    or prepared.get("mode") != "prepare-comment-draft"
                    or any(value.get("mode") != "observe-comment-draft" for value in (restored, after_restarts))
                    or any(value.get("draftLabel") != label for value in expected_files)
                    or len({value.get("bodySha256") for value in expected_files}) != 1
                ):
                    raise AssertionError(f"native UI did not retain draft {label} across restarts")
        if require_regenerations:
            for generation in generations[1:]:
                generation_number = generation.get("generation")
                observed = json.loads(
                    (native_output / "ui" / f"generation-{generation_number}.json").read_text(
                        encoding="utf-8"
                    )
                )
                if (
                    observed.get("status") != "passed"
                    or observed.get("mode") != "observe-generation"
                    or observed.get("document", {}).get("artifactRevision")
                    != generation.get("reportRevision")
                ):
                    raise AssertionError(
                        f"native UI did not observe generation R{generation_number}"
                    )
    return generations


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mana-root", required=True, type=Path)
    parser.add_argument(
        "--profile", choices=("smoke", "decision-smoke", "draft-smoke"), default="smoke"
    )
    parser.add_argument("--output-root", type=Path, default=Path("build/native-feedback-audit"))
    parser.add_argument("--app", type=Path)
    parser.add_argument(
        "--preferences-root",
        type=Path,
        help="caller-owned local preferences root; retained after the native run",
    )
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    familiar_root = Path(__file__).resolve().parents[1]
    mana_root = args.mana_root.resolve()
    fixture = mana_root / "tests" / "run-story-start-human-feedback-fixture.sh"
    gate = familiar_root / "tests" / "run-macos-native-window-e2e.sh"
    if platform.system() != "Darwin":
        parser.error("native feedback smoke requires macOS")
    if not fixture.is_file():
        parser.error(f"missing Story Start fixture: {fixture}")
    if not gate.is_file():
        parser.error(f"missing native macOS gate: {gate}")

    run_id = f"run-{int(time.time())}-{hashlib.sha256(str(time.time_ns()).encode()).hexdigest()[:10]}"
    # The macOS bundle has its own working directory. Every path passed from
    # this outer runner to a Runner process must therefore be absolute rather
    # than relative to the Familiar checkout.
    output = (args.output_root / run_id).resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / "project"
    project.mkdir()
    native_output = output / "native"
    ui_port = reserve_loopback_port()
    ui_token = secrets.token_urlsafe(32)
    second_ui_port = reserve_loopback_port()
    second_ui_token = secrets.token_urlsafe(32)
    manifest = {
        "schemaVersion": "mana.familiar.native-feedback-e2e/v1",
        "status": "running",
        "profile": args.profile,
        "platform": platform.platform(),
        "project": "synthetic Story Start fixture",
        "repositories": {
            "familiar": repository_state(familiar_root),
            "mana": repository_state(mana_root),
        },
        "command": sys.argv,
    }
    write_json(output / "manifest.json", manifest)
    started = time.monotonic()
    try:
        app = args.app
        if app is None:
            app = familiar_root / "build/macos/Build/Products/Debug/Mana Familiar.app"
        if not args.skip_build:
            build = subprocess.run(
                ["flutter", "build", "macos", "--debug"], cwd=familiar_root, text=True, check=False
            )
            if build.returncode:
                raise RuntimeError(f"macOS debug build failed ({build.returncode})")
        command = [
            str(gate),
            "--app",
            str(app),
            "--project-root",
            str(project),
            "--mana-root",
            str(mana_root),
            "--story-start-fixture",
            str(fixture),
            "--evidence-dir",
            str(native_output),
            "--ui-driver",
            str(familiar_root / "tests" / "run-native-feedback-ui-driver.py"),
            "--first-ui-port",
            str(ui_port),
            "--first-ui-token",
            ui_token,
            "--second-ui-port",
            str(second_ui_port),
            "--second-ui-token",
            second_ui_token,
        ]
        if args.preferences_root is not None:
            command.extend(["--preferences-root", str(args.preferences_root.resolve())])
        if args.profile == "decision-smoke":
            command.extend(["--exercise-decision", "--skip-regenerations"])
        if args.profile == "draft-smoke":
            command.extend(["--exercise-drafts", "--skip-regenerations"])
        result = subprocess.run(command, cwd=familiar_root, text=True, check=False)
        if result.returncode:
            raise RuntimeError(f"native gate failed ({result.returncode})")
        generations = validate_native_evidence(
            native_output,
            require_ui=True,
            require_regenerations=args.profile == "smoke",
            require_decision=args.profile == "decision-smoke",
            require_drafts=args.profile == "draft-smoke",
        )
        report = {
            **manifest,
            "status": "passed",
            "durationSeconds": round(time.monotonic() - started, 3),
            "generations": generations,
            "nativeEvidence": str(native_output.relative_to(output)),
            "uiDriver": {
                "inputMode": "flutter-widget-bridge",
                "uiActionCount": (
                    9
                    if args.profile == "decision-smoke"
                    else 20
                    if args.profile == "draft-smoke"
                    else 6
                ),
                "regenerationObservations": 5 if args.profile == "smoke" else 0,
            },
        }
        write_json(output / "report.json", report)
        write_json(output / "manifest.json", report)
        print(f"Native feedback {args.profile} passed: {output}")
        return 0
    except BaseException as error:
        failure = {
            **manifest,
            "status": "failed",
            "durationSeconds": round(time.monotonic() - started, 3),
            "error": repr(error),
        }
        write_json(output / "failure.json", failure)
        write_json(output / "manifest.json", failure)
        print(f"Native feedback {args.profile} failed: {output}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
