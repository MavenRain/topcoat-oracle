"""Exercise gate switch preambles with fake tools and no real builds."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = (
    'gates.sh', 'm20_dune.sh', 'm20_r2.sh', 'm20_gate.sh',
    *(f'm{number}_gate.sh' for number in range(22, 38)),
    'm39_gate.sh',
)

FAKE_OPAM = r'''
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with Path(os.environ['GATE_OPAM_CALLS']).open('a') as stream:
    stream.write(json.dumps(args) + '\n')
mode = os.environ['GATE_TEST_MODE']
if args == ['switch', 'list', '--short']:
    if mode == 'missing':
        print('ambient-switch\nanvil-ocaml-extra')
    else:
        print('ambient-switch\nanvil-ocaml')
elif args == ['env', '--switch=anvil-ocaml', '--set-switch']:
    if mode == 'env_failure':
        print('printf evaluated > "$GATE_EVAL_MARKER"')
        print('injected opam env failure', file=sys.stderr)
        sys.exit(19)
    print('export OPAMSWITCH=anvil-ocaml')
else:
    print('unexpected opam arguments: ' + repr(args), file=sys.stderr)
    sys.exit(23)
'''

FAKE_DUNE = r'''
import json
import os
from pathlib import Path
import sys

Path(os.environ['GATE_BUILD_CALL']).write_text(json.dumps({
    'argv': sys.argv[1:],
    'switch': os.environ.get('OPAMSWITCH'),
}))
'''


def preamble(path):
    """Stop immediately after the real source's first environment eval."""
    lines = path.read_text().splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.startswith('eval '):
            return ''.join(lines[:index + 1]) + '\ndune build\n'
    raise ValueError(f'{path.name} has no environment eval')


class GateSwitchTests(unittest.TestCase):
    def run_preamble(self, script, mode):
        with tempfile.TemporaryDirectory(prefix='gate-switch-') as temporary:
            directory = Path(temporary)
            tools = directory / 'tools'
            tools.mkdir()
            for name, source in (('opam', FAKE_OPAM), ('dune', FAKE_DUNE)):
                executable = tools / name
                executable.write_text(f'#!{sys.executable}\n' + source)
                executable.chmod(0o755)
            harness = directory / script
            harness.write_text(preamble(ROOT / script))
            calls = directory / 'opam.jsonl'
            build = directory / 'build.json'
            marker = directory / 'evaluated'
            environment = dict(os.environ)
            environment.update({
                'PATH': str(tools) + os.pathsep + environment.get('PATH', ''),
                'OPAMSWITCH': 'ambient-switch',
                'GATE_TEST_MODE': mode,
                'GATE_OPAM_CALLS': str(calls),
                'GATE_BUILD_CALL': str(build),
                'GATE_EVAL_MARKER': str(marker),
            })
            result = subprocess.run(
                [shutil.which('zsh') or '/bin/zsh', '-f', str(harness)],
                cwd=directory, env=environment, capture_output=True, text=True,
                timeout=10,
            )
            invoked = [json.loads(line) for line in calls.read_text().splitlines()]
            built = json.loads(build.read_text()) if build.exists() else None
            return result, invoked, built, marker.exists()

    def test_missing_switch_aborts_before_env_or_build(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result, invoked, built, evaluated = self.run_preamble(script, 'missing')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('opam switch anvil-ocaml is not installed',
                              result.stdout + result.stderr)
                self.assertEqual(invoked, [['switch', 'list', '--short']])
                self.assertIsNone(built)
                self.assertFalse(evaluated)

    def test_env_failure_aborts_without_evaluating_partial_output(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result, invoked, built, evaluated = self.run_preamble(script, 'env_failure')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('injected opam env failure', result.stderr)
                self.assertEqual(invoked, [
                    ['switch', 'list', '--short'],
                    ['env', '--switch=anvil-ocaml', '--set-switch'],
                ])
                self.assertIsNone(built)
                self.assertFalse(evaluated)

    def test_valid_switch_replaces_ambient_environment_before_build(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result, invoked, built, evaluated = self.run_preamble(script, 'valid')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(invoked, [
                    ['switch', 'list', '--short'],
                    ['env', '--switch=anvil-ocaml', '--set-switch'],
                ])
                self.assertEqual(built, {'argv': ['build'], 'switch': 'anvil-ocaml'})
                self.assertFalse(evaluated)


if __name__ == '__main__':
    unittest.main(verbosity=2)
