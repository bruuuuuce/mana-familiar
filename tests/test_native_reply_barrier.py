import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


class NativeReplyBarrierTest(unittest.TestCase):
    def test_holds_reply_and_forwards_exact_stdin_after_release(self):
        bash = shutil.which('bash')
        if not bash:
            self.skipTest('Bash required')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            producer = root / 'producer/scripts'
            producer.mkdir(parents=True)
            (producer / 'mana-human-feedback.sh').write_text('#!/usr/bin/env bash\ncat\n')
            (producer / 'mana-human-feedback.sh').chmod(0o755)
            project = root / 'project'
            project.mkdir()
            wrapper = project / 'mana'
            shutil.copyfile(Path(__file__).with_name('native-human-feedback-fault-wrapper.sh'), wrapper)
            markers = project / '.native-e2e-faults'
            markers.mkdir()
            (markers / 'next-reply-barrier').touch()
            payload = b'{"body":"synthetic\\nreply"}\n'
            child = subprocess.Popen([bash, str(wrapper), 'human-feedback', 'reply', '--request-stdin'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=dict(os.environ, MANA_FAMILIAR_NATIVE_E2E_MANA_ROOT=str(producer.parent)))
            try:
                child.stdin.write(payload)
                child.stdin.close()
                deadline = time.monotonic() + 5
                while not (markers / 'reply-barrier-entered').exists():
                    self.assertIsNone(child.poll())
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(.02)
                self.assertIsNone(child.poll())
                (markers / 'reply-barrier-release').touch()
                self.assertEqual(child.stdout.read(), payload)
                self.assertEqual(child.wait(timeout=5), 0)
                self.assertFalse((markers / 'reply-barrier-entered').exists())
                self.assertFalse((markers / 'reply-barrier-release').exists())
            finally:
                if child.poll() is None:
                    child.terminate()
                    child.wait(timeout=5)
                child.stdout.close()
                child.stderr.close()
