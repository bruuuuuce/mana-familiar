import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('native_performance', Path(__file__).with_name('run-m08-native-performance.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class NativePerformanceFailureEvidenceTest(unittest.TestCase):
    def test_windows_cleanup_stops_only_the_owned_process_tree(self):
        process = Mock(pid=4321)
        process.poll.return_value = None
        with patch.object(runner.subprocess, 'run', return_value=Mock(returncode=0)) as stop:
            runner.stop_test_process(process, windows=True)
        self.assertEqual(stop.call_args.args[0], ['taskkill.exe', '/PID', '4321', '/T', '/F'])
        process.terminate.assert_not_called()
        process.wait.assert_called_once_with(timeout=5)
        with patch.object(runner.subprocess, 'run', return_value=Mock(returncode=1)):
            with self.assertRaisesRegex(RuntimeError, 'process tree'):
                runner.stop_test_process(process, windows=True)

    def test_timeout_retains_payload_free_evidence_after_temp_cleanup(self):
        with tempfile.TemporaryDirectory() as output:
            evidence = Path(output) / 'diagnostics'
            with tempfile.TemporaryDirectory() as fixture:
                root = Path(fixture)
                run = root / 'warm-prime'
                process = Mock()
                process.poll.return_value = None
                process.wait.return_value = 0

                def start(*args, **kwargs):
                    trace = run / 'trace'
                    (trace / 'flutter-performance.json').write_text(json.dumps({
                        'milestones_us': {'project_loading_shell': 120},
                        'processes': [{'operation': 'project', 'start_us': 150,
                                       'completed_us': 500, 'response_body': 'do-not-persist',
                                       'arguments': ['private-path']}],
                        'frames': {'count': 1},
                        'rss_bytes': {'maximum_observed': 1000},
                        'response': 'do-not-persist',
                    }))
                    return process

                with patch.object(runner.subprocess, 'Popen', side_effect=start), \
                     patch.object(runner.time, 'monotonic', side_effect=[0, 2]):
                    with self.assertRaises(TimeoutError):
                        runner.run_once(root / 'app', root / 'project', root / 'mana',
                                        root / 'cache', run, 1, evidence)
                process.terminate.assert_called_once()
            raw = (evidence / 'warm-prime-failure.json').read_text()
            result = json.loads(raw)
            self.assertEqual(result['error_type'], 'TimeoutError')
            self.assertEqual(result['milestones_us'], {'project_loading_shell': 120})
            self.assertEqual(result['operations'], [{'operation': 'project', 'start_us': 150,
                                                     'completed_us': 500}])
            self.assertNotIn('do-not-persist', raw)
            self.assertNotIn('private-path', raw)


if __name__ == '__main__':
    unittest.main()
