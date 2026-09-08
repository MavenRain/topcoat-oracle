#!/usr/bin/env python3
"""Exercise the real M34 joiner with local mocked executables, never live legs."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile


SOURCE = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(SOURCE))
spec = importlib.util.spec_from_file_location('campaign_under_test', SOURCE / 'm34_campaign.py')
campaign = importlib.util.module_from_spec(spec)
spec.loader.exec_module(campaign)

MOCK = r'''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
import time

root = Path(__file__).resolve().parents[3]
cfg = json.loads((root / 'mock.json').read_text())
kind = Path(sys.argv[0]).name
def read(path):
    return [json.loads(line) for line in path.read_bytes().splitlines()]
def write(path, rows):
    path.write_text(''.join(json.dumps(r, separators=(',', ':')) + '\n' for r in rows))
if kind == 'm34_slice.exe':
    directory, first, count = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    if directory.exists():
        print('output must be absent', file=sys.stderr)
        sys.exit(1)
    directory.mkdir()
    # Wait for both the child marker and the parent cache publication. This
    # forces completion order without assumptions about process scheduling.
    predecessor = cfg.get('predecessors', {}).get(str(first))
    if predecessor is not None:
        deadline = time.monotonic() + 30
        marker = root / ('done_' + str(predecessor))
        cache = root / '_emit/m34/out/campaign1/parallel.json'
        while True:
            saved = json.loads(cache.read_text())['slices'] if cache.exists() else {}
            if marker.exists() and str(predecessor) in saved:
                break
            if time.monotonic() >= deadline:
                print('predecessor did not finish and enter cache: ' + str(predecessor),
                      file=sys.stderr)
                sys.exit(1)
            time.sleep(0.02)
    fault = cfg.get('faults', {}).get(str(first), '')
    if fault == 'failure':
        print('injected child failure', file=sys.stderr)
        sys.exit(1)
    runtime = (root / 'core/interp.ml').read_text()
    rows = [{'i': i, 'mode': 'read_only' if i % 2 == 0 else 'signal_writing',
             'size': 1, 'verdict': 'agree', 'runtime': runtime}
            for i in range(first, first + count)]
    traces = [{'i': i, 'steps': ['ok']} for i in range(first, first + count)]
    if fault == 'bad_index':
        rows[-1]['i'] += 1
    if fault == 'bad_count':
        rows.pop()
    if fault == 'bad_trace':
        traces[-1]['i'] += 1
    jheader, theader = cfg['jheader'].copy(), cfg['theader'].copy()
    if fault == 'bad_header':
        jheader['seed'] += 1
    write(directory / 'journal.jsonl', [jheader] + rows)
    write(directory / 'trace.jsonl', [theader] + traces)
    (root / ('done_' + str(first))).write_text(str(time.monotonic_ns()))
    sys.exit(0)
directory = Path(sys.argv[2])
js, ts = read(directory / 'journal.jsonl'), read(directory / 'trace.jsonl')
if len(js) != len(ts) or [r['i'] for r in js[1:]] != list(range(len(js) - 1)) or [r['i'] for r in ts[1:]] != list(range(len(ts) - 1)):
    print('invalid joined data', file=sys.stderr)
    sys.exit(1)
if kind == 'm34.exe':
    minimum = int(sys.argv[-1])
    if len(js) - 1 < minimum:
        print('short joined data', file=sys.stderr)
        sys.exit(1)
    print('mock validated report', len(js) - 1)
'''


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def write_rows(path, rows):
    path.write_text(''.join(json.dumps(row, separators=(',', ':')) + '\n' for row in rows))


@contextlib.contextmanager
def fixture(faults=None, predecessors=None):
    with tempfile.TemporaryDirectory(prefix='m34-join-test-') as td:
        root = Path(td)
        out = root / '_emit/m34/out/campaign1'
        out.mkdir(parents=True)
        jheader = {'m31': 1, 'seed': 42, 'batch': 100, 'plant': 'none', 'topcoat': 'a' * 40}
        theader = {'m32': 1, 'seed': 42, 'batch': 100, 'plant': 'none', 'topcoat': 'a' * 40}
        cfg = {'jheader': jheader, 'theader': theader, 'faults': faults or {},
               'predecessors': predecessors or {}}
        (root / 'mock.json').write_text(json.dumps(cfg))
        for name in ['core/interp.ml', 'bin/m31.ml', 'bin/m34_slice.ml',
                     'm34_campaign.py', 'archive_sources.py',
                     'driver-js/package.json', 'driver-js/package-lock.json']:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('runtime-v1')
        bindir = root / '_build/default/bin'
        bindir.mkdir(parents=True)
        for name in ['m32.exe', 'm34.exe', 'm34_slice.exe']:
            path = bindir / name
            path.write_text(MOCK)
            path.chmod(0o755)
        write_rows(out / 'journal.jsonl', [jheader] +
                   [{'i': i, 'mode': 'read_only' if i % 2 == 0 else 'signal_writing',
                     'size': 1, 'verdict': 'agree', 'runtime': 'runtime-v1'} for i in range(100)])
        write_rows(out / 'trace.jsonl', [theader] + [{'i': i, 'steps': ['ok']} for i in range(100)])
        before = tuple((out / name).read_bytes() for name in ['journal.jsonl', 'trace.jsonl'])
        yield root, out, before


def finish(root, out, total):
    with contextlib.redirect_stdout(io.StringIO()):
        campaign.finish(root, out, total)


def fails(call, contains=None):
    try:
        call()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        if contains is not None:
            require(contains in str(error), 'wrong refusal: ' + str(error))
        return
    raise AssertionError('operation unexpectedly succeeded')


def unchanged(out, before):
    require(tuple((out / name).read_bytes() for name in ['journal.jsonl', 'trace.jsonl']) == before,
            'live prefix was changed despite failure')


def test_out_of_order():
    with fixture(predecessors={'300': 200, '100': 300}) as (root, out, before):
        finish(root, out, 400)
        completed = sorted([100, 200, 300], key=lambda i: int((root / ('done_' + str(i))).read_text()))
        require(completed == [200, 300, 100], 'fixture did not finish out of order')
        state = json.loads((out / 'parallel.json').read_text())
        require(list(state['slices']) == ['200', '300', '100'],
                'the parent did not collect slices in the forced completion order')
        for name, prefix in zip(['journal.jsonl', 'trace.jsonl'], before):
            data = (out / name).read_bytes()
            require(data.startswith(prefix), 'prior evidence bytes changed')
            require([r['i'] for r in campaign.records(data)[1:]] == list(range(400)),
                    'join lost, reordered or repeated global indices')
        require(not (out / 'publishing.json').exists(), 'completed transaction marker remains')


def test_bad_slices():
    for fault in ['bad_index', 'bad_count', 'bad_trace', 'bad_header', 'failure']:
        with fixture(faults={'200': fault}, predecessors={'200': 100}) as (root, out, before):
            fails(lambda: finish(root, out, 300))
            unchanged(out, before)
            require(not (out / 'publishing.json').exists(), 'child failure entered publication')
            state = json.loads((out / 'parallel.json').read_text())
            require('100' in state['slices'], 'completed successful sibling was not cached')


def cached_fixture_action(mutate, expected):
    with fixture(faults={'200': 'failure'}, predecessors={'200': 100}) as (root, out, before):
        fails(lambda: finish(root, out, 300), 'slice failed')
        cfg = json.loads((root / 'mock.json').read_text())
        cfg['faults'] = {}
        (root / 'mock.json').write_text(json.dumps(cfg))
        mutate(root, out)
        after_mutation = tuple((out / name).read_bytes() for name in ['journal.jsonl', 'trace.jsonl'])
        fails(lambda: finish(root, out, 300), expected)
        unchanged(out, after_mutation)


def test_resume_identities():
    cached_fixture_action(lambda root, out: (root / 'core/interp.ml').write_text('runtime-v2'),
                          'parallel resume identity changed')
    cached_fixture_action(lambda root, out: (root / '_build/default/bin/m34_slice.exe').write_text(MOCK + '\n# changed\n'),
                          'parallel resume identity changed')
    def alter_prefix(root, out):
        path = out / 'journal.jsonl'
        rows = campaign.records(path.read_bytes())
        rows[1]['runtime'] = 'changed-prior-evidence'
        write_rows(path, rows)
    cached_fixture_action(alter_prefix, 'parallel resume identity changed')
    def alter_saved_slice(root, out):
        state = json.loads((out / 'parallel.json').read_text())
        path = Path(state['slices']['100']['directory']) / 'journal.jsonl'
        rows = campaign.records(path.read_bytes())
        rows[1]['runtime'] = 'changed-cached-evidence'
        write_rows(path, rows)
    cached_fixture_action(alter_saved_slice, 'saved slice changed')


def test_resume_reuses_siblings():
    with fixture(faults={'200': 'failure'}, predecessors={'200': 100}) as (root, out, before):
        fails(lambda: finish(root, out, 300), 'slice failed')
        first_completion = (root / 'done_100').read_bytes()
        cfg = json.loads((root / 'mock.json').read_text())
        cfg['faults'] = {}
        (root / 'mock.json').write_text(json.dumps(cfg))
        finish(root, out, 300)
        require((root / 'done_100').read_bytes() == first_completion, 'successful sibling ran again')
        require(len(campaign.records((out / 'journal.jsonl').read_bytes())) == 301,
                'resume did not finish exactly the requested population')


def test_publication_recovery():
    with fixture() as (root, out, before):
        original = campaign.replace_bytes
        def fail_trace(path, data):
            if path == out / 'trace.jsonl':
                raise OSError('injected second replacement failure')
            return original(path, data)
        campaign.replace_bytes = fail_trace
        try:
            fails(lambda: finish(root, out, 300), 'injected second replacement')
        finally:
            campaign.replace_bytes = original
        require((out / 'publishing.json').exists(), 'interrupted publication lost recovery metadata')
        require((out / 'trace.jsonl').read_bytes() == before[1], 'fault did not interrupt second replacement')
        finish(root, out, 300)
        for name, prefix in zip(['journal.jsonl', 'trace.jsonl'], before):
            data = (out / name).read_bytes()
            require(data.startswith(prefix), 'publication recovery changed prior evidence')
            require([r['i'] for r in campaign.records(data)[1:]] == list(range(300)),
                    'publication recovery did not restore a complete consistent pair')


def test_foreign_edit_during_publication():
    with fixture() as (root, out, before):
        original = campaign.replace_bytes
        def fail_trace(path, data):
            if path == out / 'trace.jsonl':
                raise OSError('injected interruption')
            return original(path, data)
        campaign.replace_bytes = fail_trace
        try:
            fails(lambda: finish(root, out, 300))
        finally:
            campaign.replace_bytes = original
        path = out / 'trace.jsonl'
        path.write_bytes(before[1] + b'foreign edit\n')
        snapshot = tuple((out / name).read_bytes() for name in ['journal.jsonl', 'trace.jsonl'])
        fails(lambda: finish(root, out, 300), 'live evidence changed outside publication')
        unchanged(out, snapshot)


def main():
    tests = [test_out_of_order, test_bad_slices, test_resume_identities,
             test_resume_reuses_siblings, test_publication_recovery,
             test_foreign_edit_during_publication]
    failed = []
    for test in tests:
        try:
            test()
            print('PASS', test.__name__, flush=True)
        except Exception as error:
            failed.append(test.__name__)
            print('FAIL', test.__name__, str(error), flush=True)
    print('m34 mocked orchestration:', len(tests) - len(failed), '/', len(tests), 'groups passed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
