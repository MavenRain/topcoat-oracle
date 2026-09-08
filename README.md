# topcoat-oracle

Differential conformance oracle for the Rust-expression-to-JS compiler
inside [Topcoat](https://github.com/tokio-rs/topcoat) (the `expr!`
macro plus browser runtime in `crates/topcoat-runtime`).

Three legs per generated expression: rustc-native, topcoat-emitted JS
under Node, and an OCaml reference interpreter. The pipeline journals every
attempt; a separate minimization step writes repros for unexcused divergences.
The first campaign retains 5,000 attempts, 803 completed comparisons and
103 minimized divergence repros. Losses remain visible in the
[campaign report](research/campaign-1/report.md).

- Design and milestone plan: [DESIGN.md](DESIGN.md)
- Pipeline model (CTLK, checked by ctlk_topos): `model/`
- Pinned study notes on the target: `research/`
- Known differences: [KNOWN.md](KNOWN.md)
- Revision comparison and adoption: [REPIN.md](REPIN.md)

## Prerequisites

Run commands from this repository root. Keep a clean Topcoat checkout at
`../topcoat`, pinned to `51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a`.
Generated Rust crates use fixed relative dependency paths. The `--clone`
flag selects JS sources and provenance; it does not relocate Rust dependencies.

The quickstart needs:

- An opam switch named `anvil-ocaml` with OCaml 5.3, Dune 3.13 or newer,
  `ctlk_topos`, `qcheck`, `alcotest` and `qcheck-alcotest`. The model checker
  links the separately installed `ctlk_topos` library; it is not vendored here.
- Rustup with `nightly-2026-06-22`, selected explicitly by the Rust leg.
- Node with `--experimental-transform-types` support (validated with
  v23.10.0), npm, Git and the driver dependencies installed below.
- zsh and ordinary Unix command-line tools. The complete gate ladder also
  needs Python 3.11 or newer, `rg`, `sd`, `fd`, `zxlint` and `gateledger` on PATH.

Install the pinned Rust toolchain and JS dependencies once if needed:

```sh
rustup toolchain install nightly-2026-06-22
npm --prefix driver-js ci
```

Dependency installation and the first Cargo build can need network access.
The M36 revision comparison runs Cargo offline, so populate its dependency
cache before running the complete ladder. Each gate selects `anvil-ocaml`
explicitly and refuses a missing switch.

## Quickstart

This runs 100 mixed samples through the three legs, replays their summary,
and checks the journal against its model trace. Every invocation creates a
fresh directory at the four-level depth required by the generated crates.

<!-- m37-quickstart:start -->
```sh
opam exec --switch=anvil-ocaml -- dune build bin/m31.exe bin/m32.exe
mkdir -p _emit/m37/out
TCO_SMOKE_DIR=$(mktemp -d _emit/m37/out/smoke.XXXXXX)
opam exec --switch=anvil-ocaml -- dune exec bin/m31.exe -- run "$TCO_SMOKE_DIR" \
  --samples 100 --seed 0x4d3336 --batch 100 --root . --clone ../topcoat \
  > "$TCO_SMOKE_DIR/run.txt"
cat "$TCO_SMOKE_DIR/run.txt"
opam exec --switch=anvil-ocaml -- dune exec bin/m31.exe -- replay "$TCO_SMOKE_DIR" \
  > "$TCO_SMOKE_DIR/replay.txt"
cmp "$TCO_SMOKE_DIR/run.txt" "$TCO_SMOKE_DIR/replay.txt"
opam exec --switch=anvil-ocaml -- dune exec bin/m32.exe -- check "$TCO_SMOKE_DIR" \
  > "$TCO_SMOKE_DIR/check.txt"
cat "$TCO_SMOKE_DIR/check.txt"
printf 'Quickstart artifacts: %s\n' "$TCO_SMOKE_DIR"
```
<!-- m37-quickstart:end -->

The summary must name seed `0x4d3336`, 100 samples and plant `none`; the
model check must report 100 lines. `cmp` succeeds silently. A divergence is
a measured result, and a `leg_fail` is a lost comparison. Neither makes the
pipeline exit nonzero by itself. The quickstart gate requires at least 10
completed comparisons, both sample modes, matching headers and contiguous
indices, so a run consisting entirely of losses cannot pass. Before M39, the
measured census was 9 agreements and 6 divergences. Counts also depend on the
Node version, so the gate retains its comparison floor and checks the census against
the whole M32 correspondence line instead, which reads the journal alone.

`./m37_gate.sh` executes this exact documented block and checks those
conditions. It re-invokes the completed run, which short-circuits to the
summary and runs no leg, and requires the journal and the trace to stay
byte-identical. It then truncates a copy of the evidence to 50 samples and
resumes THAT copy: the resumed legs must rebuild the untruncated bytes. It
also replays a second copy at another path, where the journal path is the
only permitted difference, because a run and a replay of the same directory
print the same bytes by construction. It retains the outputs under
`_emit/m37/`. Use the printed directory to inspect `journal.jsonl`,
`trace.jsonl` and the per-batch leg logs.

## Run the gates

    ./gates.sh

The ladder builds and tests the OCaml code, checks the CTLK model and ZxCaml
subset, then runs the milestone gates through M39. M34 and M35 replay the
checked campaign and repro archives; M36 and M37 earn fresh observations.
Allow time for Rust compilation, Node workers and deliberate timeout cases.
M39 checks signal identity through the actual browser runtime. Successful
completion ends with `GATES GREEN`.

## Coverage report

    dune exec bin/coverage.exe -- --samples 10000 --scope default

Prints what a drawn batch covers: the constructor tally with the
required body names and the required init shapes that stayed
unreached, the mode counters, the environment coverage, the
target-type and expression-size histograms, and one line per dropped
sample. Flags:

    --samples N     batch size (default 10000)
    --seed S        decimal or 0x hex (default 0x4d3138)
    --mode M        mixed, read-only or signal-writing
    --scope S       default, m20 or m18
    --strict        exit 1 on a drop, an unreached required body
                    name, an unreached required init shape or a
                    reached excluded name
    --json          one JSON line instead of the text report

Scope m18 redraws the M18 generator stream and takes --mode mixed
only. Its constructor block is byte-identical to the block
test_gen.exe prints, which m22_gate.sh checks. A drop is any sample
the pipeline did not keep, for any reason; only kept samples feed a
histogram, and the drop lines have no cap.

## Rust leg

    ./m23_gate.sh

Builds two crates under _emit/ from shell/driver.ml, copies
driver-rs/harness.rs in as src/harness.rs, and runs them. The seed
crate is a fixed twelve-case vector whose JSONL value channel is
compared byte for byte with the table in m23_verdict.sh, with js_hex
and debug_hex masked first: both carry a fresh Signal uuid per run. The
JS channel is checked by one decoded substring per case. The seed's
last case spins, so exit 3 is the expected code. The same crate carries
the harness unit tests, which the gate runs with cargo test. The drawn
crate is 300 samples at scope m20, seed 0x4d3233, and must exit 0 with
one line per kept case; a drawn case that spins costs one exit 3, and
the gate resumes at the next index up to 20 times. Both JSONL captures
stay under _emit/m23/out/, which is gitignored.

Driver flags: --from I, --to J, --timeout-ms N (default 2000, and 0 or
a value that does not fit u64 is a usage error). Exit 0 all cases done,
1 an IO error, 2 usage, 3 a case timed out, 4 the closure call site
lost the direct body on at least one case. Exit 4 is folded over the
range, so an inconsistent case still writes its line and every later
case still runs; every value line carries js_consistent, so a resumed
run cannot lose the verdict between segments.

    ./m24_gate.sh

Runs the same seed vector through the OCaml leg rather than through a
shell script: bin/m24.exe writes the crate under _emit/m24seed, spawns
cargo with the pinned toolchain, resumes the run past the case that
spins, decodes the JSONL with core/json.ml and core/wire.ml, and prints
one row per case. m24_verdict.sh compares the twelve rows byte for byte
with a hand-derived table, with the trailing js byte count masked
because js_hex carries a fresh Signal uuid per run; check 5 pins that
count non-zero on every row but the no-terminate one, which must carry
zero. The run summary on stderr pins the exit codes 3 then 0 over one
resume. The table, the CLI stderr and the JSONL stay under
_emit/m24/out/, which is gitignored.

## JS leg

    npm --prefix driver-js ci
    ./m25_gate.sh

The install is a one-time prerequisite and needs network access;  the
gate names it when @maverick-js/signals is missing.  The gate runs the
driver-js unit tests, then replays the JSONL that the rust leg just
wrote through node, and compares the result with a hand-derived table.

driver-js/driver.mjs evaluates the JS half of every wire line under the
target's own browser surrogates, loaded in place from the topcoat clone
by node's type transform plus a resolve hook.  It writes one JSONL line
per case: a value with its wire-form value, its rendered text and the
final state of every signal, a panic with its class and message, a
js_error for any other throw, a skipped line when the wire carries no
JS, or a driver_error naming what could not be decoded.  Run it by hand
with:

    node --experimental-transform-types --import ./driver-js/loader.mjs \
      driver-js/driver.mjs --in <jsonl> --out <jsonl>

Flags: --clone <dir> (default ../topcoat), --timeout-ms N (default
2000, and 0 or a non-integer is a usage error), --startup-timeout-ms N
(default 30000, same rules), --from I, --to J.  Exit 0 every selected
line produced a line, 1 an IO error or an input line that is not JSON,
2 usage.  There is no exit 3: a case that does not terminate is
terminated by the parent, gets a no_terminate line, and the run
continues in a fresh worker.

The two budgets are separate.  Each case gets a fresh worker, and that
worker must transform the clone TypeScript before it can run anything,
which costs about 320 ms on an idle machine and several seconds on a
loaded one.  The worker reports ready when its modules are loaded, and
--timeout-ms starts only then, so the cold start is never charged to
the case.  --startup-timeout-ms bounds the cold start alone;  its
expiry writes a driver_error line that names worker_startup, never a
no_terminate line.

## Three legs

    ./m26_gate.sh

Replays the JSONL both earlier legs wrote and prints three
observations per seed case: R for the rust leg, J for the js leg, F
for the reference interpreter, each in the canonical Obs encoding.
The rust capture is an input, so m24_gate.sh and m25_gate.sh are
prerequisites and the gate names either one when its output is
missing.  The js leg spawns the node driver over the same input file
the js gate used and compares the result with the js gate's own
expectation, which proves the spawn ran the real driver.  The
reference leg runs core/interp.ml and adds the rendered channel the
interpreter leaves out: Rust Display with no html escaping.

    ./_build/default/bin/m26.exe seeds _emit/m24/out/seed.jsonl \
      _emit/m26/out --clone ../topcoat --root .

Flags: --clone <dir> (default ../topcoat) and --root <dir> (default
M26_ROOT, else two levels above the out-dir).  Exit 0 when all three
legs produced twelve observations and the js driver exited 0, 1 on any
named error, 2 usage.  The table, the CLI stderr and the js JSONL stay
under _emit/m26/out/, which is gitignored.

The three cells disagree on five of the twelve cases, and every
disagreement is an output of the pipeline rather than a defect in it.
M27 adjudicates them.

## Verdicts

    ./m27_gate.sh

Adjudicates the three observations of each seed case and prints a
fourth line, V, carrying the sample mode and the verdict.  The three
leg lines are the ones m26 prints, byte for byte, and the gate checks
that too, so a verdict can never rewrite what a leg said.
m24_gate.sh, m25_gate.sh and m26_gate.sh are prerequisites and the
gate names the one whose output is missing.

    ./_build/default/bin/m27.exe seeds _emit/m24/out/seed.jsonl \
      _emit/m27/out --clone ../topcoat --root .

Six channels are compared in a fixed order: outcome, class, message,
value, rendered and signals.  A channel is compared only when every
party has one, so a kind mismatch is reported once, on outcome.
Signals compare by id, so their order is not a conformance surface.  A
read-only sample has three parties.  A signal-writing sample has two,
the js leg and the reference, because the server panics on every
signal write by design.

Verdicts are printed as agree, diverge:<channel>:<split> where a split
is odd:<leg>, all or two_way, known:<tag>, or leg_fail:<leg>:<reason>.
A known verdict names a divergence the pipeline already explains, and
it never hides a later unexcused one.

Flags: --clone <dir> (default ../topcoat) and --root <dir> (default
M27_ROOT, else two levels above the out-dir).  Exit 0 when all three
legs produced twelve observations and the js driver exited 0, 1 on any
named error and 2 on a usage error.  A diverge or a leg_fail verdict is
a result, not an error, so it does not move the exit code.

## Planted oracle

The gate proves the differ finds a bug it has never seen.  One binary,
three runs, one flag:

    dune exec bin/m27.exe -- seeds _emit/m24/out/seed.jsonl _emit/m28/out/ref \
      --clone ../topcoat --root . --plant ref:display_sign
    dune exec bin/m27.exe -- seeds _emit/m24/out/seed.jsonl _emit/m28/out/js \
      --clone ../topcoat --root . --plant js:signal_get_plus_one
    dune exec bin/m27.exe -- seeds _emit/m24/out/seed.jsonl _emit/m28/out/none \
      --clone ../topcoat --root .

The runs need the m24 capture, the topcoat clone beside this repo and
node v23.10 or later, the same prerequisites the m27 gate names.

The first run plants the reference leg: it renders every float with the
sign flipped, so cases 0, 3 and 6 print `diverge:rendered:odd:ref`.
The second plants the js leg: a signal read returns one more than the
stored number, so case 6 prints `diverge:value:odd:js` while its
signals cell holds.  The third plants nothing and prints the m27 table
byte for byte.

A planted run writes one extra stderr line, `plant: ref:display_sign`
or `plant: js:signal_get_plus_one`, immediately before the summary
line.  A run with no `--plant` writes no such line.

The exit codes do not move: a divergence is a result and never an
error, so all three runs exit 0.  An unknown plant name, such as
`--plant ref:nope`, is a usage error and exits 2.

`m28_gate.sh` runs all three and `m28_verdict.sh` adjudicates them.

## Minimizer

`bin/m29.exe` shrinks a diverging sample to a small one that diverges the
same way.

    dune exec bin/m29.exe -- minimize <dir> --plant <plant> \
        [--clone <dir>] [--root <dir>] [--fuel <n>]

Here `<plant>` is `ref:display_sign` or `js:signal_get_plus_one`.

One round asks the M19 shrinker for every candidate of the body at its
target type, adds one candidate per binding the body never mentions, runs
the whole batch through the three legs in one pass, and moves to the first
candidate whose verdict is the same divergence: the same channel and the
same odd leg.  A candidate that agrees, that hits a known difference, that
makes a leg fail or that produced no line at all is refused, so the loop
stays on one bug.

The loop stops when no candidate of a round preserves the divergence.  That
is a fixpoint, and it is what the gate requires;  the `--fuel` bound is a
second stop and never an error.  A round that gets NO verdict back at all,
because a leg failed or the crate writer dropped the whole batch, is a third
stop: `m29 stop: stuck <reason>`.  A stuck run is red, with the reason
named, because a small sample produced by blind legs proves nothing.

The last line of a run is a control: the minimized sample run once more with
no plant, which must agree.  Print the walk to see the size fall round by
round:

    round 0 size 13 cands 9 accepted 2
    round 1 size 8 cands 6 accepted 1
    ...
    m29 body: v3.get()
    m29 signal v3: f64 = 2.5
    m29 stop: fixpoint rounds 6 candidates 25
    m29 control: agree

`./m29_gate.sh` runs both plants and compares each walk with a table derived
by hand from the shrinker's rules.

## Repro files

`bin/m30.exe` turns one finished walk into one shareable file.

    dune exec bin/m30.exe -- repro _emit/m30/out/<plant> --plant <plant> \
        [--clone <dir>] [--root <dir>] [--fuel <n>]

It prints the same walk m29 prints, runs the final sample once more to earn
a witness, and writes `<dir>/repro.md`: the provenance with both repository
shas, the minimized program, the emitted JS, the two sizes, the four witness
cells, the walk trace and the two commands that reproduce it.  A witness that
does not preserve the divergence writes no file and exits 1.

Pass the directory RELATIVE to the root, as above, for a shareable repro:  the
directory is printed into the file exactly as it arrives, so an absolute path
on the command line would put a local path in a file meant for someone else.

`./m30_gate.sh` writes both repro files and compares them with hand derived
goldens, masking the oracle sha and the per crate signal id.

## Pipeline

The short command names below refer to the built executables. For example,
invoke `m31` as `opam exec --switch=anvil-ocaml -- dune exec bin/m31.exe --`
and `m32` as `opam exec --switch=anvil-ocaml -- dune exec bin/m32.exe --`.
They are not installed commands.

`m31 run <dir> --samples N --seed S` draws N samples from one seed and runs
them through the three legs in batches, appending one JSON line per sample to
`<dir>/journal.jsonl`.  The line carries the index, the mode, the size, the
verdict, the three observation cells and the Rust program.  Running the same
command again on the same directory continues the run;  a header that
disagrees with the flags is refused instead of appended to.

`m31 replay <dir>` prints the summary of a journal and runs nothing.  The
summary is computed from the decoded journal, so a run and a replay of the
same directory print the same bytes.

`<dir>` must sit four directories below the repository root, as
`_emit/m31/out/<name>` does, because the generated crates resolve their
dependencies by a fixed relative path (see DESIGN.md, the M29 entry).

## Correspondence

A run writes a second file beside the journal.  `<dir>/trace.jsonl` holds one
header line and one line per sample.  A sample line is
`{"i":N,"steps":["shape_ok","print_ok","compile_ok","exec_rust_ok","exec_js_ok","exec_ref_ok","judge_agree"]}`.
The step names are the transition names of the CTLK model in `model/frame.ml`.

`m32 check <dir>` reads the journal and the trace together and checks both
directions.  It prints one report line, `m32 check <dir>: 500 lines,
dropped_agree 77, dropped_known 0, minimizing_hi 10, gen_bug 0, leg_failed 413,
oracle_bug 0`, and exits 0.  It exits 1 on the first line that does not
correspond and names the line and the check on stderr.  It exits 2 on a usage
error or a missing file.

The step list of a sample is decided by its row kind and by its three cells.
A position the crate writer refused, and a batch that lost its leg before the
crate ran, walk shape, print and a compile failure into `gen_bug`.  A batch
that lost a leg after the crate ran, and a kept position with no rust line,
crash both product legs and walk `judge_infra` into `leg_failed`, which is the
one end stage the checker allows either of them, because the reference leg of
such a row always answers.  A kept and paired position reads all three legs
off their cells and takes the judge step its verdict head asks for.

Two findings are recorded here rather than fixed.  First, the differ names the
first missing party in the order rust, js, reference, and the model sends a
crashed reference to `oracle_bug` before it reads the other legs;  the checker
only requires the leg the verdict names to have crashed, and accepts the
model's choice of terminal.  Second, a signal writing sample's rust cell is not
a party for the differ, so such a sample can agree with a missing rust cell,
and the model has no `judge_agree` edge from a world whose rust leg crashed.
The checker rejects such a row.  No run of the gate produces one today.

## Known divergences

`KNOWN.md` is the allowlist review document.  It is rendered from
`core/known.ml` by `m33 render`, and `m33_gate.sh` compares the file with the
render byte for byte.  Edit the entries, not the document.

An entry excuses one channel of one row.  The walk reports the first unexcused
channel, so an entry can never hide a later difference.  Each entry names a
head, upstream or harness, and one citation: a path, a line range and a quote
that `m33 cite` requires to be inside that range.

The channel and the splits a row renders are load-bearing.  `Known.allow ()`
fences every closure with them, so a predicate broadened past the rendered
fields stops firing instead of excusing rows the document does not describe.

The document also lists what is NOT excused: the documented differences no
corpus row reaches yet, each naming its own head, and the four leg failure
classes, which are losses and not divergences.

## Campaign report

The first 5,000-sample campaign and its complete loss census are recorded in
[the campaign report](research/campaign-1/report.md). The compressed journal
and model trace beside it retain every observation and sample identity.

Run a new campaign from the repository root:

    opam exec --switch=anvil-ocaml -- dune build bin/m31.exe bin/m34.exe bin/m34_plants.exe bin/m34_slice.exe
    opam exec --switch=anvil-ocaml -- dune exec bin/m31.exe -- run _emit/m34/out/campaign1 --samples 5000 --seed 0x4d3334
    opam exec --switch=anvil-ocaml -- dune exec bin/m34.exe -- report _emit/m34/out/campaign1
    opam exec --switch=anvil-ocaml -- dune exec bin/m34_plants.exe -- _emit/m34/out/campaign1 _emit/m34/out/plants

The run resumes an existing matching journal. Reporting starts no product
leg: it checks the trace and regenerates the seed to verify every recorded
program. Its default minimum is 5,000; `--minimum N` permits smaller reports
for investigation and keeps the actual sample count visible. Both modes and
at least one completed comparison are required.

To finish an interrupted campaign at a complete 100-sample batch boundary,
run `python3 m34_campaign.py` after the serial process has stopped. It runs
three isolated batches at a time, retains completed slices for resume, and
validates all indices, seeded programs and model transitions before joining
the result. A source or executable change refuses cached slices. A retained
publication marker allows the next invocation to finish an interrupted
journal/trace replacement. `NODE_COMPILE_CACHE` may point to a local cache
directory to reuse Node's TypeScript transforms without changing timeouts.

Construct signature v1 has separate sorted constructor-count maps for target,
body, input types and initializers, and signal types and initializers. It
ignores literal values and variable ids. The grouping key also includes mode
and the full divergence verdict. All member indices are retained, so grouping
cannot discard a divergence that M35 should reproduce. Constructor coverage
counts attempts, including losses; it does not claim those constructors ran.

The two additional corpus plants change addition and string length in the
reference interpreter. Each selected sample must agree in a fresh control,
then diverge when its operation is changed. Addition is observed in the final
signals of a writing sample; string length is observed in the value of a
read-only sample, with the reference as the odd leg.

`./m34_gate.sh` replays the archived campaign and checks its report and
corruption controls. Its source fingerprints bind the archived results to
the original producer bytes retained in `research/archive-v1/sources.json.gz`.
The snapshot is verified as data and never executed. Live report reconstruction
and corruption controls still run. It is an evidence replay gate;
the four commands above perform the live campaign and plant checks.

## Campaign repro stream

M35 keeps one repro for every unexcused campaign divergence, including
separate files for members of the same construct group. `repros/campaign-1/`
contains the Markdown programs, raw Rust and JS witnesses, recorded greedy
walks and a manifest that binds the exact mapping to source fingerprints.

To check the archive, run `./m35_gate.sh`. The gate reconstructs each AST
from the campaign seed, replays its recorded shrink decisions, recomputes
the reference witness and verdict, and compares the complete repro text.
Missing, duplicate or extra identities, corrupted retained sources, incomplete
walks and corrupted witnesses fail the gate. Each recorded answer must name
a verdict class, and each walk must carry the oracle sha the manifest pins.
This replays archived evidence; it does not execute the Rust or JS product
legs.

For a campaign whose producer fingerprints match the current tree, the live
minimization commands are:

```sh
mkdir -p _emit/m35/out
python3 m34_verdict.py prepare . _emit/m34/check
opam exec --switch=anvil-ocaml -- dune build bin/m35.exe
python3 m35_verdict.py run .
```

The shipped campaign-1 archive predates M39. Its historical checks pass using
retained source bytes, but the live `run` and `publish` commands still refuse
changed producers. Using the current driver for this workflow requires fresh
campaign and repro evidence; historical observations are not relabeled.

For one sample, use `_build/default/bin/m35.exe emit
_emit/m34/check/archive 34 . ../topcoat`. Outputs go under
`_emit/m35/out/<index>/`. The stream pools up to 100 candidates per crate
while retaining each case's candidate order, then earns a fresh unplanted
witness for every final sample. Both the original and final measurements
must preserve the original divergence channel and split. Fuel exhaustion
and blind rounds cannot produce a successful repro.

A fixpoint is relative to the shipped shrink rules. The archived walks used
the original driver, which could reject a body that stopped using a declared
signal. M39 removes that restriction from fresh runs; compiler and other leg
failures can still exclude candidates. These files record differences
between the legs for triage; they do not establish which implementation is
wrong or constitute filed upstream reports.

`python3 m35_verdict.py publish .` replays all live outputs, then replays the
staged copy it fingerprints, and atomically publishes a new
`repros/campaign-1/` directory. The manifest pins the oracle sha that
publication read from git. Publication requires the
completed-run receipt written by `run`, with unchanged producer sources
and executable. It refuses to overwrite an existing archive.

## Re-pin comparison

[REPIN.md](REPIN.md) documents the revision comparison and adoption process.
From the repository root, check the current SHA against a fresh local copy:

```sh
opam exec --switch=anvil-ocaml -- dune build bin/m31.exe bin/m32.exe m36/probe.exe
python3 m36_repin.py --clone ../topcoat --to HEAD --out _emit/m36/same-sha --dry-run
```

The command reruns all three legs on identical programs and probes all five
signal writers. It retains checked journals, traces, observations and a
verdict diff. A repeated command verifies the completed evidence and returns
the same report. To test another locally available revision, omit
`--dry-run`, set `--to` and choose a fresh output directory. The maintained
checkout and archived evidence stay at their recorded revisions until the
candidate is reviewed and adopted.

## Status

The v1 milestone plan and the M39 signal identity follow-up are complete.
The CTLK pipeline model
includes negative-control expectations (see DESIGN.md section 4).

The gate ladder runs m20 through m37 and m39. M34 archives the first 5,000-sample
campaign; M35 adds a checked minimized repro stream for its unexcused
divergences; M36 compares target revisions with a checked same-SHA dry-run
and a planted negative control.
M37 executes the documented quickstart and checks replay and resume; M38
records the full ladder result in [VALIDATION.md](VALIDATION.md).

M39 binds each declared signal to the UUID in its own Rust Debug record.
Unused declarations retain their initial values, repeated references alias
the same signal, and reference order cannot swap identities. Malformed or
duplicate identities fail with named driver errors. This depends on the
pinned Topcoat Debug envelope; a changed envelope fails closed on re-pin.
The loader supports symlinked checkouts and paths containing spaces.

A fresh 500-sample validation at seed `0x4d3331` completed 449 comparisons,
up from 87 in the retained run of the same programs. No previously completed
comparison became a loss. The [measurement record](research/m39-signal-identity.json)
contains the journal digests and two corrected signal-identity witnesses.

The current limits are material: 4,197 of the first campaign's 5,000 attempts
lost their comparison, including 3,946 JS signal-arity failures. That historical
census remains unchanged. Fresh M39 runs bind signals by identity and retain
all declared signals. Shrink fixpoints remain relative to the available
candidates. Async/network semantics and
full DOM rendering remain outside v1. Repros support triage and require
review before attributing a defect to a particular implementation.

## License

MIT OR Apache-2.0.
