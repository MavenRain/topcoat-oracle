# topcoat-oracle

Differential conformance oracle for the Rust-expression-to-JS compiler
inside [Topcoat](https://github.com/tokio-rs/topcoat) (the `expr!`
macro plus browser runtime in `crates/topcoat-runtime`).

Three legs per generated expression: rustc-native, topcoat-emitted JS
under node, and an OCaml reference interpreter. Divergences shrink to
minimized repros under `repros/`.

- Design and milestone plan: [DESIGN.md](DESIGN.md)
- Pipeline model (CTLK, checked by ctlk_topos): `model/`
- Pinned study notes on the target: `research/`

## Run the gates

    ./gates.sh

Requires the karamel-710 opam switch with ctlk_topos, qcheck and
alcotest installed, plus node and cargo on PATH.

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

    node --experimental-transform-types --import driver-js/loader.mjs \
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

## Status

Phase D in progress. The CTLK pipeline model is green, including the
negative-control expectations (see DESIGN.md section 4).

## License

MIT OR Apache-2.0.
