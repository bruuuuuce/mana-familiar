#!/usr/bin/env python3
"""Deterministic C03 producer integration harness for Human Feedback.

It deliberately uses the public Mana command, isolated projects and an
independent expected model. C01/C02 remain read-only consumer harnesses.
Desktop-native lifecycle and Story Start decision consumption are separate
gates and are not claimed by this runner.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import subprocess
import sys
import tempfile
import time
import platform
from dataclasses import dataclass, field
from pathlib import Path
from threading import Lock
from typing import Callable


C03_PROFILES: dict[str, dict[str, int]] = {
    "smoke": {"seeds": 3, "actions": 100, "projects": 2, "documents": 10},
    "stress": {"seeds": 5, "actions": 2000, "projects": 3, "documents": 100},
    # These exercise the producer data path over the stated elapsed period.
    # They deliberately do not claim to exercise a native Flutter window.
    "desktop-long": {
        "seeds": 2,
        "actions": 150,
        "projects": 2,
        "documents": 30,
        "minimumDurationSeconds": 20 * 60,
    },
    "soak": {
        "seeds": 5,
        "actions": 200,
        "projects": 3,
        "documents": 100,
        "minimumDurationSeconds": 60 * 60,
    },
}


def action_interval_seconds(actions: int, minimum_duration_seconds: int) -> float:
    """Place the final action on, not before, the required duration bound."""
    if not minimum_duration_seconds:
        return 0.0
    return minimum_duration_seconds / max(actions - 1, 1)


@dataclass
class Thread:
    revision: int = 1
    state: str = "open"
    entries: list[str] = field(default_factory=list)


def write_json_atomically(path: Path, value: object) -> None:
    """Make audit evidence visible without exposing a half-written JSON file."""
    temporary = path.with_name(f".{path.name}.{time.time_ns()}.tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    temporary.replace(path)


def repository_state(path: Path) -> dict[str, object]:
    """Capture reproducible, non-payload-bearing checkout evidence."""
    def git(*arguments: str) -> str | None:
        result = subprocess.run(
            ["git", "-C", str(path), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.stdout.strip() if result.returncode == 0 else None

    return {
        "path": str(path),
        "revision": git("rev-parse", "HEAD"),
        "branch": git("branch", "--show-current"),
        "dirty": bool(git("status", "--porcelain")),
    }


def call(command: Path, project: Path, operation: str, request: dict, *, ok: bool = True) -> tuple[int, dict]:
    result = subprocess.run(
        [str(command), "--project-root", str(project), operation, "--request-stdin", "--json"],
        input=json.dumps(request, ensure_ascii=False),
        capture_output=True,
        text=True,
        check=False,
    )
    if ok and result.returncode != 0:
        raise AssertionError(f"{operation} failed ({result.returncode}): {result.stderr}")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise AssertionError(
            f"{operation} emitted invalid JSON: stdout={result.stdout!r}; stderr={result.stderr!r}"
        ) from error
    return result.returncode, payload


def list_threads(command: Path, project: Path, target: dict) -> list[dict]:
    """Read a complete, stable producer view rather than only page one."""
    for attempt in range(2):
        cursor: str | None = None
        view_revision: str | None = None
        thread_ids: set[str] = set()
        threads: list[dict] = []
        changed = False
        while True:
            request = {**target}
            if cursor is not None:
                request["cursor"] = cursor
            _, payload = call(command, project, "list", request)
            assert payload["schemaVersion"] == "mana.human-feedback.threads/v1"
            current_view = payload.get("viewRevision")
            assert current_view is None or isinstance(current_view, str)
            if view_revision is not None and current_view not in (None, view_revision):
                changed = True
                break
            view_revision = view_revision or current_view
            page = payload["threads"]
            assert isinstance(page, list)
            for thread in page:
                thread_id = thread.get("threadId")
                assert isinstance(thread_id, str) and thread_id not in thread_ids
                thread_ids.add(thread_id)
                threads.append(thread)
            cursor = payload.get("nextCursor")
            assert cursor is None or isinstance(cursor, str)
            if cursor is None:
                return threads
        if not changed:
            raise AssertionError("pagination did not terminate")
    raise AssertionError("thread view changed while C03 was reading it")


def run_seed(
    command: Path,
    project: Path,
    seed: int,
    actions: int,
    documents: int,
    trace: list[dict],
    checkpoint: Callable[[int, int], None],
    started: float,
    action_interval_seconds: float = 0.0,
) -> list[dict]:
    model: dict[str, Thread] = {}
    for index in range(actions):
        # Long-running profiles distribute real producer mutations across the
        # requested window instead of completing quickly and merely sleeping.
        if action_interval_seconds:
            due = started + index * action_interval_seconds
            delay = due - time.monotonic()
            if delay > 0:
                time.sleep(delay)
        target = {
            "artifactId": f"file:fixture-{seed}-{index % documents}.md",
            # A document revision normally remains stable while people add
            # several comments. Keeping it stable here makes C03 exercise a
            # realistic target index and pagination history; regeneration is
            # covered by the dedicated lifecycle E2E gate.
            "artifactRevision": f"sha256:revision-{seed}",
            "sectionId": f"section-{index % 3}",
        }
        key = f"c03-{seed}-{index}"
        body = f"seed {seed}, action {index}\n"
        _, created = call(command, project, "create", {
            **target,
            "author": "C03 runner 👩🏽‍💻",
            "body": body,
            "idempotencyKey": key,
        })
        thread_id = created["threadId"]
        model[thread_id] = Thread(entries=[body])
        # The same command must return the same producer result, never a copy.
        _, replay = call(command, project, "create", {
            **target,
            "author": "C03 runner 👩🏽‍💻",
            "body": body,
            "idempotencyKey": key,
        })
        assert replay == created
        if index % 5 == 0:
            _, reply = call(command, project, "reply", {
                "threadId": thread_id,
                "threadRevision": "1",
                "author": "Second window",
                "body": f"reply {seed}/{index}",
                "idempotencyKey": f"{key}-reply",
            })
            model[thread_id].revision = int(reply["threadRevision"])
            model[thread_id].entries.append(f"reply {seed}/{index}")
        if index % 17 == 0:
            expected = model[thread_id].revision
            concurrent_bodies = [
                f"concurrent A {seed}/{index}",
                f"concurrent B {seed}/{index}",
            ]
            def concurrent_reply(body: str) -> tuple[str, tuple[int, dict]]:
                writer = "a" if "concurrent A " in body else "b"
                return body, call(command, project, "reply", {
                    "threadId": thread_id,
                    "threadRevision": str(expected),
                    "author": "Concurrent writer",
                    "body": body,
                    "idempotencyKey": f"{key}-concurrent-{writer}",
                }, ok=False)
            with ThreadPoolExecutor(max_workers=2) as pool:
                outcomes = list(pool.map(concurrent_reply, concurrent_bodies))
            accepted = [(body, payload) for body, (code, payload) in outcomes if code == 0]
            conflicts = [payload for _, (code, payload) in outcomes if code == 3]
            assert len(accepted) == 1 and len(conflicts) == 1, outcomes
            model[thread_id].revision = int(accepted[0][1]["threadRevision"])
            model[thread_id].entries.append(accepted[0][0])
        if index % 11 == 0:
            expected = model[thread_id].revision
            _, resolved = call(command, project, "resolve", {
                "threadId": thread_id,
                "threadRevision": str(expected),
                "idempotencyKey": f"{key}-resolve",
            })
            model[thread_id].revision = int(resolved["threadRevision"])
            model[thread_id].state = "resolved"
            code, conflict = call(command, project, "reopen", {
                "threadId": thread_id,
                "threadRevision": str(expected),
                "idempotencyKey": f"{key}-stale",
            }, ok=False)
            assert code == 3 and conflict["status"] == "conflict"
        current = list_threads(command, project, target)
        ours = next(item for item in current if item["threadId"] == thread_id)
        expected_model = model[thread_id]
        assert int(ours["revision"]) == expected_model.revision
        assert ours["state"] == expected_model.state
        assert [entry["body"] for entry in ours["entries"]] == expected_model.entries
        trace.append({"seed": seed, "action": index, "threadId": thread_id, "revision": expected_model.revision})
        if (index + 1) % 25 == 0 or index + 1 == actions:
            checkpoint(seed, index + 1)
    return trace


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mana-root", required=True)
    parser.add_argument("--profile", choices=tuple(C03_PROFILES), default="smoke")
    parser.add_argument("--output-root", type=Path, default=Path("build/feedback-audit"))
    parser.add_argument(
        "--actions-per-seed",
        type=int,
        help="development override; reports the effective action count",
    )
    args = parser.parse_args()
    command = Path(args.mana_root) / "scripts" / "mana-human-feedback.sh"
    if not command.is_file():
        parser.error(f"missing Mana command: {command}")
    profile = C03_PROFILES[args.profile]
    seeds = profile["seeds"]
    actions = profile["actions"]
    if args.actions_per_seed is not None:
        if args.actions_per_seed < 1:
            parser.error("--actions-per-seed must be positive")
        actions = args.actions_per_seed
    minimum_duration = profile.get("minimumDurationSeconds", 0)
    # Overrides are developer-only short runs and must not quietly masquerade
    # as a 20/60-minute acceptance profile.
    if args.actions_per_seed is not None:
        minimum_duration = 0
    action_interval = action_interval_seconds(actions, minimum_duration)
    run_id = f"run-{int(time.time())}-{hashlib.sha256(str(time.time_ns()).encode()).hexdigest()[:10]}"
    output = args.output_root / run_id
    output.mkdir(parents=True, exist_ok=False)
    familiar_root = Path(__file__).resolve().parents[1]
    trace: list[dict] = []
    started = time.monotonic()
    evidence = {
        "schemaVersion": "mana.familiar.c03-human-feedback-progress/v1",
        "status": "running",
        "profile": args.profile,
        "seeds": seeds,
        "actionsPerSeed": actions,
        "projectCount": profile["projects"],
        "documentsPerProject": profile["documents"],
        "minimumDurationSeconds": minimum_duration,
        "executionScope": "producer-api",
        "limitations": [
            "This runner does not drive native Flutter windows; desktop lifecycle "
            "acceptance requires its dedicated native E2E gate."
        ],
        "command": sys.argv,
        "platform": platform.platform(),
        "repositories": {
            "familiar": repository_state(familiar_root),
            "mana": repository_state(Path(args.mana_root).resolve()),
        },
    }
    write_json_atomically(output / "manifest.json", evidence)

    progress_lock = Lock()
    completed_by_seed: dict[int, int] = {}

    def checkpoint(seed: int, completed_actions: int) -> None:
        # Seed workers share the output directory. Serialising only this tiny
        # checkpoint makes it valid JSON while mutations remain concurrent.
        with progress_lock:
            completed_by_seed[seed] = completed_actions
            write_json_atomically(output / "progress.json", {
                **evidence,
                "seed": seed,
                "completedActionsInSeed": completed_actions,
                "acceptedCreatesSoFar": sum(completed_by_seed.values()),
                "durationSeconds": round(time.monotonic() - started, 3),
            })

    with tempfile.TemporaryDirectory(prefix="mana-c03-") as raw_project:
        project_root = Path(raw_project)
        projects = [
            project_root / f"project-{index}"
            for index in range(profile["projects"])
        ]
        for project in projects:
            project.mkdir()
        try:
            # Seeds use independent models and idempotency keys. Running up to
            # one worker per project keeps the mandated five-seed stress within
            # CI's six-hour budget while still exercising writer contention on
            # the project reused by seed 3.
            with ThreadPoolExecutor(max_workers=profile["projects"]) as pool:
                futures = {
                    seed: pool.submit(
                        run_seed,
                        command,
                        projects[seed % len(projects)],
                        seed,
                        actions,
                        profile["documents"],
                        [],
                        checkpoint,
                        started,
                        action_interval,
                    )
                    for seed in range(seeds)
                }
                traces_by_seed = {
                    seed: futures[seed].result()
                    for seed in sorted(futures)
                }
            for seed in sorted(traces_by_seed):
                trace.extend(traces_by_seed[seed])
            assert len(trace) == seeds * actions, (
                f"C03 trace is incomplete: {len(trace)} != {seeds * actions}"
            )
            assert len({item["threadId"] for item in trace}) == len(trace), (
                "C03 producer reused a thread id for distinct create actions"
            )
            canonical = sorted(project_root.rglob(".mana/human-feedback/**/*.json"))
            assert canonical, "C03 did not produce canonical records"
            report = {
                "schemaVersion": "mana.familiar.c03-human-feedback/v1",
                "profile": args.profile,
                "seeds": seeds,
                "actionsPerSeed": actions,
                "projectCount": profile["projects"],
                "documentsPerProject": profile["documents"],
                "minimumDurationSeconds": minimum_duration,
                "executionScope": "producer-api",
                "acceptedCreates": seeds * actions,
                "durationSeconds": round(time.monotonic() - started, 3),
                "canonicalRecordCount": len(canonical),
                "traceSha256": hashlib.sha256(json.dumps(trace, sort_keys=True).encode()).hexdigest(),
                "command": sys.argv,
                "platform": platform.platform(),
                "repositories": {
                    "familiar": repository_state(familiar_root),
                    "mana": repository_state(Path(args.mana_root).resolve()),
                },
            }
            write_json_atomically(output / "action-trace.json", trace)
            write_json_atomically(output / "report.json", report)
            write_json_atomically(output / "manifest.json", {**evidence, "status": "passed"})
        except BaseException as error:
            write_json_atomically(output / "action-trace.json", trace)
            write_json_atomically(output / "failure.json", {
                **evidence,
                "status": "failed",
                "durationSeconds": round(time.monotonic() - started, 3),
                "acceptedCreatesSoFar": len(trace),
                "error": repr(error),
            })
            write_json_atomically(output / "manifest.json", {**evidence, "status": "failed"})
            raise
    print(f"C03 human-feedback {args.profile} passed: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"C03 human-feedback failed: {error}", file=sys.stderr)
        raise SystemExit(1)
