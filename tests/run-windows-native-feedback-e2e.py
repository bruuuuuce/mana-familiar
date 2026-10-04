#!/usr/bin/env python3
"""Native WindowPattern.Close and draft isolation on disposable Windows fixtures.

Composer actions use Familiar's debug widget bridge; Close uses Windows UI
Automation, checks the exact process executable, and must happen before the
350 ms draft debounce. No security settings or global preferences are changed.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_driver', ROOT / 'tests/run-native-feedback-ui-driver.py')
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


def port():
    with socket.socket() as value:
        value.bind(('127.0.0.1', 0))
        return value.getsockname()[1]


def quoted(value):
    return "'" + str(value).replace("'", "''") + "'"


def close_window(process, app, bridge, draft=None):
    payload = json.dumps({'token': bridge.token, 'action': 'setComposer', **(draft or {})}).encode()
    encoded = base64.b64encode(payload).decode()
    script = f'''
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
$owned=Get-Process -Id {process.pid}
if($owned.Path -ine {quoted(app)}){{throw 'test process executable mismatch'}}
$window=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ProcessIdProperty,{process.pid}))
if($null -eq $window){{throw 'owned native window missing'}}
$pattern=$window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
$clock=[Diagnostics.Stopwatch]::StartNew()
'''
    if draft:
        script += f'''
$body=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{encoded}'))
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:{bridge.port}/v1/ui -ContentType application/json -Body ('{{"token":"' + ($body | ConvertFrom-Json).token + '","action":"status"}}') | Out-Null
$clock.Restart()
$result=Invoke-RestMethod -Method Post -Uri http://127.0.0.1:{bridge.port}/v1/ui -ContentType application/json -Body $body
if($result.panel.composer.body -cne ($body | ConvertFrom-Json).body){{throw 'composer did not retain the requested draft'}}
'''
    script += '''
$requested=$clock.Elapsed.TotalMilliseconds
$pattern.Close()
@{inputMode='windows-ui-automation';closeRequestedMilliseconds=$requested} | ConvertTo-Json -Compress
'''
    result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand', base64.b64encode(script.encode('utf-16le')).decode()], capture_output=True, text=True, check=True)
    evidence = json.loads(result.stdout.strip())
    process.wait(timeout=15)
    if draft:
        assert evidence['closeRequestedMilliseconds'] < 350, evidence
        evidence['bodySha256'] = hashlib.sha256(draft['body'].encode()).hexdigest()
    return evidence


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--mana-root', required=True, type=Path)
    parser.add_argument('--output-dir', required=True, type=Path)
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('this native acceptance runner requires Windows')
    app, mana = args.app.resolve(strict=True), args.mana_root.resolve(strict=True)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / 'project'
    project.mkdir()
    preferences = output / 'preferences'
    subprocess.run([sys.executable, str(ROOT / 'tests/run-story-start-human-feedback-fixture.py'), '--mana-root', str(mana), '--project-root', str(project), '--generation', '0'], check=True)
    processes = {}
    report = {'schemaVersion': 'mana.familiar.windows-native-feedback/v1', 'status': 'running', 'lifecycle': [], 'inputModes': ['flutter-widget-bridge', 'windows-ui-automation']}
    def start(label, ordinal):
        ui_port = port()
        trace = output / f'{label}-{ordinal}-trace'
        log = (output / f'{label}-{ordinal}.log').open('wb')
        process = subprocess.Popen([str(app), '--project-root', str(project), '--mana-root', str(mana), '--preferences-root', str(preferences), '--window-session', f'windows-{label}', '--initial-artifact', 'file:.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md', '--native-e2e-port', str(ui_port), '--native-e2e-token', 'synthetic-native-fixture-token', '--performance-trace-dir', str(trace)], stdout=log, stderr=subprocess.STDOUT)
        log.close()
        processes[label] = process
        bridge = driver.Bridge(ui_port, 'synthetic-native-fixture-token')
        driver.wait_for(bridge, driver.stable_document, 'native Windows document with stable producer targets')
        options = SimpleNamespace(project_root=project, mana_root=mana, draft_label=label)
        driver.open_stable_comment_panel(options, bridge)
        return process, bridge, trace, options
    def close_and_record(label, values, draft=None):
        process, bridge, trace, _ = values
        evidence = close_window(process, app, bridge, draft)
        marks = json.loads((trace / 'flutter-performance.json').read_text())['milestones_us']
        assert marks['close_preparation_completed'] >= marks['close_preparation_requested']
        report['lifecycle'].append({'windowSession': label, 'oldPid': process.pid, 'draftFlushCompleted': True, **evidence})
    try:
        first = start('A', 0)
        second = start('B', 0)
        # Prepare B independently, then close A immediately after its edit.
        driver.prepare_comment_draft(second[3], second[1])
        close_and_record('A', first, driver.DRAFTS['A'])
        first = start('A', 1)
        assert first[0].pid != report['lifecycle'][-1]['oldPid']
        driver.observe_comment_draft(first[3], first[1])
        driver.observe_comment_draft(second[3], second[1])
        close_and_record('B', second, driver.DRAFTS['B'])
        second = start('B', 1)
        driver.observe_comment_draft(second[3], second[1])
        driver.observe_comment_draft(first[3], first[1])
        report['publishedCommentAndReply'] = driver.publish_comment(first[3], first[1])
        close_and_record('A', first)
        close_and_record('B', second)
        report.update(status='passed', independentSessions=2, nativeCloses=4, verifiedRestarts=2, preDebounceCloses=2, unpublishedDraftsRemainNoncanonical=True, appSha256=hashlib.sha256(app.read_bytes()).hexdigest())
        print('Windows native feedback passed:', output)
    except Exception as error:
        report.update(status='failed', error=repr(error))
        raise
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        for process in processes.values():
            if process.poll() is None:
                process.terminate()  # Failure cleanup is never native-close proof.

if __name__ == '__main__':
    main()
