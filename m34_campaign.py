#!/usr/bin/env python3
"""Finish a journal using three isolated batch workers and validate the join."""

from concurrent.futures import CancelledError, ThreadPoolExecutor, as_completed
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import sys
from m34_verdict import source_inventory


def require(condition, text):
    if not condition:
        raise ValueError(text)


def records(data):
    return [json.loads(line) for line in data.splitlines()]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def replace_bytes(path, data):
    temporary = path.with_suffix(path.suffix + '.pending')
    temporary.write_bytes(data)
    temporary.replace(path)


def implementation(root):
    paths = source_inventory(root) | {'_build/default/bin/m34_slice.exe',
                                     '_build/default/bin/m34.exe', '_build/default/bin/m32.exe'}
    return {name: digest((root / name).read_bytes()) for name in sorted(paths)}


def recover_publication(root, out, total):
    marker = out / 'publishing.json'
    if not marker.exists():
        return
    transaction = json.loads(marker.read_text())
    require(transaction['implementation'] == implementation(root), 'implementation changed during publication')
    joined = Path(transaction['joined'])
    for name in ['journal.jsonl', 'trace.jsonl']:
        require(digest((joined / name).read_bytes()) == transaction['new'][name], 'joined evidence changed')
        require(digest((out / name).read_bytes()) in [transaction['old'][name], transaction['new'][name]],
                'live evidence changed outside publication')
    with (joined / 'recovery-report.md').open('wb') as report:
        subprocess.run([str(root / '_build/default/bin/m34.exe'), 'report', str(joined),
                        '--minimum', str(total)], stdout=report, check=True)
    for name in ['journal.jsonl', 'trace.jsonl']:
        replace_bytes(out / name, (joined / name).read_bytes())
    marker.unlink()


def validate_slice(directory, start, count, jheader, theader):
    journal = (directory / 'journal.jsonl').read_bytes()
    trace = (directory / 'trace.jsonl').read_bytes()
    js, ts = records(journal), records(trace)
    require(js[0] == jheader and ts[0] == theader, 'slice header mismatch')
    expected = list(range(start, start + count))
    require([row['i'] for row in js[1:]] == expected, 'slice journal index/count mismatch')
    require([row['i'] for row in ts[1:]] == expected, 'slice trace index/count mismatch')
    return journal, trace


def finish(root, out, total):
    recover_publication(root, out, total)
    parent = out.parent
    jpath, tpath = out / 'journal.jsonl', out / 'trace.jsonl'
    prefix_j, prefix_t = jpath.read_bytes(), tpath.read_bytes()
    js, ts = records(prefix_j), records(prefix_t)
    start = len(js) - 1
    require(start <= total and len(js) == len(ts), 'invalid existing journal length')
    require([r['i'] for r in js[1:]] == list(range(start)), 'invalid existing journal indices')
    require([r['i'] for r in ts[1:]] == list(range(start)), 'invalid existing trace indices')
    require(js[0]['plant'] == 'none' and js[0]['batch'] == 100, 'requires unplanted batches of 100')
    require(start == total or start % 100 == 0, 'resume at a complete 100-sample boundary')
    subprocess.run([str(root / '_build/default/bin/m32.exe'), 'check', str(out)], check=True)
    state_path = out / 'parallel.json'
    identity = {'journal': digest(prefix_j), 'trace': digest(prefix_t), 'total': total,
                'start': start, 'seed': js[0]['seed'], 'implementation': implementation(root)}
    state = {'identity': identity, 'slices': {}}
    if state_path.exists() and start != total:
        state = json.loads(state_path.read_text())
        require(state['identity'] == identity, 'parallel resume identity changed')
    if start == total:
        print('m34 campaign already complete:', total, flush=True)
        return

    def run_slice(first, count):
        directory = Path(tempfile.mkdtemp(prefix='slice_' + str(first) + '_', dir=parent))
        directory.rmdir()
        stdout_path, stderr_path = Path(str(directory) + '.stdout'), Path(str(directory) + '.stderr')
        with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
            result = subprocess.run(
                [str(root / '_build/default/bin/m34_slice.exe'), str(directory), str(first),
                 str(count), str(js[0]['seed']), str(root), str(root.parent / 'topcoat')],
                cwd=root, stdout=stdout, stderr=stderr)
        require(result.returncode == 0, 'slice failed; see ' + str(stderr_path))
        a, b = validate_slice(directory, first, count, js[0], ts[0])
        return {'directory': str(directory), 'journal': digest(a), 'trace': digest(b)}

    batches = [(first, min(100, total - first)) for first in range(start, total, 100)]
    pending = []
    for first, count in batches:
        saved = state['slices'].get(str(first))
        if saved is None:
            pending.append((first, count))
        else:
            a, b = validate_slice(Path(saved['directory']), first, count, js[0], ts[0])
            require(digest(a) == saved['journal'] and digest(b) == saved['trace'], 'saved slice changed')
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(run_slice, first, count): first for first, count in pending}
        errors = []
        for future in as_completed(futures):
            first = futures[future]
            try:
                result = future.result()
            except CancelledError:
                continue
            except (ValueError, KeyError, OSError, IndexError) as error:
                errors.append(str(error))
                for waiting in futures:
                    waiting.cancel()
                continue
            state['slices'][str(first)] = result
            replace_bytes(state_path, (json.dumps(state, indent=2) + '\n').encode())
            print('m34 parallel batch', first, 'completed', len(state['slices']), 'of', len(batches), flush=True)
        require(not errors, '; '.join(errors))

    all_j, all_t = prefix_j, prefix_t
    for first, count in batches:
        saved = state['slices'][str(first)]
        a, b = validate_slice(Path(saved['directory']), first, count, js[0], ts[0])
        require(digest(a) == saved['journal'] and digest(b) == saved['trace'], 'slice changed before join')
        all_j += b''.join(a.splitlines(keepends=True)[1:])
        all_t += b''.join(b.splitlines(keepends=True)[1:])
    joined = Path(tempfile.mkdtemp(prefix='joined_', dir=parent))
    (joined / 'journal.jsonl').write_bytes(all_j)
    (joined / 'trace.jsonl').write_bytes(all_t)
    with (joined / 'report.md').open('wb') as report:
        subprocess.run([str(root / '_build/default/bin/m34.exe'), 'report', str(joined),
                        '--minimum', str(total)], stdout=report, check=True)
    require(jpath.read_bytes() == prefix_j and tpath.read_bytes() == prefix_t,
            'live journal changed while workers ran')
    require(implementation(root) == identity['implementation'], 'implementation changed while workers ran')
    transaction = {'joined': str(joined), 'implementation': identity['implementation'],
                   'old': {'journal.jsonl': digest(prefix_j), 'trace.jsonl': digest(prefix_t)},
                   'new': {'journal.jsonl': digest(all_j), 'trace.jsonl': digest(all_t)}}
    replace_bytes(out / 'publishing.json', (json.dumps(transaction, indent=2) + '\n').encode())
    recover_publication(root, out, total)
    subprocess.run([str(root / '_build/default/bin/m32.exe'), 'check', str(out)], check=True)
    print('m34 campaign complete:', total, 'samples', flush=True)


def main():
    require(len(sys.argv) == 1, 'usage: m34_campaign.py')
    root = Path(__file__).resolve().parent
    out = root / '_emit/m34/out/campaign1'
    require(out.is_dir(), 'create the initial campaign journal with m31 run first')
    with (out / 'parallel.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finish(root, out, 5000)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, IndexError, subprocess.CalledProcessError) as error:
        print('m34 campaign failure:', error, file=sys.stderr)
        sys.exit(1)
