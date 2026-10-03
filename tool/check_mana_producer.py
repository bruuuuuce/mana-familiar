#!/usr/bin/env python3
"""Verify the M08 producer checkout before running client CI."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--mana-root', required=True, type=Path)
args = parser.parse_args()
root = args.mana_root.resolve()
required = (
    'scripts/generate-m08-fixture.py',
    'scripts/mana-inspect.sh',
    'scripts/mana-knowledge.py',
    'scripts/mana-review-inbox.py',
    'scripts/mana-human-feedback.sh',
    'contracts/mana-inspect/v1/schemas/semantic-snapshot.schema.json',
)
missing = [name for name in required if not (root / name).is_file()]
revision = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], capture_output=True, text=True)
print(json.dumps({'schema': 'mana-familiar.m08.producer-prerequisites/v1',
                  'revision': revision.stdout.strip() if revision.returncode == 0 else None,
                  'missing': missing}))
if missing:
    raise SystemExit('M08/C03 producer prerequisites missing: integrate the Mana producer PRs into develop before rerunning client CI.')
if revision.returncode:
    raise SystemExit('Cannot identify the checked-out Mana producer revision.')
