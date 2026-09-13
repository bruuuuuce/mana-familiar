#!/usr/bin/env python3
"""Exercise the mounted Flutter feedback UI through its debug-only bridge.

The bridge is intentionally limited to widget callbacks. This driver still
uses Mana's public feedback command as an independent canonical-read oracle;
it never writes a project except by pressing the mounted panel's Publish
control through that bridge.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable


SECTION_ID = "base-implementation-plan"
AUTHOR = "Native E2E"
BODY = "Decisione osservata dalla UI\n\n- verifica Unicode: è"


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{time.time_ns()}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temporary.replace(path)


class Bridge:
    def __init__(self, port: int, token: str) -> None:
        self.port = port
        self.token = token

    def call(self, action: str, **arguments: str) -> dict[str, Any]:
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            payload = json.dumps({"token": self.token, "action": action, **arguments})
            connection.request(
                "POST", "/v1/ui", body=payload, headers={"Content-Type": "application/json"}
            )
            response = connection.getresponse()
            parsed = json.loads(response.read().decode("utf-8"))
        finally:
            connection.close()
        if response.status != 200:
            raise AssertionError(f"bridge {action} returned HTTP {response.status}: {parsed}")
        if not isinstance(parsed, dict):
            raise AssertionError(f"bridge {action} did not return an object")
        return parsed


def wait_for(
    bridge: Bridge, predicate: Callable[[dict[str, Any]], bool], description: str
) -> dict[str, Any]:
    deadline = time.monotonic() + 45
    last: object = None
    while time.monotonic() < deadline:
        try:
            status = bridge.call("status")
            last = status
            if predicate(status):
                return status
        except (OSError, TimeoutError, http.client.HTTPException, json.JSONDecodeError) as error:
            last = repr(error)
        time.sleep(0.25)
    raise AssertionError(f"timed out waiting for {description}: {last!r}")


def document(status: dict[str, Any]) -> dict[str, Any] | None:
    value = status.get("document")
    return value if isinstance(value, dict) else None


def panel(status: dict[str, Any]) -> dict[str, Any] | None:
    value = status.get("panel")
    return value if isinstance(value, dict) else None


def stable_document(status: dict[str, Any], revision: str | None = None) -> bool:
    value = document(status)
    if value is None:
        return False
    anchors = value.get("stableSectionAnchors")
    return (
        isinstance(anchors, dict)
        and SECTION_ID in anchors
        and (revision is None or value.get("artifactRevision") == revision)
    )


def visible_entry(status: dict[str, Any]) -> bool:
    value = panel(status)
    if value is None or value.get("loading") is True:
        return False
    threads = value.get("threads")
    if not isinstance(threads, list):
        return False
    return any(
        isinstance(thread, dict)
        and thread.get("linkState") == "valid"
        and any(
            isinstance(entry, dict)
            and entry.get("author") == AUTHOR
            and entry.get("body") == BODY
            for entry in thread.get("entries", [])
        )
        for thread in threads
    )


def canonical_entry(mana_root: Path, project_root: Path, target: dict[str, Any]) -> str:
    artifact_id = target.get("artifactId")
    revision = target.get("artifactRevision")
    if not isinstance(artifact_id, str) or not isinstance(revision, str):
        raise AssertionError("mounted panel has no canonical artifact target")
    command = [
        str(mana_root / "scripts" / "mana-human-feedback.sh"),
        "--project-root",
        str(project_root),
        "list-history",
        "--artifact-id",
        artifact_id,
        "--artifact-revision",
        revision,
        "--section-id",
        SECTION_ID,
        "--json",
    ]
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    if completed.returncode:
        raise AssertionError(f"canonical feedback read failed: {completed.stderr.strip()}")
    value = json.loads(completed.stdout)
    threads = value.get("threads")
    if not isinstance(threads, list):
        raise AssertionError("canonical feedback response has no thread list")
    for thread in threads:
        if not isinstance(thread, dict) or thread.get("linkState") != "valid":
            continue
        for entry in thread.get("entries", []):
            if isinstance(entry, dict) and entry.get("author") == AUTHOR and entry.get("body") == BODY:
                thread_id = thread.get("threadId")
                if isinstance(thread_id, str):
                    return thread_id
    raise AssertionError("published UI comment is absent from canonical feedback history")


def payload_free_document_status(status: dict[str, Any]) -> dict[str, Any]:
    value = document(status) or {}
    anchors = value.get("stableSectionAnchors")
    return {
        "artifactId": value.get("artifactId"),
        "artifactRevision": value.get("artifactRevision"),
        "activeSectionId": value.get("activeSectionId"),
        "stableSectionCount": len(anchors) if isinstance(anchors, dict) else 0,
    }


def publish_comment(args: argparse.Namespace, bridge: Bridge) -> dict[str, object]:
    status = wait_for(bridge, stable_document, "a mounted Story Start document with stable targets")
    bridge.call("selectSection", sectionId=SECTION_ID)
    status = wait_for(
        bridge,
        lambda current: document(current) is not None
        and document(current).get("activeSectionId") == SECTION_ID,
        "the selected stable section",
    )
    bridge.call("openComments")
    status = wait_for(
        bridge,
        lambda current: panel(current) is not None
        and panel(current).get("target", {}).get("sectionId") == SECTION_ID,
        "the mounted comments panel",
    )
    bridge.call("setComposer", author=AUTHOR, body=BODY)
    status = wait_for(
        bridge,
        lambda current: panel(current) is not None
        and panel(current).get("composer", {}).get("author") == AUTHOR
        and panel(current).get("composer", {}).get("body") == BODY,
        "the UI composer to retain Unicode multiline input",
    )
    target = panel(status).get("target")
    if not isinstance(target, dict):
        raise AssertionError("mounted panel lacks its target")
    bridge.call("publish")
    status = wait_for(bridge, visible_entry, "the published thread in the visible UI")
    thread_id = canonical_entry(args.mana_root, args.project_root, target)
    return {
        "schemaVersion": "mana.familiar.native-e2e-ui/v1",
        "status": "passed",
        "mode": "publish-comment",
        "inputMode": "flutter-widget-bridge",
        "uiActionCount": 4,
        "bodySha256": hashlib.sha256(BODY.encode("utf-8")).hexdigest(),
        "canonicalThreadId": thread_id,
        "document": payload_free_document_status(status),
    }


def observe_generation(args: argparse.Namespace, bridge: Bridge) -> dict[str, object]:
    status = wait_for(
        bridge,
        lambda current: stable_document(current, args.expected_revision),
        f"the mounted UI to observe {args.expected_revision}",
    )
    return {
        "schemaVersion": "mana.familiar.native-e2e-ui/v1",
        "status": "passed",
        "mode": "observe-generation",
        "inputMode": "flutter-widget-bridge",
        "uiActionCount": 0,
        "document": payload_free_document_status(status),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--mana-root", type=Path, required=True)
    parser.add_argument("--mode", choices=("publish-comment", "observe-generation"), required=True)
    parser.add_argument("--expected-revision")
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    if args.mode == "observe-generation" and not args.expected_revision:
        parser.error("--expected-revision is required for observe-generation")
    try:
        bridge = Bridge(args.port, args.token)
        result = (
            publish_comment(args, bridge)
            if args.mode == "publish-comment"
            else observe_generation(args, bridge)
        )
        write_json(args.evidence, result)
        return 0
    except BaseException as error:
        write_json(
            args.evidence,
            {
                "schemaVersion": "mana.familiar.native-e2e-ui/v1",
                "status": "failed",
                "mode": args.mode,
                "error": repr(error),
            },
        )
        print(f"native UI driver failed: {error!r}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
