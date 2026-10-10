"""Adversarial stdlib tests for the distributed, offline metrics adapter."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
SCRIPT = ROOT / 'framework/templates/__brick__/scripts/aef/task-metrics.py'
spec = importlib.util.spec_from_file_location('metrics', SCRIPT)
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


def event(kind, second, task='root', interval=None, reason=None, outcome=None, identity=None):
    return dict(schema_version=1, event_id=identity or f'{kind}-{second}-{task}',
                run_id='run', task_id=task, lane_id=task, type=kind,
                at=f'2026-01-01T00:00:{second:02d}Z', recorded_at='2026-01-02T00:00:00Z',
                interval_id=interval, reason=reason, outcome=outcome, ref=None, metadata={})


class MetricsTests(unittest.TestCase):
    def test_overlap_pause_unknown_and_effort(self):
        events = [event('run_start', 0), event('run_stop', 50, outcome='done'),
                  event('active_start', 0, 'a', '1'), event('active_stop', 20, 'a', '1'),
                  event('active_start', 10, 'b', '1'), event('active_stop', 30, 'b', '1'),
                  event('wait_start', 30, 'a', '2', reason='human'), event('wait_stop', 40, 'a', '2'),
                  event('active_start', 45, 'a', '3')]
        result = metrics.summarize(events, 'run')
        self.assertEqual(result['elapsed_seconds'], 50)
        self.assertEqual(result['run_outcome'], 'done')
        self.assertEqual(result['active_union_seconds'], 30)
        self.assertEqual(result['lane_effort_seconds'], 40)
        self.assertEqual(result['waiting_by_reason_seconds'], {'human': 10})
        self.assertEqual(result['unknown_seconds'], 10)
        self.assertEqual(len(result['open_intervals']), 1)
        self.assertEqual(result, metrics.summarize(list(reversed(events)), 'run'))

    def test_incomplete_run_and_no_active_inference(self):
        result = metrics.summarize([event('run_start', 0), event('task_start', 1),
                                    event('task_stop', 5, outcome='implemented')], 'run')
        self.assertIsNone(result['elapsed_seconds'])
        self.assertIsNone(result['run_outcome'])
        self.assertEqual(result['task_outcomes'], {'root': 'implemented'})
        self.assertIsNone(result['unknown_seconds'])
        self.assertEqual(result['active_union_seconds'], 0)
        self.assertEqual(result['task_elapsed_seconds'], {'root': 4})
        self.assertIsNone(result['metadata']['run:run']['model'])

    def test_counters_not_human_inference(self):
        events = [event('run_start', 0), event('attempt', 1), event('correction', 2),
                  event('review', 3, outcome='changes_required'), event('test_failure', 4),
                  event('build_failure', 5), event('environment_blocker', 6),
                  event('ai_verification', 7, outcome='pass'), event('qa_escape', 8),
                  event('human_qa', 9, outcome='fail'), event('attempt', 10)]
        result = metrics.summarize(events, 'run')
        self.assertEqual(result['observed_counts']['attempt'], 2)
        self.assertEqual(result['observed_outcomes']['ai_verification'], {'pass': 1})
        self.assertEqual(result['observed_outcomes']['human_qa'], {'fail': 1})
        self.assertNotIn('human_accepted', result)
        for kind in ('correction', 'review', 'test_failure', 'build_failure', 'environment_blocker', 'qa_escape'):
            self.assertEqual(result['observed_counts'][kind], 1)

    def test_invalid_inputs_and_sequences(self):
        bad = [[], None, 1,
               dict(event('attempt', 1), at='2026-01-01T00:00:00+00:99'),
               dict(event('attempt', 1), at='2026-01-01T00:00:00-00:99'),
               dict(event('attempt', 1), at='2026-01-01T00:00:00+24:00'),
               dict(event('attempt', 1), at='2026-01-01T00:00:00'),
               dict(event('attempt', 1), at='2026-02-30T00:00:00Z'),
               dict(event('attempt', 1), type='imaginary'),
               dict(event('attempt', 1), event_id='../escape'),
               event('active_start', 1), event('human_qa', 1)]
        for item in bad:
            with self.subTest(item=item), self.assertRaises(ValueError):
                metrics.summarize([item], 'run')
        sequences = [[event('active_stop', 2, interval='x')],
                     [event('active_start', 5, interval='x'), event('active_stop', 2, interval='x')],
                     [event('run_start', 0), event('run_start', 1)],
                     [event('run_stop', 1, outcome='done')],
                     [event('run_start', 5), event('attempt', 2)],
                     [event('run_start', 0), event('run_stop', 1, outcome='done'), event('attempt', 2)]]
        for items in sequences:
            with self.subTest(items=items), self.assertRaises(ValueError):
                metrics.summarize(items, 'run')

    def test_duplicate_import_idempotency_and_conflicts(self):
        item = event('attempt', 1)
        self.assertEqual(metrics.summarize([item, item], 'run')['event_count'], 1)
        with self.assertRaises(ValueError):
            metrics.summarize([item, dict(item, reason='different')], 'run')

    def test_concurrent_atomic_writes_and_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            def append(identity, reason=None):
                return metrics.append(argparse.Namespace(store=directory, event_id=identity,
                    run='run', task='root', lane=None, type='attempt', at=None,
                    interval=None, reason=reason, outcome=None, ref=None, metadata='{}'))
            with ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(lambda i: append(f'event-{i}'), range(32)))
                retries = list(pool.map(lambda _: append('retry'), range(8)))
            files = list(Path(directory).glob('*.json'))
            self.assertEqual(len(files), 33)
            self.assertTrue(all(e == retries[0] for e in retries))
            self.assertEqual(metrics.summarize([json.loads(p.read_text()) for p in files], 'run')['event_count'], 33)
            with self.assertRaises(ValueError):
                append('retry', 'conflicting retry')
            self.assertEqual(len(list(Path(directory).iterdir())), 33)

    def test_markdown_contains_unknown_and_same_machine_summary(self):
        result = metrics.summarize([event('run_start', 0)], 'run')
        document = metrics.markdown(result)
        self.assertIn('| elapsed_seconds | unknown |', document)
        self.assertEqual(json.loads(document.split('```json\n')[1].split('\n```')[0]), result)


if __name__ == '__main__':
    unittest.main()
