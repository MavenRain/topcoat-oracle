#!/usr/bin/env python3
"""Exercise M36 with local Git commits and fake leg/check/probe executables."""

import contextlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import m36_repin as repin


MOCK = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
config = json.loads((root / 'mock.json').read_text())
kind = Path(sys.argv[0]).name
with (root / 'events.txt').open('a') as stream:
    stream.write(kind + '\n')
if config.get('failure') == kind:
    print('injected subprocess failure', file=sys.stderr)
    sys.exit(9)
if kind == 'm32.exe':
    print('mock correspondence check')
    sys.exit(0)
if kind == 'probe.exe':
    out = Path(sys.argv[3])
    assert out.is_dir()
    (out / 'raw.txt').write_text('fresh five-writer evidence\n')
    if config.get('fault') == 'probe_report':
        print('PROBE FAILED: 3 of 5 signal writers wrong')
        sys.exit(0)
    for name in ('set', 'toggle', 'increment', 'decrement', 'push_str'):
        print(name + ' R=Psignal_write:69:server-side|r0:| J=Vu|r0:| F=Vu|r0:| agree')
    print('m36 signal writers 5 verified')
    sys.exit(0)

args = dict(zip(sys.argv[3::2], sys.argv[4::2]))
out, oracle, clone = Path(sys.argv[2]), Path(args['--root']), Path(args['--clone'])
assert os.environ['CARGO_NET_OFFLINE'] == 'true'
assert (oracle / '_emit/m36/out/run/b0/../../../../../../topcoat').resolve() == clone
assert (oracle / 'driver-js/node_modules/@maverick-js/signals/index.js').is_file()
assert (oracle / 'research/probes-rs/exprmac/target').is_symlink()
side = oracle.parent.name
plant = args.get('--plant', 'none')
assert side == 'candidate' or plant == 'none'
sha = subprocess.check_output(['git', '-C', str(clone), 'rev-parse', 'HEAD'], text=True).strip()
header = dict(m31=1, seed=int(args['--seed']), batch=int(args['--batch']), plant=plant, topcoat=sha)
fault = config.get('fault') if side == 'candidate' else None
if fault == 'wrong_sha':
    header['topcoat'] = '0' * 40
if fault == 'planted':
    header['plant'] = 'ref:add_sign'
count = int(args['--samples']) - (fault == 'truncated')
rows = [dict(i=i, mode='read_only' if i % 2 == 0 else 'signal_writing', size=1,
             verdict='agree', r='ok:1', j='ok:1', f='ok:1', env=['let x = 1.0;'], body='x')
        for i in range(count)]
if fault == 'verdict':
    rows[1]['verdict'] = 'diverge:value:odd:rust'
if fault == 'observation':
    rows[1]['r'] = 'ok:2'
if fault in ('identity_body', 'identity_mode', 'identity_size', 'identity_env'):
    key = fault.removeprefix('identity_')
    rows[1][key] = {'body': 'x + 0.0', 'mode': 'read_only', 'size': 2, 'env': []}[key]
if config.get('fault') == 'loss_reason':
    rows[0]['verdict'] = 'batch_fail:' + side
if config.get('fault') == 'loss_transition':
    rows[0]['verdict'] = 'batch_fail:missing' if side == 'candidate' else 'agree'
    rows[1]['verdict'] = 'batch_fail:missing' if side == 'baseline' else 'agree'
if fault == 'all_losses':
    for row in rows:
        row['verdict'] = 'batch_fail:compiler unavailable'
if fault == 'bad_index':
    rows[-1]['i'] += 1
if fault == 'extra_key':
    rows[1]['extra'] = 'unexpected'
if fault == 'unknown_head':
    rows[1]['verdict'] = 'novel:thing'
if plant != 'none':
    rows[2]['verdict'] = 'diverge:rendered:odd:ref'
    rows[2]['f'] = 'ok:-1'
trace_header = {('m32' if key == 'm31' else key): value for key, value in header.items()}
traces = [dict(i=row['i'], steps=['ok']) for row in rows]
if fault == 'short_trace':
    traces.pop()
if fault == 'bad_trace_index':
    traces[-1]['i'] += 1
out.mkdir()
for name, records in [('journal.jsonl', [header] + rows), ('trace.jsonl', [trace_header] + traces)]:
    data = ''.join(json.dumps(row, separators=(',', ':')) + '\n' for row in records)
    if fault == 'missing_newline' and name == 'journal.jsonl':
        data = data.rstrip('\n')
    (out / name).write_text(data)
if fault == 'source_changed':
    (root / 'core/interp.ml').write_text('changed during run')
if fault == 'binary_changed':
    with (root / '_build/default/bin/m32.exe').open('a') as stream:
        stream.write('\n# changed during run\n')
if fault == 'clone_changed':
    (clone / 'Cargo.toml').write_text('changed during run')
if fault == 'snapshot_changed':
    with (oracle / 'driver-js/node_modules/@maverick-js/signals/index.js').open('a') as stream:
        stream.write('# changed inside the snapshot\n')
print('mock completed', count)
'''


def git(directory, *args):
    return subprocess.check_output(['git', '-C', str(directory), *args], stderr=subprocess.DEVNULL).decode().strip()


@contextlib.contextmanager
def fixture(fault=None, failure=None):
    with tempfile.TemporaryDirectory(prefix='m36-test-') as temporary:
        base = Path(temporary)
        root, clone, out = base / 'oracle', base / 'topcoat', base / 'evidence'
        root.mkdir()
        clone.mkdir()
        git(clone, 'init', '--quiet', '--initial-branch=main')
        git(clone, 'config', 'user.name', 'M36 Test')
        git(clone, 'config', 'user.email', 'm36@example.invalid')
        for name in repin.TOPCOAT_FILES:
            path = clone / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture commit one\n')
        git(clone, 'add', '.')
        git(clone, 'commit', '--quiet', '-m', 'fixture one')
        candidate = git(clone, 'rev-parse', 'HEAD')
        (clone / 'Cargo.toml').write_text('fixture commit two\n')
        git(clone, 'commit', '--quiet', '-am', 'fixture two')
        before = git(clone, 'rev-parse', 'HEAD')
        names = ('bin/m31.ml', 'bin/m32.ml', 'm36/probe.ml', 'm36_repin.py',
                 'core/interp.ml', 'core/dune', 'shell/dune', 'model/dune', 'bin/dune',
                 'm36/dune', 'dune-project', 'driver-rs/harness.rs',
                 'driver-js/package.json', 'driver-js/package-lock.json', 'driver-js/loader.mjs',
                 'driver-js/node_modules/@maverick-js/signals/index.js')
        for name in names:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('producer-v1\n')
        for name in repin.BINARIES:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(MOCK)
            path.chmod(0o755)
        (root / 'mock.json').write_text(json.dumps({'fault': fault, 'failure': failure}))
        yield root, clone, candidate, out
        assert git(clone, 'rev-parse', 'HEAD') == before


def execute(root, clone, candidate, out, **kwargs):
    return repin.run(root, clone, candidate, out, samples=4, seed=42, batch=2, **kwargs)


class RepinTests(unittest.TestCase):
    def test_changed_verdict_planted_control_and_pin_proposal(self):
        with fixture('verdict') as args:
            root, clone, candidate, out = args
            report = execute(*args).decode()
            self.assertIn('changed_verdicts 1 changed_observations 0', report)
            self.assertIn('signal_writer_probes baseline verified 5 candidate verified 5', report)
            diff = json.loads((out / 'diff.json').read_text())
            self.assertEqual(diff['changed_verdicts'],
                             [{'i': 1, 'baseline': 'agree', 'candidate': 'diverge:value:odd:rust'}])
            self.assertEqual((out / 'candidate-pin.txt').read_text(), candidate + '\n')
            self.assertEqual(git(clone, 'status', '--porcelain=v1'), '')
            receipt = json.loads((out / 'receipt.json').read_text())
            self.assertIn('driver-js/node_modules/@maverick-js/signals/index.js',
                          receipt['request']['implementation'])
            commands = json.loads((out / 'commands.json').read_text())
            self.assertEqual(sum(c['label'].endswith('-check') for c in commands), 2)
            self.assertEqual(sum(c['label'].endswith('-probe') for c in commands), 2)

        with fixture() as (root, clone, candidate, out):
            report = execute(root, clone, candidate, out,
                             candidate_plant='ref:display_sign').decode()
            self.assertIn('baseline_plant none candidate_plant ref:display_sign', report)
            self.assertIn('changed_verdicts 1 changed_observations 1', report)
            commands = json.loads((out / 'commands.json').read_text())
            self.assertEqual([c['label'] for c in commands if '--plant' in c['argv']],
                             ['candidate-run'])
        with fixture() as args:
            with self.assertRaisesRegex(ValueError, 'unplanted candidate side'):
                execute(*args, dry_run=True, candidate_plant='ref:display_sign')
        with fixture() as args:
            with self.assertRaisesRegex(ValueError, 'candidate plant must be none'):
                execute(*args, candidate_plant='ref:display sign')

    def test_identical_dry_run_and_completed_output_reuse(self):
        with fixture() as (root, clone, _, out):
            first = execute(root, clone, 'HEAD', out, dry_run=True)
            events = (root / 'events.txt').read_bytes()
            receipt = (out / 'receipt.json').read_bytes()
            second = execute(root, clone, git(clone, 'rev-parse', 'HEAD'), out, dry_run=True)
            self.assertEqual(first, second)
            self.assertEqual((root / 'events.txt').read_bytes(), events)
            self.assertEqual((out / 'receipt.json').read_bytes(), receipt)
            self.assertIn(b'changed_verdicts 0 changed_observations 0', first)

    def test_same_sha_requires_identical_verdict_and_observation(self):
        for fault in ('verdict', 'observation'):
            with self.subTest(fault=fault), fixture(fault) as (root, clone, _, out):
                with self.assertRaisesRegex(ValueError, 'same-SHA dry-run changed'):
                    execute(root, clone, 'HEAD', out, dry_run=True)
                self.assertTrue((out / 'diff.json').is_file())
                self.assertFalse((out / 'receipt.json').exists())

    def test_loss_reasons_and_comparison_transitions(self):
        with fixture('loss_reason') as args:
            execute(*args)
            delta = json.loads((args[3] / 'diff.json').read_text())
            self.assertEqual(delta['changed_verdicts'],
                             [{'i': 0, 'baseline': 'batch_fail:baseline', 'candidate': 'batch_fail:candidate'}])
        with fixture('loss_transition') as args:
            execute(*args)
            delta = json.loads((args[3] / 'diff.json').read_text())
            self.assertEqual(delta['lost_comparisons'], 1)
            self.assertEqual(delta['gained_comparisons'], 1)

    def test_identity_and_incomplete_evidence_refused(self):
        faults = {'identity_body': 'identity mismatch', 'identity_env': 'identity mismatch',
                  'identity_size': 'identity mismatch', 'identity_mode': 'identity mismatch',
                  'truncated': 'sample count mismatch', 'wrong_sha': 'SHA mismatch',
                  'planted': 'plant or Topcoat SHA mismatch',
                  'bad_index': 'journal index mismatch at index',
                  'bad_trace_index': 'trace count or index mismatch',
                  'extra_key': 'journal row schema mismatch at index',
                  'unknown_head': 'unknown verdict head',
                  'snapshot_changed': 'snapshot producer sources changed',
                  'all_losses': 'all samples were lost', 'short_trace': 'trace count',
                  'missing_newline': 'truncated'}
        for fault, reason in faults.items():
            with self.subTest(fault=fault), fixture(fault) as args:
                with self.assertRaisesRegex(ValueError, reason):
                    execute(*args)
                self.assertFalse((args[3] / 'receipt.json').exists())
        with fixture('loss_reason') as args:
            with self.assertRaisesRegex(ValueError, '3 adjudicated rows, minimum 4'):
                execute(*args, min_compared=4)
            self.assertFalse((args[3] / 'receipt.json').exists())
        with fixture() as args:
            with self.assertRaisesRegex(ValueError, 'floor must be between 1 and the sample count'):
                execute(*args, min_compared=5)
            self.assertFalse(args[3].exists())

    def test_subprocess_failures_retain_logs_and_refuse_resume(self):
        for binary in ('m31.exe', 'm32.exe', 'probe.exe'):
            with self.subTest(binary=binary), fixture(failure=binary) as args:
                with self.assertRaisesRegex(ValueError, 'failed with exit 9'):
                    execute(*args)
                self.assertFalse((args[3] / 'receipt.json').exists())
                logs = [path.read_text() for path in (args[3] / 'logs').glob('*.stderr')]
                self.assertTrue(any('injected subprocess failure' in text for text in logs))
                with self.assertRaisesRegex(ValueError, 'without a completion receipt'):
                    execute(*args)
        with fixture('probe_report') as args:
            with self.assertRaisesRegex(ValueError, 'signal writer probe printed 1 lines'):
                execute(*args)
            self.assertFalse((args[3] / 'receipt.json').exists())
            self.assertIn('PROBE FAILED',
                          (args[3] / 'logs/baseline-probe.stdout').read_text())

    def test_completed_evidence_and_producer_tamper_refused(self):
        names = ('baseline/oracle/_emit/m36/out/run/journal.jsonl',
                 'candidate/oracle/_emit/m36/out/run/trace.jsonl', 'report.txt',
                 'logs/baseline-probe.stdout')
        for name in names:
            with self.subTest(name=name), fixture() as args:
                execute(*args)
                with (args[3] / name).open('a') as stream:
                    stream.write('changed\n')
                with self.assertRaisesRegex(ValueError, 'artifact digest mismatch'):
                    execute(*args)
        for name in ('_build/default/bin/m31.exe', 'driver-js/node_modules/@maverick-js/signals/index.js'):
            with self.subTest(name=name), fixture() as args:
                execute(*args)
                with (args[0] / name).open('a') as stream:
                    stream.write('\n# changed\n')
                with self.assertRaisesRegex(ValueError, 'implementation changed'):
                    execute(*args)
        # A retained clone can move to another commit with the same tree, which
        # leaves every artifact digest intact. The reuse path rechecks the SHA.
        with fixture() as args:
            execute(*args)
            git(args[3] / 'candidate/topcoat', '-c', 'user.name=M36 Test',
                '-c', 'user.email=m36@example.invalid', 'commit', '--quiet',
                '--amend', '--no-edit', '--allow-empty')
            with self.assertRaisesRegex(ValueError, 'Topcoat clone HEAD changed'):
                execute(*args)

    def test_request_changes_refused(self):
        with fixture() as (root, clone, candidate, out):
            execute(root, clone, candidate, out)
            for changes in ({'samples': 5}, {'seed': 43}, {'batch': 3}):
                with self.subTest(changes=changes):
                    options = dict(samples=4, seed=42, batch=2, dry_run=False)
                    options.update(changes)
                    with self.assertRaisesRegex(ValueError, 'request or implementation changed'):
                        repin.run(root, clone, candidate, out, **options)
            git(clone, 'checkout', '--quiet', '--detach', candidate)
            try:
                with self.assertRaisesRegex(ValueError, 'request or implementation changed'):
                    execute(root, clone, candidate, out)
            finally:
                git(clone, 'checkout', '--quiet', 'main')
        with fixture() as (root, clone, _, out):
            execute(root, clone, 'HEAD', out)
            with self.assertRaisesRegex(ValueError, 'request or implementation changed'):
                execute(root, clone, 'HEAD', out, dry_run=True)

    def test_changes_during_execution_refused(self):
        # Each fault names one refusal and the command the run stopped at. The
        # producer recheck inside execute() is what stops the run at the next
        # command; the post-loop recheck alone would refuse it later.
        expected = {'source_changed': ('producer sources or binaries changed during run',
                                       'candidate-run'),
                    'binary_changed': ('producer sources or binaries changed during run',
                                       'candidate-run'),
                    'clone_changed': ('Topcoat clone has tracked or untracked changes',
                                      'candidate-probe')}
        for fault, (reason, last) in expected.items():
            with self.subTest(fault=fault), fixture(fault) as args:
                with self.assertRaisesRegex(ValueError, reason):
                    execute(*args)
                self.assertFalse((args[3] / 'receipt.json').exists())
                commands = json.loads((args[3] / 'commands.json').read_text())
                self.assertEqual(commands[-1]['label'], last)

    def test_dirty_clone_and_invalid_revision_refused_before_output(self):
        for untracked in (False, True):
            with self.subTest(untracked=untracked), fixture() as args:
                path = args[1] / ('unknown-file' if untracked else 'Cargo.toml')
                path.write_text('local edits\n')
                with self.assertRaisesRegex(ValueError, 'tracked or untracked changes'):
                    execute(*args)
                self.assertFalse(args[3].exists())
        with fixture() as (root, clone, _, out):
            with self.assertRaisesRegex(ValueError, 'git rev-parse failed'):
                execute(root, clone, '--help', out)
            self.assertFalse(out.exists())
        with fixture() as args:
            with self.assertRaisesRegex(ValueError, 'requires the same resolved Topcoat SHA'):
                execute(*args, dry_run=True)
            self.assertFalse(args[3].exists())

    def test_duplicate_json_keys_and_missing_tree_refused(self):
        with self.assertRaisesRegex(ValueError, 'duplicate JSON field'):
            repin.decode(b'{"i":0,"i":1}')
        with fixture() as (root, clone, candidate, out):
            path = repin.TOPCOAT_FILES[-1]
            git(clone, 'rm', path)
            git(clone, 'commit', '--quiet', '-m', 'remove required tree entry')
            try:
                with self.assertRaisesRegex(ValueError, 'missing Topcoat tree entry'):
                    execute(root, clone, candidate, out)
                self.assertFalse(out.exists())
            finally:
                git(clone, 'reset', '--hard', 'HEAD~1')


if __name__ == '__main__':
    unittest.main(verbosity=2)
