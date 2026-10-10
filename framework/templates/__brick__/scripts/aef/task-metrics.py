#!/usr/bin/env python3
"""Optional, offline AEF observability. No lifecycle or approval authority."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid

TYPES = {'run_start', 'run_stop', 'task_start', 'task_stop', 'active_start',
         'active_stop', 'wait_start', 'wait_stop', 'attempt', 'review', 'correction',
         'test_failure', 'build_failure', 'environment_blocker', 'ai_verification',
         'human_qa', 'qa_escape'}
COUNTERS = TYPES - {'run_start', 'run_stop', 'task_start', 'task_stop',
                    'active_start', 'active_stop', 'wait_start', 'wait_stop'}
META = ('scope', 'model', 'harness', 'framework_revision', 'parent_task')


def timestamp(value):
    if not isinstance(value, str) or not re.fullmatch(
            r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)', value):
        raise ValueError('timestamp must be timezone-aware ISO 8601')
    if value[-1] != 'Z' and (int(value[-5:-3]) > 23 or int(value[-2:]) > 59):
        raise ValueError('invalid timestamp timezone offset')
    return datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()


def now():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


def validate(event):
    if not isinstance(event, dict):
        raise ValueError('event must be an object')
    if event.get('schema_version') != 1 or event.get('type') not in TYPES:
        raise ValueError('unsupported schema_version or event type')
    for field in ('event_id', 'run_id', 'task_id', 'lane_id'):
        if not isinstance(event.get(field), str) or not re.fullmatch(r'[A-Za-z0-9_.-]+', event[field]):
            raise ValueError(f'invalid {field}')
    timestamp(event.get('at'))
    timestamp(event.get('recorded_at'))
    if not isinstance(event.get('metadata'), dict):
        raise ValueError('metadata must be an object')
    for field in ('interval_id', 'reason', 'outcome', 'ref'):
        if event.get(field) is not None and not isinstance(event[field], str):
            raise ValueError(f'{field} must be string or null')
    if event['type'].startswith(('active_', 'wait_')) and not event.get('interval_id'):
        raise ValueError('interval events require --interval')
    if event['type'] == 'wait_start' and not event.get('reason'):
        raise ValueError('wait_start requires --reason')
    if event['type'] in {'run_stop', 'task_stop', 'review', 'human_qa', 'ai_verification'} and not event.get('outcome'):
        raise ValueError('this event requires --outcome')


def git_value(*args):
    try:
        result = subprocess.run(['git', *args], capture_output=True, text=True, timeout=5)
        return result.stdout.strip() or None if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def append(args):
    event = dict(schema_version=1, event_id=args.event_id or uuid.uuid4().hex,
                 run_id=args.run, task_id=args.task, lane_id=args.lane or args.task,
                 type=args.type, at=args.at or now(), recorded_at=now(),
                 interval_id=args.interval, reason=args.reason, outcome=args.outcome,
                 ref=args.ref, metadata=json.loads(args.metadata))
    validate(event)
    event['git'] = {'head': git_value('rev-parse', 'HEAD'),
                    'branch': git_value('branch', '--show-current')}
    directory = Path(args.store)
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / (event['event_id'] + '.json')
    fd, temporary = tempfile.mkstemp(prefix='.event-', dir=directory)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(event, stream, sort_keys=True, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, destination)  # complete file visible atomically, never overwrite
        except FileExistsError:
            previous = json.loads(destination.read_text())
            comparable = lambda e: {k: v for k, v in e.items()
                                    if k not in ({'recorded_at', 'git'} | ({'at'} if args.at is None else set()))}
            if comparable(previous) != comparable(event):
                raise ValueError('event-id already exists with different content')
            event = previous
    finally:
        os.unlink(temporary)
    return event


def union(intervals):
    total, end = 0.0, None
    for start, stop in sorted(intervals):
        total += max(0, stop - max(start, end if end is not None else start))
        end = max(stop, end if end is not None else stop)
    return total


def summarize(events, run):
    selected, seen = [], {}
    for event in events:
        validate(event)
        identity = event['event_id']
        if identity in seen:
            if seen[identity] != event:
                raise ValueError('conflicting duplicate event_id')
            continue
        seen[identity] = event
        if event['run_id'] == run:
            selected.append(event)
    if not selected:
        raise ValueError('no events for requested run')
    selected.sort(key=lambda e: (timestamp(e['at']), e['event_id']))
    warnings, intervals = [], defaultdict(list)
    boundaries = defaultdict(list)
    counts, outcomes = Counter(), defaultdict(Counter)
    for event in selected:
        kind = event['type']
        if kind in COUNTERS:
            counts[kind] += 1
            if event['outcome'] is not None:
                outcomes[kind][event['outcome']] += 1
        if kind.startswith(('active_', 'wait_')):
            family, action = kind.split('_')
            intervals[(event['task_id'], event['lane_id'], family, event['interval_id'])].append(event)
        if kind.startswith(('run_', 'task_')):
            family, action = kind.split('_')
            boundaries[(family, run if family == 'run' else event['task_id'])].append(event)
    active, waits, lane_active = [], defaultdict(list), defaultdict(list)
    open_intervals = []
    for key, values in sorted(intervals.items()):
        family = key[2]
        starts = [e for e in values if e['type'] == family + '_start']
        stops = [e for e in values if e['type'] == family + '_stop']
        if len(starts) != 1 or len(stops) > 1 or (stops and timestamp(stops[0]['at']) < timestamp(starts[0]['at'])):
            raise ValueError(f'invalid interval sequence: {key}')
        if not stops:
            open_intervals.append({'task_id': key[0], 'lane_id': key[1], 'kind': family,
                                   'interval_id': key[3], 'started_at': starts[0]['at']})
            continue  # never extrapolate an unattended/crashed lane into active time
        pair = (timestamp(starts[0]['at']), timestamp(stops[0]['at']))
        if family == 'active':
            active.append(pair)
            lane_active[(key[0], key[1])].append(pair)
        else:
            waits[starts[0]['reason']].append(pair)
    durations, metadata, completion = {}, {}, {}
    for key, values in sorted(boundaries.items()):
        starts = [e for e in values if e['type'] == key[0] + '_start']
        stops = [e for e in values if e['type'] == key[0] + '_stop']
        if len(starts) != 1 or len(stops) > 1:
            raise ValueError(f'invalid lifecycle sequence: {key}')
        duration = timestamp(stops[0]['at']) - timestamp(starts[0]['at']) if stops else None
        if duration is not None and duration < 0:
            raise ValueError('stop precedes start')
        durations[':'.join(key)] = duration
        completion[':'.join(key)] = stops[0]['outcome'] if stops else None
        metadata[':'.join(key)] = {k: starts[0]['metadata'].get(k) for k in META}
    run_events = boundaries.get(('run', run), [])
    start = next((timestamp(e['at']) for e in run_events if e['type'] == 'run_start'), None)
    stop = next((timestamp(e['at']) for e in run_events if e['type'] == 'run_stop'), None)
    if start is not None and any(timestamp(e['at']) < start for e in selected):
        raise ValueError('event precedes run_start')
    if stop is not None and any(timestamp(e['at']) > stop for e in selected):
        raise ValueError('event follows run_stop')
    waiting = [p for values in waits.values() for p in values]
    elapsed = durations.get('run:' + run)
    unknown = max(0.0, elapsed - union(active + waiting)) if elapsed is not None else None
    if open_intervals:
        warnings.append('Unclosed intervals excluded; their duration is unknown.')
    if elapsed is None:
        warnings.append('Run start/stop incomplete; elapsed and unknown duration are null.')
    if len({json.dumps(v, sort_keys=True) for v in metadata.values()}) > 1:
        warnings.append('Metadata varies across tasks; do not treat this as a controlled comparison.')
    return dict(schema_version=1, run_id=run, event_count=len(selected), metadata=metadata,
                elapsed_seconds=elapsed, run_outcome=completion.get('run:' + run),
                task_outcomes={k[5:]: v for k, v in completion.items() if k.startswith('task:')},
                active_union_seconds=union(active),
                lane_effort_seconds=sum(union(p) for p in lane_active.values()),
                waiting_union_seconds=union(waiting),
                waiting_by_reason_seconds={k: union(v) for k, v in sorted(waits.items())},
                unknown_seconds=unknown, task_elapsed_seconds={k[5:]: v for k, v in durations.items() if k.startswith('task:')},
                observed_counts={k: counts[k] for k in sorted(COUNTERS)},
                observed_outcomes={k: dict(sorted(v.items())) for k, v in sorted(outcomes.items())},
                open_intervals=open_intervals, warnings=warnings,
                interpretation='Observed events only. Zero counts do not prove absence. Active intervals are not CPU/token time. AI verification is not human acceptance.')


def markdown(summary):
    lines = ['# AEF task metrics', '', f"Run: `{summary['run_id']}`", '', '| Metric | Seconds |', '|---|---:|']
    for key in ('elapsed_seconds', 'active_union_seconds', 'lane_effort_seconds', 'waiting_union_seconds', 'unknown_seconds'):
        value = summary[key]
        lines.append(f"| {key} | {'unknown' if value is None else value} |")
    lines += ['', '## Machine-readable details', '', '```json', json.dumps(summary, indent=2, sort_keys=True), '```', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--store', default='docs/engineering/dispatch/metrics/events')
    commands = parser.add_subparsers(dest='command', required=True)
    event = commands.add_parser('event', help='append one immutable event')
    for flag in ('run', 'task', 'type'):
        event.add_argument('--' + flag, required=True, **({'choices': sorted(TYPES)} if flag == 'type' else {}))
    for flag in ('lane', 'interval', 'reason', 'outcome', 'ref', 'event-id', 'at'):
        event.add_argument('--' + flag)
    event.add_argument('--metadata', default='{}')
    summary = commands.add_parser('summary', help='render reproducible observed metrics')
    summary.add_argument('--run', required=True)
    summary.add_argument('--format', choices=['json', 'markdown'], default='json')
    args = parser.parse_args()
    try:
        if args.command == 'event':
            result = append(args)
        else:
            events = [json.loads(p.read_text()) for p in sorted(Path(args.store).glob('*.json'))]
            result = summarize(events, args.run)
            if args.format == 'markdown':
                print(markdown(result), end='')
                return
        print(json.dumps(result, indent=2, sort_keys=True))
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(f'metrics error: {error}', file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
