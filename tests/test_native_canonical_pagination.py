import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('native_driver', Path(__file__).with_name('run-native-feedback-ui-driver.py'))
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class CanonicalPaginationTest(unittest.TestCase):
    def page(self, threads, cursor=None, revision='sha256:view'):
        return SimpleNamespace(returncode=0, stderr='', stdout=json.dumps(dict(threads=threads, nextCursor=cursor, viewRevision=revision)))

    def test_counts_body_on_later_page(self):
        first = dict(threadId='thread_a', entries=[])
        second = dict(threadId='thread_b', entries=[dict(body='accepted')])
        with patch.object(driver, 'producer_result', side_effect=[self.page([first], 'thread_a'), self.page([second])]) as invoke:
            self.assertEqual(driver.canonical_body_count(Path('/mana'), Path('/project'), dict(artifactId='file:a', artifactRevision='sha256:a'), body='accepted'), 1)
            self.assertEqual(invoke.call_args_list[1].args[0][-2:], ['--cursor', 'thread_a'])

    def test_rejects_changed_snapshot(self):
        with patch.object(driver, 'producer_result', side_effect=[self.page([dict(threadId='thread_a')], 'thread_a'), self.page([], revision='sha256:changed')]):
            with self.assertRaisesRegex(AssertionError, 'changed during pagination'):
                driver.canonical_threads(Path('/mana'), Path('/project'), dict(artifactId='file:a', artifactRevision='sha256:a'))
