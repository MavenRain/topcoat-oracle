"""Negative controls for quickstart evidence, documentation, replay and resume."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "m37_verdict", Path(__file__).resolve().parents[1] / "m37_verdict.py")
m37 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m37)


def jsonl(rows):
    return "".join(json.dumps(row) + "\n" for row in rows)


# The stub opam refuses any command that is not wrapped for the named switch,
# so a resume that drops the wrapper cannot pass.
STUB_OPAM = r'''
import os
import sys

argv = sys.argv[1:]
if argv[:3] != ['exec', '--switch=anvil-ocaml', '--']:
    print('unwrapped opam call: ' + repr(argv), file=sys.stderr)
    sys.exit(7)
with open(os.environ['GATE_OPAM_CALLS'], 'a') as stream:
    stream.write(argv[5] + '\n')
os.execv(argv[3], argv[3:])
'''

# The stub m31 answers the summary of the directory it is given and, on run,
# rebuilds the whole evidence from the fixture.  GATE_STUB_DRIFT makes only
# the truncated resume rebuild different bytes.
STUB_M31 = r'''
import os
from pathlib import Path
import sys

argv = sys.argv[1:]
mode, target = argv[0], argv[1]
fixture = Path(os.environ['GATE_STUB_FIXTURE'])
summary = (fixture / 'run.txt').read_text().replace('SMOKE', target)
if os.environ.get('GATE_STUB_STICKY') and Path(target).name.startswith('replay.'):
    # A replay that answers about the directory it was NOT given.
    summary = (fixture / 'run.txt').read_text().replace('SMOKE', 'elsewhere')
if mode == 'run':
    code = int(os.environ.get('GATE_STUB_EXIT', '0'))
    if code:
        print('injected run failure', file=sys.stderr)
        sys.exit(code)
    drift = os.environ.get('GATE_STUB_DRIFT', '')
    tail = drift.encode() if Path(target).name.startswith('partial.') else b''
    for name in ('journal.jsonl', 'trace.jsonl'):
        (Path(target) / name).write_bytes((fixture / name).read_bytes() + tail)
sys.stdout.write(summary)
'''

# The stub m32 counts the journal the way shell/correspond.ml maps heads to
# end stages.  Two environment variables plant a census that names a bug.
STUB_M32 = r'''
import json
import os
from pathlib import Path
import sys

target = sys.argv[2]
lines = (Path(target) / 'journal.jsonl').read_text().splitlines()[1:]
heads = [json.loads(line)['verdict'].split(':', 1)[0] for line in lines]
count = {head: heads.count(head) for head in ('agree', 'known', 'diverge', 'leg_fail')}
print('m32 check %s: %d lines, dropped_agree %d, dropped_known %d, '
      'minimizing_hi %d, gen_bug %s, leg_failed %d, oracle_bug %s'
      % (target, len(lines), count['agree'], count['known'],
         count['diverge'] - int(os.environ.get('GATE_STUB_LOSE_HI', '0')),
         os.environ.get('GATE_STUB_GEN_BUG', '0'), count['leg_fail'],
         os.environ.get('GATE_STUB_ORACLE_BUG', '0')))
'''

BLOCK = """mkdir -p _emit/m37/out
TCO_SMOKE_DIR=$(mktemp -d _emit/m37/out/smoke.XXXXXX)
cp fixture/journal.jsonl fixture/trace.jsonl "$TCO_SMOKE_DIR/"
_build/default/bin/m31.exe replay "$TCO_SMOKE_DIR" > "$TCO_SMOKE_DIR/run.txt"
cp "$TCO_SMOKE_DIR/run.txt" "$TCO_SMOKE_DIR/replay.txt"
_build/default/bin/m32.exe check "$TCO_SMOKE_DIR" > "$TCO_SMOKE_DIR/check.txt"
printf 'Quickstart artifacts: %s\\n' "$TCO_SMOKE_DIR"
"""


class QuickstartTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.directory = Path(scratch.name)
        self.header = dict(m31=1, seed=m37.SEED, batch=100, plant="none", topcoat=m37.PIN)
        self.rows = [dict(i=i, mode="read_only" if i % 2 else "signal_writing",
                          verdict="agree" if i < 9 else "diverge:value:odd:js" if i < 15
                          else "dropped:fixture") for i in range(100)]
        self.trace = [dict(i=i, steps=["fixture"]) for i in range(100)]
        for name in ("run.txt", "replay.txt", "resume.txt"):
            (self.directory / name).write_text("summary\n")
        self.write()

    def write(self):
        trace_head = {("m32" if key == "m31" else key): value
                      for key, value in self.header.items()}
        for name, rows in (("journal.jsonl", [self.header] + self.rows),
                           ("trace.jsonl", [trace_head] + self.trace)):
            (self.directory / name).write_text(jsonl([rows[0]] + rows[1:]))

    def test_floor_reports_the_census_and_rejects_losses(self):
        census = m37.validate(self.directory)
        self.assertEqual(m37.adjudicated(census), 15)
        self.assertEqual((census["agree"], census["known"], census["diverge"]), (9, 0, 6))
        for count in (m37.FLOOR - 1, 0):
            for i, row in enumerate(self.rows):
                row["verdict"] = "agree" if i < count else "batch_fail:fixture"
            self.write()
            with self.assertRaisesRegex(ValueError,
                                        f"adjudicated rows, minimum {m37.FLOOR}"):
                m37.validate(self.directory)

    def test_wrong_seed_pin_plant_batch_are_refused(self):
        for field, value in (("seed", m37.SEED + 1), ("topcoat", "0" * 40),
                             ("plant", "ref:display_sign"), ("batch", 50)):
            with self.subTest(field=field):
                previous, self.header[field] = self.header[field], value
                self.write()
                with self.assertRaisesRegex(ValueError, "header mismatch"):
                    m37.validate(self.directory)
                self.header[field] = previous

    def test_missing_and_reordered_identities_in_both_files(self):
        for rows in (self.rows, self.trace):
            last = rows.pop()
            self.write()
            with self.assertRaisesRegex(ValueError, "100 samples"):
                m37.validate(self.directory)
            rows.append(last)
            rows[0], rows[1] = rows[1], rows[0]
            self.write()
            with self.assertRaisesRegex(ValueError, "identities"):
                m37.validate(self.directory)
            rows[0], rows[1] = rows[1], rows[0]

    def test_resume_rejects_a_changed_trace_or_journal(self):
        before = {name: (self.directory / name).read_bytes() for name in m37.EVIDENCE}
        m37.verify_resume(self.directory, before, "completed resume")
        for label in ("completed resume", "truncated resume"):
            for name in m37.EVIDENCE:
                path = self.directory / name
                original = path.read_bytes()
                path.write_bytes(original + b"\n")
                with self.subTest(label=label, name=name), \
                        self.assertRaisesRegex(ValueError, f"{label} changed {name}"):
                    m37.verify_resume(self.directory, before, label)
                path.write_bytes(original)

    def test_truncated_keeps_the_header_and_the_named_rows(self):
        data = (self.directory / "journal.jsonl").read_bytes()
        kept = m37.truncated(data, 50)
        self.assertEqual(kept.count(b"\n"), 51)
        self.assertTrue(data.startswith(kept))
        with self.assertRaisesRegex(ValueError, "100 samples before truncation"):
            m37.truncated(kept, 50)

    def test_modes_and_replay(self):
        (self.directory / "replay.txt").write_text("changed\n")
        with self.assertRaisesRegex(ValueError, "replay differs"):
            m37.validate(self.directory)
        for row in self.rows:
            row["mode"] = "read_only"
        self.write()
        with self.assertRaisesRegex(ValueError, "both modes"):
            m37.validate(self.directory)

    def test_actual_block_and_malformed_documentation(self):
        valid = m37.START + "\n```sh\nprintf 'actual commands\\n'\n```\n" + m37.END
        self.assertEqual(m37.quickstart(valid), "printf 'actual commands\\n'\n")
        pair = "exactly one quickstart marker pair"
        block = "exactly one fenced sh block"
        for bad, message in (
                ("", pair),
                (valid + valid, pair),
                (valid.replace("```sh", "```bash"), block),
                (valid.replace("```\n", "```\n```sh\ntrue\n```\n"), block),
                (m37.END + "\n```sh\ntrue\n```\n" + m37.START, "markers are reversed"),
                (m37.START + "\n```sh\n\n```\n" + m37.END, "block is empty")):
            with self.subTest(document=bad), self.assertRaisesRegex(ValueError, message):
                m37.quickstart(bad)

    def test_typing_newline_and_verdict_head_guards(self):
        path = self.directory / "journal.jsonl"
        original = path.read_bytes()
        path.write_bytes(original.rstrip(b"\n"))
        with self.assertRaisesRegex(ValueError, "lacks final newline"):
            m37.validate(self.directory)
        path.write_bytes(original)
        self.header["m31"] = True
        self.write()
        with self.assertRaisesRegex(ValueError, "header mismatch"):
            m37.validate(self.directory)
        self.header["m31"] = 1
        self.rows[0]["i"] = True
        self.write()
        with self.assertRaisesRegex(ValueError, "identities"):
            m37.validate(self.directory)
        self.rows[0]["i"] = 0
        self.rows[0]["verdict"] = "surprise:new"
        self.write()
        with self.assertRaisesRegex(ValueError, "unknown verdict head"):
            m37.validate(self.directory)

    def test_correspondence_reads_the_whole_census(self):
        census = dict(agree=9, known=0, diverge=6, leg_fail=85, dropped=0,
                      no_line=0, batch_fail=0)
        line = ("m32 check out/smoke.x: 100 lines, dropped_agree 9, "
                "dropped_known 0, minimizing_hi 6, gen_bug 0, leg_failed 85, "
                "oracle_bug 0\n")
        m37.verify_correspondence(line, census, "out/smoke.x")
        for bad, message in (
                (line.replace("oracle_bug 0", "oracle_bug 2"), "oracle_bug 2"),
                (line.replace("gen_bug 0", "gen_bug 3"), "gen_bug 3"),
                (line.replace("minimizing_hi 6", "minimizing_hi 5"), "minimizing_hi rows"),
                (line.replace("dropped_agree 9", "dropped_agree 8"), "dropped_agree rows"),
                (line.replace("100 lines", "99 lines"), "does not report 100 lines")):
            with self.subTest(line=bad), self.assertRaisesRegex(ValueError, message):
                m37.verify_correspondence(bad, census, "out/smoke.x")

    def stub_root(self, block):
        """A temporary root whose README block writes fixture evidence, with
        stub legs and a stub opam under it."""
        scratch = tempfile.TemporaryDirectory(prefix="m37-root-")
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        (root / "fixture").mkdir()
        (root / "_build/default/bin").mkdir(parents=True)
        (root / "tools").mkdir()
        header = dict(m31=1, seed=m37.SEED, batch=100, plant="none", topcoat=m37.PIN)
        trace_head = {("m32" if key == "m31" else key): value
                      for key, value in header.items()}
        rows = [dict(i=i, mode="read_only" if i % 2 else "signal_writing",
                     verdict="agree" if i < 9 else "diverge:value:odd:js" if i < 15
                     else "leg_fail:js:fixture") for i in range(100)]
        (root / "fixture/journal.jsonl").write_text(jsonl([header] + rows))
        (root / "fixture/trace.jsonl").write_text(
            jsonl([trace_head] + [dict(i=i, steps=["fixture"]) for i in range(100)]))
        (root / "fixture/run.txt").write_text(
            "m31 seed 0x4d3336 samples 100 batch 100 plant none topcoat "
            + m37.PIN + "\nm31 journal SMOKE/journal.jsonl lines 100\n")
        for name, source in (("tools/opam", STUB_OPAM),
                             ("_build/default/bin/m31.exe", STUB_M31),
                             ("_build/default/bin/m32.exe", STUB_M32)):
            stub = root / name
            stub.write_text(f"#!{sys.executable}\n" + source)
            stub.chmod(0o755)
        (root / "README.md").write_text(
            m37.START + "\n```sh\n" + block + "```\n" + m37.END + "\n")
        return root

    def drive(self, root, **environment):
        """Run the whole gate over a stub root, with the stubs on PATH."""
        previous = dict(os.environ)
        os.environ.update({
            "PATH": str(root / "tools") + os.pathsep + os.environ.get("PATH", ""),
            "GATE_STUB_FIXTURE": str(root / "fixture"),
            "GATE_OPAM_CALLS": str(root / "opam.calls"),
            **environment,
        })
        try:
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                m37.run(root)
            return printed.getvalue()
        finally:
            os.environ.clear()
            os.environ.update(previous)

    def test_run_over_a_stub_root_passes_and_each_guard_bites(self):
        root = self.stub_root(BLOCK)
        printed = self.drive(root)
        self.assertIn("M37 GATE GREEN: 100 samples, 15 adjudicated", printed)
        # Both resumes went through the switch wrapper of the stub opam.
        resumed = (root / "opam.calls").read_text().splitlines()
        self.assertEqual(len(resumed), 2)
        self.assertTrue(Path(resumed[1]).name.startswith("partial."))
        artifacts = "printf 'Quickstart artifacts: %s\\n' \"$TCO_SMOKE_DIR\""
        checker = '_build/default/bin/m32.exe check "$TCO_SMOKE_DIR"'
        stale = self.stub_root(BLOCK.replace(
            "TCO_SMOKE_DIR=$(mktemp -d _emit/m37/out/smoke.XXXXXX)",
            'TCO_SMOKE_DIR=_emit/m37/out/smoke.stale\nmkdir -p "$TCO_SMOKE_DIR"'))
        (stale / "_emit/m37/out/smoke.stale").mkdir(parents=True)
        cases = (
            ("duplicate", self.stub_root(BLOCK + artifacts + "\n"), {},
             "exactly one artifact directory"),
            ("absolute", self.stub_root(BLOCK.replace(
                artifacts, artifacts.replace('"$TCO', '"$PWD/$TCO'))), {},
             "fresh smoke directory"),
            ("stale", stale, {}, "fresh smoke directory"),
            ("checker", self.stub_root(BLOCK.replace(
                checker, "printf 'm32 check %s: 100 lines, all clear\\n' \"$TCO_SMOKE_DIR\"")),
             {}, "documented checker output differs"),
            ("oracle_bug", self.stub_root(BLOCK), {"GATE_STUB_ORACLE_BUG": "1"},
             "oracle_bug 1"),
            ("gen_bug", self.stub_root(BLOCK), {"GATE_STUB_GEN_BUG": "1"}, "gen_bug 1"),
            ("census", self.stub_root(BLOCK), {"GATE_STUB_LOSE_HI": "1"},
             "minimizing_hi rows and the journal"),
            ("exit", self.stub_root(BLOCK), {"GATE_STUB_EXIT": "3"},
             r"resume failed \(3\)"),
            ("drift", self.stub_root(BLOCK), {"GATE_STUB_DRIFT": "x"},
             "truncated resume changed journal.jsonl"),
            ("relocated", self.stub_root(BLOCK), {"GATE_STUB_STICKY": "1"},
             "relocated replay differs"),
        )
        for name, bad, environment, message in cases:
            with self.subTest(case=name), self.assertRaisesRegex(ValueError, message):
                self.drive(bad, **environment)
