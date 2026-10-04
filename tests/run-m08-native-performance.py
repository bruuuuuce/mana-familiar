#!/usr/bin/env python3
"""Run the real Familiar desktop binary against generated M08 fixtures.

The application writes payload-free Flutter and native-window traces only when
the explicit --performance-trace-dir flag is present. This runner needs no
Accessibility permission and never drives product actions through the trace.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import statistics
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


def checked(command: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode != 0:
        raise RuntimeError(f"{command[0]} exited {result.returncode}: {result.stderr.strip()}")
    return result


def revision(root: Path) -> str:
    return checked(["git", "-C", str(root), "rev-parse", "HEAD"]).stdout.strip()


def dirty(root: Path) -> bool:
    return bool(checked(["git", "-C", str(root), "status", "--porcelain"]).stdout.strip())


def flutter_version() -> str:
    executable = "flutter.bat" if os.name == "nt" else "flutter"
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        if not directory:
            continue
        candidate = Path(directory) / executable
        if not candidate.is_file():
            continue
        try:
            root = candidate.resolve(strict=True).parent.parent
            value = json.loads((root / "bin" / "cache" / "flutter.version.json").read_text(encoding="utf-8"))
            framework = value.get("frameworkVersion")
            channel = value.get("channel")
            if isinstance(framework, str) and isinstance(channel, str):
                return f"{framework} ({channel})"
        except (OSError, json.JSONDecodeError):
            return "unavailable"
    return "unavailable"


def load_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else None
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def run_once(
    app: Path,
    project: Path,
    mana_root: Path,
    cache: Path,
    run_root: Path,
    timeout: float,
    diagnostic_directory: Path | None = None,
    destination: str = "overview",
) -> dict[str, Any]:
    trace = run_root / "trace"
    preferences = run_root / "preferences"
    cache.mkdir(parents=True, exist_ok=True)
    trace.mkdir(parents=True)
    preferences.mkdir(parents=True)
    environment = dict(os.environ)
    environment["MANA_CACHE_HOME"] = str(cache)
    route_milestone = {
        "overview": "first_meaningful_overview",
        "advanced": "advanced_catalog_visible",
        "knowledge": "knowledge_visible",
        "activity": "activity_page_visible",
    }[destination]
    if destination == "knowledge":
        checked(["python3", str(mana_root / "scripts" / "mana-catalog.py"),
                 "--project-root", str(project), "--json", "build"], env=environment)
        checked(["python3", str(mana_root / "scripts" / "mana-knowledge.py"),
                 "--project-root", str(project), "build", "--json"], env=environment)
    process = subprocess.Popen(
        [
            str(app),
            "--initial-destination",
            destination,
            "--project-root",
            str(project),
            "--mana-root",
            str(mana_root),
            "--preferences-root",
            str(preferences),
            "--window-session",
            run_root.name,
            "--performance-trace-dir",
            str(trace),
        ],
        cwd=str(app.parent),
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    deadline = time.monotonic() + timeout
    flutter: dict[str, Any] | None = None
    native: dict[str, Any] | None = None
    try:
        while time.monotonic() < deadline:
            if process.poll() is not None:
                stdout, stderr = process.communicate()
                raise RuntimeError(
                    f"desktop process exited {process.returncode} before evidence: {stdout[-500:]} {stderr[-500:]}"
                )
            flutter = load_json(trace / "flutter-performance.json")
            native = load_json(trace / "native-window.json")
            if flutter and native:
                milestones = flutter.get("milestones_us", {})
                frames = flutter.get("frames", {})
                if (destination != "overview" or milestones.get("optional_surfaces_settled") is not None) and milestones.get(route_milestone) is not None and frames.get("count", 0) > 0:
                    break
            time.sleep(0.05)
        else:
            raise TimeoutError("desktop performance evidence did not settle before timeout")

        assert flutter is not None
        initial_process_count = len(flutter.get("processes", []))
        refresh_source = project / ".mana" / "global" / "knowledge" / "document-00000.md"
        if not refresh_source.is_file():
            raise RuntimeError("fixture has no stable refresh source")
        source_bytes = refresh_source.read_bytes()
        for offset in range(5):
            temporary_source = refresh_source.with_name(f".{refresh_source.name}.{offset}.tmp")
            temporary_source.write_bytes(source_bytes)
            os.replace(temporary_source, refresh_source)
            time.sleep(0.01)
        refresh_deadline = time.monotonic() + timeout
        while time.monotonic() < refresh_deadline:
            flutter = load_json(trace / "flutter-performance.json")
            if flutter:
                milestones = flutter.get("milestones_us", {})
                if (
                    milestones.get("workspace_event") is not None
                    and milestones.get("refresh_visible_route") is not None
                    and len(flutter.get("processes", [])) >= initial_process_count + 2
                ):
                    break
            time.sleep(0.05)
        else:
            milestones = flutter.get("milestones_us", {}) if flutter else {}
            processes = flutter.get("processes", []) if flutter else []
            operations = [item.get("operation") for item in processes[initial_process_count:]]
            raise TimeoutError(
                "coalesced workspace refresh evidence did not settle before timeout "
                f"(workspace_event={'workspace_event' in milestones}, "
                f"refresh_visible_route={'refresh_visible_route' in milestones}, "
                f"refresh_processes={operations})"
            )
    except Exception as error:
        if diagnostic_directory is not None:
            diagnostic_directory.mkdir(parents=True, exist_ok=True)
            current = load_json(trace / "flutter-performance.json") or {}
            window = load_json(trace / "native-window.json") or {}
            diagnostic = {
                "schema": "mana-familiar.c04.native-failure/v1",
                "run": run_root.name,
                "error_type": type(error).__name__,
                "milestones_us": current.get("milestones_us", {}),
                "operations": [
                    {key: value for key, value in item.items() if key in {
                        "operation", "start_us", "completed_us", "elapsed_us", "exit_code", "response_bytes", "transport_error_code"
                    }}
                    for item in current.get("processes", [])
                ],
                "typed_projection": [
                    {key: value for key, value in item.items() if key in {
                        "schema", "elapsed_us", "offloaded", "failure_code"
                    }} for item in current.get("typed_projection", [])
                ],
                "probe_publication_failures": current.get("diagnostics", {}).get("publication_failures", 0),
                "frames": current.get("frames", {}),
                "rss_bytes": current.get("rss_bytes", {}),
                "process_to_window_presented_us": window.get("process_to_window_presented_us"),
            }
            (diagnostic_directory / f"{run_root.name}-failure.json").write_text(
                json.dumps(diagnostic, indent=2) + "\n", encoding="utf-8"
            )
        raise
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        if process.stdout:
            process.stdout.close()
        if process.stderr:
            process.stderr.close()
    assert flutter is not None and native is not None
    if flutter.get("build_mode") not in {"profile", "release"}:
        raise RuntimeError("native performance gate requires a profile or release app")
    if native.get("process_to_window_presented_us", -1) < 0:
        raise RuntimeError("native window timing is invalid")
    milestones = flutter["milestones_us"]
    frames = flutter["frames"]
    decode = flutter.get("decode", [])
    projections = flutter.get("typed_projection", [])
    processes = flutter.get("processes", [])
    return {
        "destination": destination,
        "route_ready_us": milestones[route_milestone] - milestones["project_loading_shell"],
        "build_mode": flutter["build_mode"],
        "native_window_us": native["process_to_window_presented_us"],
        "binding_to_first_frame_us": milestones["first_application_frame"] - milestones["binding_ready"],
        "project_to_loading_shell_us": milestones["project_loading_shell"] - milestones["binding_ready"],
        "loading_shell_to_meaningful_overview_us": milestones["first_meaningful_overview"] - milestones["project_loading_shell"],
        "visible_route_populated_us": milestones["visible_route_populated"],
        "optional_surfaces_settled_us": milestones.get("optional_surfaces_settled"),
        "workspace_refresh_us": milestones["refresh_visible_route"] - milestones["workspace_event"],
        "refresh_model_replaced": "refresh_model_replaced" in milestones,
        "frames": {
            "count": frames["count"],
            "critical_interval": frames["critical_interval"],
            "max_total_us": frames["max_total_us"],
        },
        "maximum_observed_rss_bytes": flutter["rss_bytes"]["maximum_observed"],
        "probe_publication_failures": flutter.get("diagnostics", {}).get("publication_failures", 0),
        "processes": processes,
        "refresh_processes": processes[initial_process_count:],
        "max_ui_isolate_decode_us": max(
            (item["elapsed_us"] for item in decode if not item["offloaded"]),
            default=0,
        ),
        "max_offloaded_decode_us": max(
            (item["elapsed_us"] for item in decode if item["offloaded"]),
            default=0,
        ),
        "max_typed_projection_us": max((item["elapsed_us"] for item in projections if not item.get("offloaded", False)), default=0),
        "max_offloaded_projection_us": max((item["elapsed_us"] for item in projections if item.get("offloaded", False)), default=0),
    }


def median(runs: list[dict[str, Any]], field: str) -> int | float:
    return statistics.median(run[field] for run in runs)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--mana-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--fixture-class", choices=("small", "medium", "large", "hostile-large"), default="large")
    parser.add_argument("--cold-runs", type=int, default=5)
    parser.add_argument("--warm-runs", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--destination", choices=("overview", "advanced", "knowledge"), default="overview")
    args = parser.parse_args()
    if args.cold_runs < 1 or args.warm_runs < 1 or args.timeout <= 0:
        parser.error("run counts and timeout must be positive")
    app = args.app.resolve(strict=True)
    mana_root = args.mana_root.resolve(strict=True)
    familiar_root = Path(__file__).resolve().parents[1]
    generator = mana_root / "scripts" / "generate-m08-fixture.py"
    if not generator.is_file():
        raise SystemExit("Mana fixture generator is missing")

    diagnostic_directory = args.output.parent / f"{args.output.stem}.diagnostics"

    def measured_run(*run_arguments: Any) -> dict[str, Any]:
        result = run_once(*run_arguments, diagnostic_directory=diagnostic_directory, destination=args.destination)
        diagnostic_directory.mkdir(parents=True, exist_ok=True)
        run_root = run_arguments[4]
        (diagnostic_directory / f"{run_root.name}-sample.json").write_text(
            json.dumps(result, indent=2) + "\n", encoding="utf-8"
        )
        return result

    with tempfile.TemporaryDirectory(prefix="mana-familiar-native-performance-") as temporary_value:
        temporary = Path(temporary_value)
        project = temporary / "project"
        checked(
            [
                "python3",
                str(generator),
                "--output",
                str(project),
                "--class",
                args.fixture_class,
                "--seed",
                "20260928",
            ]
        )
        manifest = json.loads((project / "m08-fixture-manifest.json").read_text(encoding="utf-8"))
        cold: list[dict[str, Any]] = []
        for index in range(args.cold_runs):
            cold.append(
                measured_run(
                    app,
                    project,
                    mana_root,
                    temporary / f"cold-cache-{index}",
                    temporary / f"cold-run-{index}",
                    args.timeout,
                )
            )
        warm_cache = temporary / "warm-cache"
        measured_run(app, project, mana_root, warm_cache, temporary / "warm-prime", args.timeout)
        warm = [
            measured_run(
                app,
                project,
                mana_root,
                warm_cache,
                temporary / f"warm-run-{index}",
                args.timeout,
            )
            for index in range(args.warm_runs)
        ]

    report = {
        "schema": "mana-familiar.c04.native-performance-matrix/v1" if args.destination == "overview" else "mana-familiar.c04.native-route-performance-matrix/v1",
        "environment": {
            "os": platform.platform(),
            "machine": platform.machine(),
            "python": platform.python_version(),
            "flutter": flutter_version(),
            "mana_revision": revision(mana_root),
            "mana_dirty": dirty(mana_root),
            "familiar_revision": revision(familiar_root),
            "familiar_dirty": dirty(familiar_root),
        },
        "destination": args.destination,
        "fixture": {
            "class": manifest["fixture_class"],
            "digest": manifest["fixture_digest"],
            "logical_counts": manifest["logical_counts"],
        },
        "runs": {"cold": cold, "warm": warm},
        "background_load_policy": (
            "route-minimal initial semantic snapshot; supporting context and activity "
            "after first meaningful model; raw catalog route-only"
        ),
        "cache_policy": {
            "cold": "isolated empty MANA_CACHE_HOME per run",
            "warm": "one priming run followed by repeated shared-cache runs",
        },
        "medians_us": {
            phase: {
                field: median(runs, field)
                for field in (
                    "route_ready_us",
                    "native_window_us",
                    "binding_to_first_frame_us",
                    "project_to_loading_shell_us",
                    "loading_shell_to_meaningful_overview_us",
                    "optional_surfaces_settled_us",
                    "workspace_refresh_us",
                    "maximum_observed_rss_bytes",
                    "max_ui_isolate_decode_us",
                    "max_offloaded_decode_us",
                    "max_typed_projection_us",
                )
                if field != "optional_surfaces_settled_us" or args.destination == "overview"
            }
            for phase, runs in (("cold", cold), ("warm", warm))
        },
        "privacy": {
            "source_content": False,
            "absolute_paths": False,
            "credentials": False,
            "responses": False,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
