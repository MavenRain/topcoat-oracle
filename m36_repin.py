#!/usr/bin/env python3
"""Compare two local Topcoat commits without changing the caller's checkout."""

import argparse
from collections import Counter
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


BINARIES = ('_build/default/bin/m31.exe', '_build/default/bin/m32.exe',
            '_build/default/m36/probe.exe')
TOPCOAT_FILES = ('Cargo.toml', 'crates/topcoat-runtime/Cargo.toml',
                 'crates/topcoat-runtime/macro/Cargo.toml',
                 'crates/topcoat-view/Cargo.toml', 'crates/topcoat-core/Cargo.toml')
JOURNAL_KEYS = {'i', 'mode', 'size', 'verdict', 'r', 'j', 'f', 'env', 'body'}
IDENTITY_KEYS = ('i', 'mode', 'env', 'body', 'size')
OBSERVATION_KEYS = ('r', 'j', 'f')
PROBE_CASES = ('set', 'toggle', 'increment', 'decrement', 'push_str')
PROBE_SUMMARY = 'm36 signal writers 5 verified'
COMPARED = {'agree', 'known', 'diverge'}
LOSSES = {'leg_fail', 'dropped', 'no_line', 'batch_fail'}
DEFAULT_SEED = 0x4d3336


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON field: ' + key)
        result[key] = value
    return result


def decode(data):
    return json.loads(data, object_pairs_hook=unique_object)


def file_fingerprints(directory, skip=()):
    """Hash files and link text, without following links to shared build caches."""
    result = {}
    for path in sorted(directory.rglob('*')):
        name = path.relative_to(directory).as_posix()
        if any(part in skip for part in path.relative_to(directory).parts):
            continue
        if path.is_symlink():
            result[name] = {'symlink': os.readlink(path)}
        elif path.is_file():
            result[name] = {'sha256': digest(path.read_bytes())}
    return result


def implementation(root):
    """Keep M36's inventory separate from the frozen M34 and M35 inventories."""
    names = set(BINARIES)
    names.update(('bin/m31.ml', 'bin/m32.ml', 'm36_repin.py', 'dune-project',
                  'core/dune', 'shell/dune', 'model/dune', 'bin/dune', 'm36/dune'))
    for pattern in ('core/*.ml', 'shell/*.ml', 'model/*.ml', 'm36/*.ml',
                    'driver-rs/**/*.rs'):
        names.update(path.relative_to(root).as_posix() for path in root.glob(pattern)
                     if 'target' not in path.relative_to(root).parts)
    names.update('driver-js/' + name for name in file_fingerprints(root / 'driver-js'))
    for name in ('driver-rs/harness.rs', 'driver-js/package.json',
                 'driver-js/package-lock.json', 'driver-js/loader.mjs'):
        names.add(name)
    require((root / 'driver-js/node_modules').is_dir(),
            'driver-js/node_modules is missing; install the locked JS dependencies first')
    result = {}
    for name in sorted(names):
        path = root / name
        require(path.is_file(), 'missing producer or binary: ' + str(path))
        result[name] = digest(path.read_bytes())
    for name in BINARIES:
        require(os.access(root / name, os.X_OK), 'binary is not executable: ' + name)
    return result


def git(directory, *args):
    argv = ['git', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null',
            '-C', str(directory), *args]
    result = subprocess.run(argv, capture_output=True, check=False,
                            env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'})
    require(result.returncode == 0,
            'git ' + args[0] + ' failed: ' + result.stderr.decode(errors='replace').strip())
    return result.stdout


def revision(clone, name):
    sha = git(clone, 'rev-parse', '--verify', '--end-of-options', name + '^{commit}').decode().strip()
    require(re.fullmatch('[0-9a-f]{40}', sha) is not None, 'expected a full SHA-1 commit')
    return sha


def clean_clone(clone, expected=None):
    require(clone.is_dir(), 'clone does not exist: ' + str(clone))
    top = Path(git(clone, 'rev-parse', '--show-toplevel').decode().strip()).resolve()
    require(top == clone, '--clone must name the repository root')
    require(not git(clone, 'status', '--porcelain=v1', '--untracked-files=all',
                    '--ignore-submodules=none'), 'Topcoat clone has tracked or untracked changes: ' + str(clone))
    for name in TOPCOAT_FILES:
        require((clone / name).is_file(), 'missing Topcoat tree entry: ' + name)
    sha = revision(clone, 'HEAD')
    if expected is not None:
        require(sha == expected, 'Topcoat clone HEAD changed: ' + str(clone))
    return sha


def read_journal(directory, sha, samples, seed, batch, plant, min_compared):
    data = (directory / 'journal.jsonl').read_bytes()
    require(data.endswith(b'\n'), 'journal is truncated or lacks its final newline')
    rows = [decode(line) for line in data.splitlines()]
    expected = {'m31': 1, 'seed': seed, 'batch': batch, 'plant': plant, 'topcoat': sha}
    require(rows and rows[0] == expected and
            all(type(rows[0].get(key)) is int for key in ('m31', 'seed', 'batch')),
            'journal header, parameters, plant or Topcoat SHA mismatch')
    require(len(rows) == samples + 1, 'journal sample count mismatch or truncated run')
    for index, row in enumerate(rows[1:]):
        require(isinstance(row, dict) and set(row) == JOURNAL_KEYS,
                'journal row schema mismatch at index ' + str(index))
        require(type(row['i']) is int and row['i'] == index,
                'journal index mismatch at index ' + str(index))
        require(type(row['size']) is int and row['size'] >= 0,
                'invalid sample size at index ' + str(index))
        require(row['mode'] in ('read_only', 'signal_writing'), 'invalid sample mode')
        require(all(isinstance(row[key], str) for key in ('body', 'verdict', 'r', 'j', 'f')),
                'invalid journal text field')
        require(isinstance(row['env'], list) and all(isinstance(x, str) for x in row['env']),
                'invalid sample environment')
        require(row['verdict'].split(':', 1)[0] in COMPARED | LOSSES, 'unknown verdict head')
    # A side that adjudicates one row of a hundred carries no more evidence than
    # a side that adjudicates none, so the caller states the floor it needs.
    compared = sum(row['verdict'].split(':', 1)[0] in COMPARED for row in rows[1:])
    require(compared >= min_compared,
            'all samples were lost or too few comparisons: ' + str(compared)
            + ' adjudicated rows, minimum ' + str(min_compared))
    trace_data = (directory / 'trace.jsonl').read_bytes()
    require(trace_data.endswith(b'\n'), 'trace is truncated or lacks its final newline')
    trace = [decode(line) for line in trace_data.splitlines()]
    expected_trace = {('m32' if key == 'm31' else key): value for key, value in expected.items()}
    require(trace and trace[0] == expected_trace, 'trace header or Topcoat SHA mismatch')
    require(len(trace) == samples + 1 and
            all(isinstance(row, dict) and type(row.get('i')) is int and row['i'] == index
                for index, row in enumerate(trace[1:])), 'trace count or index mismatch')
    return rows[1:]


def compare(before, after):
    # read_journal pins each side to samples plus one row, so the two lists have
    # the same length by construction and zip below drops nothing.
    changed, observations = [], []
    lost, gained = 0, 0
    for index, (old, new) in enumerate(zip(before, after)):
        require(all(old[key] == new[key] for key in IDENTITY_KEYS),
                'sample identity mismatch at index ' + str(index))
        was_compared = old['verdict'].split(':', 1)[0] in COMPARED
        is_compared = new['verdict'].split(':', 1)[0] in COMPARED
        lost += was_compared and not is_compared
        gained += is_compared and not was_compared
        if old['verdict'] != new['verdict']:
            changed.append({'i': index, 'baseline': old['verdict'], 'candidate': new['verdict']})
        fields = {key: {'baseline': old[key], 'candidate': new[key]}
                  for key in OBSERVATION_KEYS if old[key] != new[key]}
        if fields:
            observations.append({'i': index, 'fields': fields})
    return {'changed_verdicts': changed, 'changed_observations': observations,
            'lost_comparisons': lost, 'gained_comparisons': gained,
            'baseline_census': dict(sorted(Counter(row['verdict'] for row in before).items())),
            'candidate_census': dict(sorted(Counter(row['verdict'] for row in after).items()))}


def report_text(request, delta, probes):
    lines = ['m36 baseline ' + request['baseline'], 'm36 candidate ' + request['candidate'],
             ('m36 samples {samples} seed {seed} batch {batch} baseline_plant none '
              'candidate_plant {candidate_plant}').format(**request),
             'm36 dry_run ' + str(request['dry_run']).lower(),
             'm36 changed_verdicts ' + str(len(delta['changed_verdicts'])) +
             ' changed_observations ' + str(len(delta['changed_observations'])) +
             ' lost_comparisons ' + str(delta['lost_comparisons']) +
             ' gained_comparisons ' + str(delta['gained_comparisons'])]
    for side in ('baseline', 'candidate'):
        for verdict, count in delta[side + '_census'].items():
            lines.append('m36 census ' + side + ' ' + json.dumps(verdict) + ' ' + str(count))
    for row in delta['changed_verdicts']:
        lines.append('m36 verdict ' + json.dumps(row, sort_keys=True))
    for row in delta['changed_observations']:
        lines.append('m36 observations ' + json.dumps(row, sort_keys=True))
    lines.extend(('m36 signal_writer_probes baseline ' + probes['baseline'] +
                  ' candidate ' + probes['candidate'],
                  'm36 proposed_pin ' + request['candidate'],
                  'm36 proposal only; adopt deliberately and renew shipped gates and archives separately',
                  'm36 caller_checkout unchanged'))
    return ('\n'.join(lines) + '\n').encode()


def snapshot(root, side, shared_target):
    oracle = side / 'oracle'
    oracle.mkdir()
    shutil.copytree(root / 'driver-js', oracle / 'driver-js')
    (oracle / 'driver-rs').mkdir()
    shutil.copy2(root / 'driver-rs/harness.rs', oracle / 'driver-rs/harness.rs')
    target = oracle / 'research/probes-rs/exprmac/target'
    target.parent.mkdir(parents=True)
    target.symlink_to(shared_target, target_is_directory=True)
    (oracle / '_emit/m36/out').mkdir(parents=True)
    # The frozen Rust producer appends six parents then "topcoat" from /run/b0.
    rust_clone = oracle / '_emit/m36/out/run/b0/../../../../../../topcoat'
    require(rust_clone.resolve() == (side / 'topcoat').resolve(),
            'snapshot layout does not select the intended Rust Topcoat clone')
    return oracle


def check_snapshot(oracle, fingerprints):
    expected = {name: sha for name, sha in fingerprints.items()
                if name.startswith('driver-js/') or name == 'driver-rs/harness.rs'}
    names = {'driver-js/' + name for name in file_fingerprints(oracle / 'driver-js')}
    names.add('driver-rs/harness.rs')
    actual = {name: digest((oracle / name).read_bytes()) for name in sorted(names)}
    require(actual == expected, 'snapshot producer sources changed or differ from the recorded implementation')


def probe_result(path):
    """Read what the probe printed, so the report states a measured result.

    m36/probe.ml prints one line per signal writer and then its summary line.
    It exits 1 on any rejection, but exit 0 alone is not evidence that the five
    writers were checked, so the log is read here and the report repeats it.
    """
    lines = path.read_text(errors='replace').splitlines()
    require(len(lines) == len(PROBE_CASES) + 1,
            'signal writer probe printed ' + str(len(lines)) +
            ' lines; expected one per writer and one summary')
    for name, line in zip(PROBE_CASES, lines):
        require(line.startswith(name + ' '), 'signal writer probe did not report ' + name)
    require(lines[-1] == PROBE_SUMMARY,
            'signal writer probe summary is ' + json.dumps(lines[-1]) +
            ', expected ' + json.dumps(PROBE_SUMMARY))
    return 'verified ' + str(len(PROBE_CASES))


def artifacts(out):
    return {name: value for name, value in file_fingerprints(out, skip=('.git',)).items()
            if name not in ('receipt.json', 'receipt.pending')}


def run(root, clone, to, out, samples=100, seed=DEFAULT_SEED, batch=100, dry_run=False,
        candidate_plant='none', min_compared=1):
    root, clone, out = root.resolve(), clone.resolve(), out.resolve()
    require(type(samples) is int and samples >= 1 and type(batch) is int and batch >= 1,
            'samples and batch must be positive integers')
    require(type(min_compared) is int and 1 <= min_compared <= samples,
            'the adjudicated row floor must be between 1 and the sample count')
    require(type(seed) is int and 0 <= seed <= 999999999999999999,
            'seed must be nonnegative with at most 18 decimal digits')
    require(candidate_plant == 'none' or re.fullmatch('(ref|js):[a-z0-9_]+', candidate_plant),
            'candidate plant must be none or a leg plant name such as ref:display_sign')
    require(candidate_plant == 'none' or not dry_run,
            '--dry-run requires an unplanted candidate side')
    require(clone != out and clone not in out.parents, 'output must be outside the caller clone')
    baseline = clean_clone(clone)
    candidate = revision(clone, to)
    require(not dry_run or candidate == baseline, '--dry-run requires the same resolved Topcoat SHA as HEAD')
    fingerprints = implementation(root)
    request = {'format': 1, 'root': str(root), 'clone': str(clone), 'baseline': baseline,
               'candidate': candidate, 'samples': samples, 'seed': seed, 'batch': batch,
               'dry_run': dry_run, 'candidate_plant': candidate_plant,
               'min_compared': min_compared, 'implementation': fingerprints}
    if out.exists():
        require((out / 'receipt.json').is_file(), 'output exists without a completion receipt; use a new --out')
        receipt = decode((out / 'receipt.json').read_bytes())
        require(isinstance(receipt, dict) and receipt.get('request') == request,
                'completed output request or implementation changed')
        require(receipt.get('artifacts') == artifacts(out), 'completed output artifact digest mismatch')
        for side, sha in (('baseline', baseline), ('candidate', candidate)):
            clean_clone(out / side / 'topcoat', sha)
        return (out / 'report.txt').read_bytes()

    out.mkdir(parents=True)
    (out / 'logs').mkdir()
    (out / 'request.json').write_bytes(json_bytes(request))
    commands = []
    env = {**os.environ, 'CARGO_NET_OFFLINE': 'true', 'GIT_TERMINAL_PROMPT': '0',
           'RUSTUP_AUTO_INSTALL': '0'}

    def execute(label, argv):
        stdout_path, stderr_path = out / 'logs' / (label + '.stdout'), out / 'logs' / (label + '.stderr')
        commands.append({'label': label, 'argv': [str(value) for value in argv]})
        (out / 'commands.json').write_bytes(json_bytes(commands))
        with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
            result = subprocess.run(argv, cwd=root, env=env, stdout=stdout, stderr=stderr, check=False)
        require(result.returncode == 0,
                label + ' failed with exit ' + str(result.returncode) + '; see ' + str(stderr_path))
        require(implementation(root) == fingerprints, 'producer sources or binaries changed during run')

    shared_target = root / '_emit/m36/target'
    shared_target.mkdir(parents=True, exist_ok=True)
    lock_path = shared_target / '.m36.lock'
    with lock_path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        rows, probes = {}, {}
        # The plant is a run-time flag on the candidate leg run only. It gives the
        # gate a negative control: an unplanted baseline against a planted candidate.
        plants = {'baseline': 'none', 'candidate': candidate_plant}
        for side, sha in (('baseline', baseline), ('candidate', candidate)):
            directory = out / side
            directory.mkdir()
            isolated = directory / 'topcoat'
            execute(side + '-clone', ['git', '-c', 'core.hooksPath=/dev/null', 'clone',
                                     '--no-hardlinks', '--no-checkout', '--', str(clone), str(isolated)])
            execute(side + '-checkout', ['git', '-c', 'core.hooksPath=/dev/null', '-C', str(isolated),
                                        'checkout', '--detach', sha])
            clean_clone(isolated, sha)
            oracle = snapshot(root, directory, shared_target)
            check_snapshot(oracle, fingerprints)
            run_dir, probe_dir = oracle / '_emit/m36/out/run', oracle / '_emit/m36/out/probe'
            plant = plants[side]
            execute(side + '-run', [str(root / BINARIES[0]), 'run', str(run_dir), '--samples',
                                   str(samples), '--seed', str(seed), '--batch', str(batch),
                                   '--root', str(oracle), '--clone', str(isolated)]
                                   + ([] if plant == 'none' else ['--plant', plant]))
            execute(side + '-check', [str(root / BINARIES[1]), 'check', str(run_dir)])
            rows[side] = read_journal(run_dir, sha, samples, seed, batch, plant, min_compared)
            probe_dir.mkdir()
            execute(side + '-probe', [str(root / BINARIES[2]), str(oracle), str(isolated), str(probe_dir)])
            probes[side] = probe_result(out / 'logs' / (side + '-probe.stdout'))
            clean_clone(isolated, sha)
            check_snapshot(oracle, fingerprints)
        delta = compare(rows['baseline'], rows['candidate'])
        (out / 'diff.json').write_bytes(json_bytes(delta))
        if dry_run and baseline == candidate:
            require(not delta['changed_verdicts'] and not delta['changed_observations'],
                    'same-SHA dry-run changed verdicts or observations; inspect diff.json')
        clean_clone(clone, baseline)
        require(implementation(root) == fingerprints, 'producer sources or binaries changed during run')
        report = report_text(request, delta, probes)
        (out / 'report.txt').write_bytes(report)
        (out / 'candidate-pin.txt').write_text(candidate + '\n')
        receipt = {'request': request, 'artifacts': artifacts(out)}
        clean_clone(clone, baseline)
        for side, sha in (('baseline', baseline), ('candidate', candidate)):
            clean_clone(out / side / 'topcoat', sha)
            check_snapshot(out / side / 'oracle', fingerprints)
        require(implementation(root) == fingerprints, 'producer sources or binaries changed during run')
        pending = out / 'receipt.pending'
        with pending.open('xb') as stream:
            stream.write(json_bytes(receipt))
            stream.flush()
            os.fsync(stream.fileno())
        pending.replace(out / 'receipt.json')
        return report


def number(text):
    try:
        return int(text, 0) if text.lower().startswith(('0x', '0o', '0b')) else int(text)
    except ValueError as error:
        raise argparse.ArgumentTypeError('expected an integer') from error


def main(argv=None):
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__, epilog=(
        'Both modes execute fresh runs and all five signal writer probes in isolated local '
        'clones. Both sides are unplanted unless --plant-candidate names a plant, which the '
        'candidate leg run alone receives as a negative control. Each side must adjudicate '
        'at least --min-compared samples. '
        '--dry-run requires the same resolved SHA as HEAD and identical verdicts and observations. '
        'Normal mode writes a candidate pin proposal for deliberate adoption; it does not '
        'change the caller checkout, shipped gates, or archived evidence. No Git fetch or Cargo '
        'network access is performed. A matching completed --out verifies retained artifacts and '
        'prints the original report without re-executing; incomplete output is refused.'))
    parser.add_argument('--clone', type=Path, default=root.parent / 'topcoat')
    parser.add_argument('--to', required=True, help='local commit or revision to propose')
    parser.add_argument('--out', required=True, type=Path, help='new evidence directory')
    parser.add_argument('--samples', type=number, default=100)
    parser.add_argument('--seed', type=number, default=DEFAULT_SEED)
    parser.add_argument('--batch', type=number, default=100)
    parser.add_argument('--min-compared', type=number, default=1,
                        help='refuse a side with fewer adjudicated rows than this floor')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--plant-candidate', default='none',
                        help='plant a known bug in the candidate leg run only, as a negative control')
    args = parser.parse_args(argv)
    sys.stdout.buffer.write(run(root, args.clone, args.to, args.out, args.samples,
                                args.seed, args.batch, args.dry_run, args.plant_candidate,
                                args.min_compared))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, TypeError, UnicodeError, subprocess.SubprocessError) as error:
        print('m36 repin failure: ' + str(error), file=sys.stderr)
        sys.exit(1)
