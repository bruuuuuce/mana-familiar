#!/usr/bin/env python3
"""Publish a disposable native-feedback fixture through Mana's public pipeline.

Provider responses come from Mana's admitted synthetic regression fixtures.
Generation one is deterministic; later generations vary an existing task's
synthetic prose without adding scope, relations, or approvals.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mana-root', required=True, type=Path)
    parser.add_argument('--project-root', required=True, type=Path)
    parser.add_argument('--generation', required=True, type=int, choices=range(6))
    args = parser.parse_args()
    root = args.mana_root.resolve(strict=True)
    project = args.project_root.resolve(strict=True)
    workspace = project / '.mana/features/FEEDBACK-E2E'
    workspace.mkdir(parents=True, exist_ok=True)
    fixtures = root / 'tests/fixtures/story-start-scope-v2'
    bash = shutil.which('bash.exe' if os.name == 'nt' else 'bash')
    if not bash:
        raise SystemExit('Git Bash or Bash is required')
    with tempfile.TemporaryDirectory(prefix='familiar-native-provider-') as temporary:
        out = Path(temporary)
        environment = dict(os.environ, MANA_USER_LEARNING_ALLOW_STUB='true')
        for phase, name in [('discovery', 'DISCOVERY'), ('triage', 'TRIAGE'), ('planner', 'PLAN')]:
            value = json.loads((fixtures / phase / 'provider-output.json').read_text())
            if phase == 'planner' and args.generation >= 2:
                value['basePlan'][0]['description'] += f' Synthetic native generation {args.generation}.'
            path = out / f'{phase}.json'
            path.write_text(json.dumps(value) + '\n')
            environment[f'HUMAN_TEST_{name}'] = path.as_posix()
        stub = out / 'provider-stub'
        stub.write_text('''#!/usr/bin/env bash
last=""; for arg in "$@"; do last="$arg"; done
case "$last" in
 *COMPACT_DISCOVERY_PACKAGE*) cat "$HUMAN_TEST_DISCOVERY" ;;
 *COMPACT_DISCOVERY_V2*) cat "$HUMAN_TEST_TRIAGE" ;;
 *) cat "$HUMAN_TEST_PLAN" ;;
esac
''')
        stub.chmod(0o700)
        environment['MANA_USER_LEARNING_STUB_COMMAND'] = stub.as_posix()
        command = [bash, '--noprofile', '--norc', '-c',
                   '. "$1/scripts/lib/provider-dispatch.sh"; . "$1/scripts/lib/story-start-scope-v2.sh"; mana_story_start_scope_v2_run_public stub deterministic "$2" "$3"',
                   'native-feedback-fixture', root.as_posix(),
                   (fixtures / 'discovery/compact-package.json').as_posix(), workspace.as_posix()]
        result = subprocess.run(command, env=environment, check=False)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
