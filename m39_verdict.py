#!/usr/bin/env python3
"""Exercise signal identity through the real Node driver and pinned runtime."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

RECORD = Path(__file__).resolve().parent / 'research/m39-signal-identity.json'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def f64(value):
    hi, lo = struct.unpack('>II', struct.pack('>d', value))
    return {'t': 'f64', 'hi': hi, 'lo': lo}


def signal(identity, value):
    uuid = f'00000000-0000-4000-8000-{identity:012x}'
    debug = f'Signal {{ id: SignalId({uuid}), value: fixture }}'
    return {'id': identity, 'value': value, 'debug_hex': debug.encode().hex()}, uuid


def hydrate(uuid):
    return 'cx.hydrate(' + json.dumps({'t': 'Signal', 'id': uuid},
                                    separators=(',', ':')) + ')'


def fixtures():
    a, ua = signal(3, f64(2.5))
    b, ub = signal(7, f64(7.0))
    c, uc = signal(9, {'t': 'bool', 'v': True})
    all_signals = [a, b, c]
    a_js, b_js, c_js = (hydrate(uuid) for uuid in (ua, ub, uc))
    rows, expected = [], []

    def add(name, js, signals, value=None, rendered='', final=None,
            form='direct', error=None, detail=None, outcome='value',
            js_name=None, js_msg=None):
        index = len(rows)
        rows.append({'case': index, 'outcome': 'value', 'value': {'t': 'unit'},
                     'rendered_hex': '', 'js_consistent': True,
                     'js_hex': js.encode().hex(), 'js_form': form,
                     'hint': 'none', 'signals': signals})
        want = {'case': index, 'outcome': outcome}
        if outcome == 'value':
            want.update(value=value, rendered_hex=rendered.encode().hex())
        if error is not None:
            # The refusal name alone accepts any diagnostic, so pin its bytes.
            want.update(error=error, detail_hex=detail.encode().hex())
        if js_name is not None:
            # A JavaScript refusal carries no error name, so pin both halves
            # of its diagnostic; the outcome alone accepts any thrown value.
            want.update(name_hex=js_name.encode().hex(),
                        msg_hex=js_msg.encode().hex())
        if outcome in ('value', 'js_error'):
            want.update(js_form=form, hint='none')
            want['signals'] = final if final is not None else [
                {'id': s['id'], 'value': s['value']} for s in signals]
        expected.append((name, want))

    add('all declarations unused', 'cx.hydrate(1.5)', all_signals, f64(1.5), '1.5')
    add('only second declaration used', b_js + '.get()', all_signals, f64(7.0), '7')
    add('reverse reference order', b_js + '.get().sub(' + a_js + '.get())',
        [a, b], f64(4.5), '4.5')
    add('repeated reference aliases one signal', a_js + '.get().sub(' + a_js + '.get())',
        [a], f64(0.0), '0')
    add('reverse writes preserve wire identities',
        '() => {' + b_js + '.set(cx.hydrate(11));' + a_js +
        '.set(cx.hydrate(4)); return cx.hydrate(null);}', all_signals,
        {'t': 'unit'}, '',
        [{'id': 3, 'value': f64(4.0)}, {'id': 7, 'value': f64(11.0)},
         {'id': 9, 'value': c['value']}], form='closure')
    add('mixed types and writes',
        '() => {' + c_js + '.toggle();' + a_js + '.increment(); return ' + c_js + '.get();}',
        [a, c], {'t': 'bool', 'v': False}, 'false',
        [{'id': 3, 'value': f64(3.5)}, {'id': 9, 'value': {'t': 'bool', 'v': False}}],
        form='closure')
    decoy = '{"t":"Signal","id":"00000000-0000-4000-8000-000000000099"}'
    # Raw double quotes inside this JS string matched the former source scan.
    add('signal-shaped literal is data', "cx.hydrate('" + decoy + "')",
        [], {'t': 'str', 'hex': decoy.encode().hex()}, decoy)
    add('malformed unused declaration fails closed', 'cx.hydrate(1.5)',
        [{**a, 'debug_hex': 'not a Signal'.encode().hex()}],
        error='signal_debug', detail='record 0', outcome='driver_error')
    add('duplicate UUID fails closed', 'cx.hydrate(1.5)',
        [a, {**b, 'debug_hex': a['debug_hex']}],
        error='signal_duplicate_uuid', detail=ua, outcome='driver_error')
    add('duplicate wire ID fails closed', 'cx.hydrate(1.5)',
        [a, {**b, 'id': a['id']}], error='signal_duplicate_id',
        detail=str(a['id']), outcome='driver_error')
    add('unknown hydration ID is not paired by position', hydrate(ub) + '.get()',
        [a], outcome='js_error', js_name='Error',
        js_msg='Unknown signal id: ' + ub)
    return rows, expected


def check(label, expected, rows):
    """Compare one clone path's rows; every message names that leg."""
    require(len(rows) == len(expected), label + ': driver omitted or repeated a fixture')
    for (name, want), got in zip(expected, rows):
        require(isinstance(got, dict), f'{label}: {name}: output is not an object')
        # A row that leaks an extra key, or drops one, is not this expectation.
        require(set(got) == set(want),
                f'{label}: {name}: keys: expected {sorted(want)}, got {sorted(got)}')
        for key, value in want.items():
            require(got.get(key) == value,
                    f'{label}: {name}: {key}: expected {value!r}, got {got!r}')


def run(root, clone):
    parent = root / '_emit/m39'
    parent.mkdir(parents=True, exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix='identity.', dir=parent))
    rows, expected = fixtures()
    source = out / 'rust.jsonl'
    source.write_text(''.join(json.dumps(row, separators=(',', ':')) + '\n' for row in rows))
    alias = out / 'clone with spaces'
    alias.symlink_to(clone.resolve(), target_is_directory=True)
    produced = {}
    for label, clone_path in [('physical', clone.resolve()), ('symlink', alias)]:
        target = out / (label + '.js.jsonl')
        argv = ['node', '--experimental-transform-types', '--import',
                str(root / 'driver-js/loader.mjs'), str(root / 'driver-js/driver.mjs'),
                '--in', str(source), '--out', str(target), '--clone', str(clone_path)]
        with (out / (label + '.stdout')).open('wb') as stdout, \
                (out / (label + '.stderr')).open('wb') as stderr:
            result = subprocess.run(argv, cwd=root, stdout=stdout, stderr=stderr)
        require(result.returncode == 0, f'{label}: driver exited {result.returncode}; see {out}')
        data = target.read_bytes()
        require(data.endswith(b'\n'), label + ': driver output lacks final newline')
        check(label, expected, [json.loads(line) for line in data.splitlines()])
        produced[label] = data
    require(produced['physical'] == produced['symlink'],
            f'physical and symlink clone paths disagree on the output bytes; see {out}')
    print(f'M39 GATE GREEN: {len(rows)} signal identity cases, physical and symlink clone paths; {out}')


def rows_of(expected):
    """The exact output a compliant driver would write for these fixtures."""
    return [dict(want) for _, want in expected]


class Fixtures(unittest.TestCase):
    """The expectations must cover every fixture and pin every diagnostic."""

    def setUp(self):
        self.rows, self.expected = fixtures()

    def test_eleven_cases_are_expected_in_wire_order(self):
        self.assertEqual(len(self.rows), 11)
        self.assertEqual(len(self.expected), 11)
        self.assertEqual([row['case'] for row in self.rows], list(range(11)))
        self.assertEqual([want['case'] for _, want in self.expected], list(range(11)))

    def test_every_refusal_pins_its_diagnostic_bytes(self):
        refusals = {want.get('error', want['outcome']): want
                    for _, want in self.expected if want['outcome'] != 'value'}
        self.assertEqual(refusals.keys(), {'signal_debug', 'signal_duplicate_uuid',
                                           'signal_duplicate_id', 'js_error'})
        self.assertEqual(refusals['signal_debug']['detail_hex'],
                         'record 0'.encode().hex())
        self.assertEqual(refusals['signal_duplicate_uuid']['detail_hex'],
                         '00000000-0000-4000-8000-000000000003'.encode().hex())
        self.assertEqual(refusals['signal_duplicate_id']['detail_hex'], '3'.encode().hex())
        self.assertEqual(refusals['js_error']['name_hex'], 'Error'.encode().hex())
        self.assertEqual(
            refusals['js_error']['msg_hex'],
            'Unknown signal id: 00000000-0000-4000-8000-000000000007'.encode().hex())

    def test_each_outcome_pins_its_whole_row_shape(self):
        shapes = {'value': {'case', 'outcome', 'value', 'rendered_hex', 'js_form',
                            'hint', 'signals'},
                  'driver_error': {'case', 'outcome', 'error', 'detail_hex'},
                  'js_error': {'case', 'outcome', 'name_hex', 'msg_hex', 'js_form',
                               'hint', 'signals'}}
        for name, want in self.expected:
            with self.subTest(case=name):
                self.assertEqual(set(want), shapes[want['outcome']])

    def test_measured_literals_are_pinned_outside_the_builder(self):
        by_case = {want['case']: want for _, want in self.expected}
        self.assertEqual(by_case[3]['value'],
                         {'t': 'f64', 'hi': 0, 'lo': 0})
        self.assertEqual(by_case[3]['rendered_hex'], '30')
        self.assertEqual(by_case[3]['signals'],
                         [{'id': 3, 'value': {'t': 'f64', 'hi': 1074003968, 'lo': 0}}])
        self.assertEqual(by_case[7]['error'], 'signal_debug')
        self.assertEqual(by_case[7]['detail_hex'], '7265636f72642030')


class Check(unittest.TestCase):
    """check() must reject a forged row, a lost row and a mislabelled leg."""

    def setUp(self):
        _, self.expected = fixtures()
        self.rows = rows_of(self.expected)

    def compare(self, label='physical'):
        check(label, self.expected, self.rows)

    def test_expected_rows_pass(self):
        self.compare()

    def test_a_dropped_or_repeated_row_is_rejected(self):
        for rows in [self.rows[:-1], self.rows + [dict(self.rows[-1])]]:
            with self.subTest(count=len(rows)):
                self.rows = rows
                with self.assertRaisesRegex(ValueError,
                                            'symlink: driver omitted or repeated a fixture'):
                    self.compare('symlink')

    def test_row_order_is_pinned(self):
        self.rows[0], self.rows[1] = self.rows[1], self.rows[0]
        with self.assertRaisesRegex(ValueError, 'physical: .*: case: expected 0'):
            self.compare()

    def test_a_wrong_refusal_name_is_rejected(self):
        index = next(i for i, row in enumerate(self.rows)
                     if row['outcome'] == 'driver_error')
        self.rows[index]['error'] = 'signal_debug_hex'
        with self.assertRaisesRegex(ValueError, 'physical: .*: error: expected'):
            self.compare()

    def test_a_forged_refusal_diagnostic_is_rejected(self):
        index = next(i for i, row in enumerate(self.rows)
                     if row.get('error') == 'signal_duplicate_uuid')
        self.rows[index]['detail_hex'] = 'wrong diagnostic'.encode().hex()
        with self.assertRaisesRegex(ValueError, 'physical: .*: detail_hex: expected'):
            self.compare()

    def test_a_leaked_extra_key_is_rejected(self):
        index = next(i for i, row in enumerate(self.rows)
                     if row['outcome'] == 'driver_error')
        self.rows[index]['signals'] = [{'id': 3, 'value': {'t': 'unit'}}]
        with self.assertRaisesRegex(ValueError, 'physical: .*: keys: expected'):
            self.compare()

    def test_an_omitted_key_is_rejected(self):
        del self.rows[0]['value']
        with self.assertRaisesRegex(ValueError, 'physical: .*: keys: expected'):
            self.compare()

    def test_a_wrong_value_is_rejected(self):
        self.rows[0]['value'] = {'t': 'unit'}
        with self.assertRaisesRegex(ValueError, 'physical: .*: value: expected'):
            self.compare()

    def test_a_row_that_is_not_an_object_is_rejected(self):
        self.rows[0] = [self.rows[0]]
        with self.assertRaisesRegex(ValueError, 'symlink: .*: output is not an object'):
            self.compare('symlink')


class Record(unittest.TestCase):
    """The published measurement record must add up to its own censuses."""

    def setUp(self):
        self.record = json.loads(RECORD.read_text(encoding='utf-8'))

    def test_the_loss_breakdown_sums_to_the_recorded_loss_total(self):
        losses = self.record['after_leg_fail_verdicts']
        self.assertEqual(sum(losses.values()), self.record['after']['leg_fail'])
        for verdict in losses:
            self.assertTrue(verdict.startswith('leg_fail:'), verdict)

    def test_the_recovered_signal_arity_rows_are_a_subset_of_the_losses(self):
        recovered = self.record['signal_arity_after_verdicts']
        self.assertEqual(sum(recovered.values()), self.record['previous_signal_arity'])
        losses = {name: count for name, count in recovered.items()
                  if name.startswith('leg_fail:')}
        self.assertEqual(self.record['signal_arity_now_adjudicated'],
                         self.record['previous_signal_arity'] - sum(losses.values()))
        for name, count in losses.items():
            self.assertLessEqual(count, self.record['after_leg_fail_verdicts'][name])


def selftest():
    """Drive fixtures() and check() directly, before any driver runs."""
    require(RECORD.exists(), 'the M39 measurement record is missing: ' + str(RECORD))
    loader = unittest.TestLoader()
    suite = unittest.TestSuite(loader.loadTestsFromTestCase(case)
                               for case in (Fixtures, Check, Record))
    result = unittest.TextTestRunner(verbosity=0).run(suite)
    require(not result.skipped, 'the M39 expectation tests were skipped')
    require(result.wasSuccessful(), 'the M39 expectations failed their own tests')
    print(f'M39 SELFTEST OK: {result.testsRun} expectation tests')


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['--selftest']:
            selftest()
        else:
            require(len(sys.argv) == 3,
                    'usage: m39_verdict.py ROOT CLONE, or m39_verdict.py --selftest')
            run(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
    except (ValueError, OSError) as error:
        print('M39 GATE RED: ' + str(error), file=sys.stderr)
        sys.exit(1)
