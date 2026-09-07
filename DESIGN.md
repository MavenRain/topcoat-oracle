# topcoat-oracle: design

A differential conformance oracle for the compiler hidden inside
[Topcoat](https://github.com/tokio-rs/topcoat): type-checked Rust
expressions cross-compiled to JavaScript with no WASM. The deliverable
is a stream of minimized bug repros against a framework announced
2026-07-22. The harness is the machine that produces them.

Pinned target: tokio-rs/topcoat @ `51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a`
(2026-08-25, workspace 0.6.2). Local clone: `~/Documents/topcoat`.
Research notes with file:line evidence live in `research/`.

## 1. What the target actually is

The `expr!` proc macro (`crates/topcoat-runtime/macro`) accepts one
Rust expression and emits two halves in lockstep
(`crates/topcoat-runtime/grammar/src/expr.rs`):

- a real Rust expression over `Surrogate` newtypes, evaluated
  server-side by rustc-compiled code;
- a JavaScript source STRING, built by text concatenation, evaluated
  in the browser via `new Function("cx", "return " + js)` against
  hand-written TypeScript mirror classes
  (`crates/topcoat-runtime/browser/src/surrogate/*.ts`).

There is no separate IL and no static check of the JS half. Rust/TS
parity is maintained by hand. That hand parity is the bug surface.

The expression vocabulary (v0.6.2): `f64`, `bool`, `String`/`&str`,
`Option`, `Result`, tuples, closures (sync and async), `Signal`
(get/set/toggle/increment/decrement/push_str). Binary `+ - * /` and
comparisons, unary not, negation, deref. `let` bindings (plain
idents), blocks, `if`/`else if`, `loop`/`while`/`break`/`continue`/
`return`, `Some`/`Ok`/`Err`/`None::<T>`, field and index access,
`.await`. There are NO integer literals (f64 is the only numeric
type), no `match`, no short-circuit logical operators, no bitwise
ops, no assignment operator.

Known risk classes (details in `research/study-topcoat.md`):
string `len` and indexing (Rust bytes vs JS UTF-16), panic mapping
(`unwrap`/`expect` vs a JS `Panic extends Error`, message text
differs), duck-typed `.clone()` falling back to reference aliasing,
f64 text rendering (Rust `Display` vs JS `toString`), NaN (identical
by IEEE, verify), signal write shorthands (server-side panic by
design), `.await` (network round-trip, no server analogue).

## 2. Three legs, two observation channels

For each generated expression:

1. rust leg: a driver crate invokes `expr!` on the expression, renders
   server-side, captures the native value AND extracts the emitted JS
   text between the `::topcoat::expr::start`/`end` comment markers.
2. js leg: a node driver imports the browser runtime surrogates,
   builds a stub `cx` Context, evaluates the JS text, captures the
   value or thrown Panic plus final signal states.
3. reference leg: the OCaml reference interpreter evaluates the AST
   under the intended Rust semantics.

Observations normalize to a common ADT with two channels:
bit-exact value (f64 as IEEE bit pattern, strings as bytes, structured
Option/Result/tuple) and rendered text (each side's own
display/toString path; formatting is itself a conformance surface).
Outcome is part of the observation: value, panic (with class), or
non-termination guard.

Expressions split into two taxonomies: read-only (three-way diff) and
signal-writing event handlers (two-way: js leg vs reference; the
server panics on those by design).

## 3. ZxCaml-maximal layout

Rule: every module that CAN live in the ZxCaml subset DOES, so it
compiles under both stock OCaml (dune) and `omlz` (native check), with
`zxlint` as a pre-gate. The subset has no floats, no exceptions, no
functors (facts: `research/study-zxcaml.md`), so:

- f64 values are carried as IEEE-754 bit patterns in the single 64-bit
  int type; the float operations arrive as an injected record of
  closures, implemented once in the full-OCaml shell via
  `Int64.bits_of_float`/`float_of_bits`.
- panics are values: the interpreter returns a result, never raises.
- strings are byte strings in both OCaml and the Rust semantics, which
  makes the byte-vs-UTF-16 divergence class directly expressible.

Layout:

    model/     CTLK pipeline model (plain OCaml + ctlk_topos)
    core/      dual-compiled ZxCaml-subset modules:
               prelude, ast, wf, obs, printer_rust, interp, differ
    shell/     full OCaml: floatops, gen (QCheck), legs, minimizer, CLI
    driver-rs/ generated-crate template for the rust leg
    driver-js/ node driver for the js leg
    repros/    minimized divergence repros (the product)
    research/  pinned study reports

## 4. Model-driven development (ctlk-topos)

The pipeline is modeled FIRST as an interpreted system
(`Ctlk.system_of`) in `model/`, and the implementation must stay a
refinement of it. State: pipeline stage x three leg outcomes x
verdict. Agents: the three legs (each observes only its own outcome)
and a triager (observes only the disposition). Properties (P1..P9 in
`model/props.ml`), each with an expected verdict against BOTH the
shipped design (Coupled) and a negative control (Uncoupled, which can
file a repro without a diverge verdict):

- P1 soundness: AG (filed implies diverged). Holds Coupled, fails
  Uncoupled.
- P2 no vacuous agreement: AG (agree-terminal implies all legs ran ok).
- P3 progress: AF terminal, from every reachable state.
- P4 epistemic soundness: AG (filed implies K_triager diverged). The
  triager sees only the disposition, so this holds exactly when the
  reachable space couples filing to divergence. Fails Uncoupled.
- P5 reference crash never files (it is our bug: Oracle_bug).
- P6 each leg knows its own crash (view adequacy).
- P7/P8 filing and agreement are reachable (satisfiability).
- P9 no common knowledge of divergence among the legs (documented
  non-property: legs never see the verdict).

R0 pin-drift guard: the repo's own reachable closure must equal the
kernel carrier, so a silent ctlk_topos pin drift fails the gate.
Status: MODEL GREEN including negative-control expectations
(31 coupled / 32 uncoupled worlds).

The correspondence gate (M32) closes the loop: real runs emit a
transition log; a checker asserts every logged step is an edge of
`model/frame.ml` and every terminal disposition is a model terminal.

## 5. Milestones

38 milestones, 5 phases. Each milestone has its own gate. A milestone
is done only when its gate runs green in `gates.sh` or is recorded as
an explicit one-shot verdict.

Phase A: foundations and model
- M01 scaffold: dune-project, licenses, gitignore, README, gates.sh
  skeleton. Gate: dune build. [DONE]
- M02 DESIGN.md: this document. Gate: file present, milestone table
  authoritative. [DONE]
- M03 toolchain: qcheck, alcotest, qcheck-alcotest installed on switch
  karamel-710; ctlk_topos pin present. Gate: dune finds libs. [DONE]
- M04 model state and frame. Gate: dune build. [DONE]
- M05 model props, check, R0 guard, Coupled/Uncoupled control.
  Gate: check.exe runs. [DONE]
- M06 model green: all expectations met, negative control fails where
  it must. Gate: check.exe exit 0. [DONE]
- M07 gates.sh v1: build + runtest + model check. Gate: exit 0. [DONE]
- M08 omlz dual-gate probe: run `omlz check` on a probe core file via
  the zxcaml wrapper; wire zxlint. Gate: recorded verdict, degrade
  documented if omlz unavailable. [DONE: DEGRADED-INACTIVE, verdict +
  minimal repros in research/m08-omlz-verdict.md; zxlint wired]

Phase B: dual-compiled core
- M09 core/prelude.ml: total combinators (nth_opt, div_opt, fold,
  map). Gate: dune + zxlint (+ omlz check when active).
- M10 core/ast.ml: Ty, closed Method enum, Expr, Lit with F64_bits of
  (hi32, lo32) int pair (OCaml native int is 63-bit, one int cannot
  hold an IEEE binary64 pattern). Gate: build; matches exhaustive.
- M11 core/wf.ml: type-shape checker returning result. Gate: unit
  vectors, positive and negative.
- M12 core/obs.ml: observation ADT + canonical encoding. Gate: unit
  vectors.
- M13 core/printer_rust.ml: AST to Rust expr text; float renderer
  injected. Gate: golden tests.
- M14 core/interp.ml: reference interpreter, ops-record injected,
  panic as value. Gate: hand-written vectors per construct.
- M15 shell/floatops.ml: IEEE ops record + shortest-roundtrip decimal
  rendering. Gate: QCheck bit-exact roundtrip on random bit patterns.
- M16 dual gate: every core/ module passes dune + zxlint (+ omlz
  check). Gate: gates.sh extended.

Phase C: generator
- M17 shell/gen.ml: QCheck sized, type-directed generator (Ty first,
  then Expr at Ty). Gate: 1k samples all pass wf.
- M18 corpus-seeded weights: per-construct weights from the topcoat
  examples corpus; config record. Gate: every constructor reached at
  N=10k (counter report).
- M19 type-preserving shrinker. Gate: shrink chains preserve wf on 1k
  samples.
- M20 printer soundness: batch 1k printed exprs into one driver crate,
  compile with rustc. Gate: zero rejects; any reject minimizes to a
  recorded printer bug.
- M21 taxonomy split: read-only vs signal-writing modes; sample
  environment generator (signals 1..3 drawn with element type and
  initial value; inputs keep the fixed driver shape with drawn
  initial values; fn-typed inputs excluded, expr! .call gap).
  Gate: mode counters at N=10k, classifier agrees with the requested
  mode on every sample.
- M22 coverage report CLI; no silent caps, dropped samples logged.
  Six sections: header, constructor tally, mode counters, environment
  coverage, target types and size, drops. Three scopes: default and
  m20 draw whole samples, m18 redraws the M18 stream. Every cap in
  shell/ and bin/ is listed in shell/cover.ml with whether it drops a
  sample; only kept samples feed a histogram.
  The required set has two halves, because they live in two
  tallies: body names scored against the kept bodies, init shapes
  scored against the drawn initial values. The report names both
  as unreached_required and unreached_required_inits.
  Gate: strict smoke run at N=10k drops nothing, reaches every
  required body name and every required init shape, and emits a
  json form; the m18 constructor block is byte-identical to the
  block test_gen prints.

Phase D: legs and differ
- M23 driver-rs template: batch of expr! call sites, per-expression
  catch_unwind, server render capture, JS extraction, JSON out.
  Gate: seed expressions produce native value + JS text. The driver
  has a per-case timeout (2000 ms default) on a spawned thread; a
  timeout prints a no_terminate line and exits 3, and M24 resumes
  with --from. A String-typed init renders String::from(..) at every
  string-literal leaf (Driver.init_rust). A panicking case loses its
  JS to the unwind, so a second call site in closure form supplies
  it and the line records js_form and js_consistent. All five signal
  writers panic server-side at this pin
  (topcoat-runtime crates/topcoat-runtime/src/surrogate/signal.rs:50-108),
  so a Signal_writing sample observes the write panic and not a value;
  M36 re-probes that verdict when the browser leg lands. The seed
  vector is twelve cases and pins all four hints.
- M24 shell/rust_leg.ml: crate writer, cargo runner against the
  pinned topcoat path dep, JSON parser. core/json.ml parses the subset
  the harness emits (objects, strings with the six escapes, ints, the
  three literals) and is total: a bad byte is a named error, never an
  exception. core/wire.ml maps one line to Obs.t plus the js form, the
  hint and js_consistent, and derives the resume index. The runner is a
  resume loop: exit 3 restarts the child at the last decoded case plus
  one under a budget, and every segment appends to one JSONL, so a
  timeout costs one case and not the run. bin/m24.exe seeds prints one
  row per case. Gate: end-to-end on seeds, twelve rows compared with a
  hand-derived table.
- M25 driver-js: node script importing the browser surrogate SOURCES
  under node's type transform, stub cx, evaluates JS strings, captures
  value/panic/signal finals.  Gate: seeds round-trip.  The browser dist
  bundle exports nothing and is unusable under node, so the driver
  imports browser/src/context.ts, signal.ts and surrogate/ in place
  through a resolve hook that adds the .ts extension and finds the
  pinned @maverick-js/signals under driver-js/.  Evaluation is the
  production form, new Function("cx", `return ${js};`), called once
  against a fresh Context over a registry seeded from the line's
  signals array;  a closure-form line is invoked once.  The JS text is
  entity-decoded with the exact inverse of the comment escaper, three
  entities and no general table.  Each case runs in its own worker
  thread and a timeout writes a no_terminate line and continues, so
  there is no resume protocol and no exit 3.  The per-case timeout
  starts at the worker's ready message and not at its creation,
  because a fresh worker must transform the clone TypeScript first and
  that cold start grows with the load on the machine;  the cold start
  has its own budget and its expiry is a driver_error that names
  worker_startup.  The wire signal id is a
  u32 and the JS registry key is a uuid, so the two are paired by
  position and only the u32 leaves the driver.
- M26 shell/js_leg.ml + shell/ref_leg.ml: spawn wrapper + adapter to
  obs.  Gate: three observations per seed.  The js wire has no js_hex
  and no js_consistent and its signal entries are two keys, so
  core/wire_js.ml decodes it with its own strict key tables and its own
  signal decoder, reusing core/wire.ml for the value tree, the hex, the
  class, the hint and the js_form.  A lossy UTF-16 payload is detected
  on the parsed line before any value decoding, at any depth, and the
  three js outcomes with no Obs counterpart (js_error, skipped,
  driver_error) stay leg-level results rather than growing
  core/obs.ml.  The reference leg composes the rendered channel
  core/interp.ml deliberately omits: Rust Display with no html
  escaping, so f64 goes through f_display, str bytes travel verbatim,
  Some renders its payload, and unit, None, tuple, Ok, Err and closure
  render absent.  The CLI prints three lines per case, R then J then F,
  each an Obs.encode, and the gate compares all 36 with a hand-derived
  table.
- M27 core/differ.ml: verdict ADT (Agree, Diverge with channel and
  legs, Known with tag, Leg_fail), subset-pure. Gate: unit vectors. The
  six channels are compared in one fixed order, outcome, class,
  message, value, rendered and signals, and a channel is compared only
  when every party projects a value on it, so a kind mismatch is
  reported once on outcome and never again. Signals compare by id, so
  their order is not a conformance surface. A Read_only sample has
  three parties; a Signal_writing sample has two, the js leg and the
  reference, because the server panics on every signal write by design,
  so the rust cell of such a sample is not a party. An absent party
  cell short-circuits to Leg_fail with the leg and the leg's own reason
  text, in the order rust, js, reference. The walk classifies each
  divergent channel as excused or not against a known list and reports
  the first unexcused divergence, else the first excused channel's tag
  as Known, else Agree, so an entry never masks a later unexcused
  channel. core/differ.ml ships one entry, [ i1 ], for the case 10 class
  divergence that finding I1 explains; M33 relocates and grows the
  entries with upstream citations. The CLI prints a fourth line per
  case, V, carrying the sample mode and the verdict text, and the gate
  compares all 48 lines with a hand-derived table.
- M28 planted-oracle gate: a deliberately mutated interpreter AND a
  deliberately mutated js stub must BOTH produce Diverge, then
  restore green. Gate: both planted bugs detected.
  Two plants, selected at run time by m27's --plant flag and never by
  editing a file: ref:display_sign flips the sign bit of the float the
  reference leg is about to display, and js:signal_get_plus_one adds
  one to the number a signal read returns. The "stub" is the worker's
  own glue around the clone's Context, so the plant is a glue plant and
  the clone is never touched. Three runs of one binary: the ref run
  turns cases 0, 3 and 6 into diverge:rendered:odd:ref, the js run
  turns case 6 into diverge:value:odd:js, and the no-plant run
  reproduces the m27 table byte for byte. Restore green is that third
  table plus the m27 gate that ran one line earlier in the same ladder:
  nothing was edited, so nothing has to be put back, and there is no
  window in which a crash leaves the tree mutated. Only two of the
  twenty-one interpreter ops are reached by these twelve seeds,
  f_display and str_debug, so the plant table is seed-bound today and
  M34 grows it with the corpus.
- M29 minimizer: shrink loop re-executing legs, divergence-preserving.
  Gate: planted divergence minimizes below a size bound.

  The loop is core/minimize.ml and is pure: the three legs enter as one
  injected function, so the whole walk is testable with a fake oracle
  that runs nothing.  One round offers every candidate of
  Shrink.cands at the sample's target type, then one drop per binding
  the body never mentions, and the loop moves to the FIRST candidate
  whose verdict is a Diverge on the same channel with the same split.
  Agree, Known, Leg_fail and a run that produced no line never
  preserve, so a timeout can lose a shrink but can never invent one.
  A round is one batch: one crate, one build, one node start, one
  reference pass.  Every accepted step lowers Shrink.size plus the
  binding count by at least one, so the walk terminates; the round fuel
  is a second bound and a stop reason, never an error.  A round whose
  answers are ALL no-verdicts is a third stop, Stuck, which carries the
  runner's reason: blind legs are not a fixpoint and the gate names
  them.  bin/m29.ml
  prints the walk and then runs the minimized sample once more with NO
  plant, and that control must agree: a divergence that survives with
  no plant was never the planted one.  m29_gate.sh runs both plants and
  compares the two walks with the hand-derived tables of the M29 spec.
- M30 repro emitter: self-contained markdown (Rust source, emitted JS,
  three observations, SHAs, seed). Gate: golden repro for the planted
  bug.

  M29 shrinks a divergence to a small sample.  M30 writes down what it
  found.  `m30 repro <dir> --plant P` runs the same walk, prints the
  same text, then runs the final sample ONE more time to earn a
  witness, and writes `<dir>/repro.md` with nine blocks: the title,
  the provenance, the program, the emitted JS, the sizes, the four
  witness cells, the walk trace, how to reproduce it and what to look
  for.  Two properties hold by
  construction.  The renderer is a pure function in core/repro.ml, so
  the same walk renders the same bytes: no date, no host name and no
  absolute path enters the file.  The witness is one more planted run
  of the final sample in <dir>/rp, and it must satisfy
  Minimize.preserves, so a repro file cannot record a difference the
  walk did not keep.  The two shas in the provenance block come from
  git rev-parse HEAD in the clone and in this repository, so a reader
  knows which pair of trees the file is about.  The walk itself moved
  to shell/walk.ml so both binaries run one copy of it, and the
  unedited m29 gate is the proof that its printed bytes did not move.
- M31 pipeline CLI: run --samples N --seed S, journal + resume.
  Gate: 500-sample smoke completes and replays.

  M30 writes one repro by hand;  M31 runs the corpus.  `m31 run <dir>
  --samples N --seed S` draws N samples from one seed, runs them in batches
  of `--batch` (100 by default) through the same three legs M29 uses, and
  appends one JSON line per sample to `<dir>/journal.jsonl`: the index, the
  mode, the size, the verdict, the three cells and the program that produced
  them.  The first line is a header carrying the seed, the batch size, the
  plant and the sha of the clone, so a journal names the run that wrote it.

  A second `m31 run` of the same directory CONTINUES it.  There is no
  `--resume` flag: the CLI decodes the journal, refuses a header that
  disagrees with the flags, and starts at the first index the file does not
  hold.  A resumed run draws N samples and drops the ones already written, so
  its batch boundaries differ from a straight run's and its journal bytes do
  not.  `m31 replay <dir>` prints the summary of an existing journal and
  spawns nothing at all;  the summary is computed from the decoded journal in
  both cases, so a run and a replay print the same bytes.

  The journal is data, not a log.  `core/journal.ml` is pure, is inside the
  ZxCaml subset and has no I/O, so M34 and M35 read a journal with the codec
  and no process.

Phase E: campaign and delivery
- M32 correspondence gate: run log validates against model/frame.ml
  edges; a mutated log is rejected. Gate: both directions checked.

  M31 writes the journal;  M32 writes a second file beside it.  A run of
  `m31 run <dir>` now appends `<dir>/trace.jsonl` in the same batch step as the
  journal: one header line with the journal header's four fields under the key
  `m32`, then one line per sample carrying the index and the model steps that
  sample walked.  The step names are the constructors of `model/frame.ml`, so a
  change to the model breaks the build of `shell/correspond.ml` and not a test.

  `m32 check <dir>` reads both files and checks both directions.  The log
  against the model: every step of every line is an edge of `Frame.steps` from
  the world the line has reached, and the line ends in a model terminal, or in
  `minimizing_hi` when the verdict diverged, because M31 does not shrink.  The
  journal against the log: the two headers agree, the line counts and the
  indices agree, each leg ran in the log exactly when its journal cell is a
  cell, the judge step matches the verdict head, the end stage matches the
  disposition, and a `leg_fail` verdict names a leg that crashed.  The checker
  prints one report line and exits 0, and on the first line that does not
  correspond it prints nothing on stdout and names the line and the check on
  stderr.

  The journal is still data, not a log.  The trace is the log.  It is a
  second file, and `core/journal.ml` does not change.  A resumed run requires the
  trace to hold as many sample lines as the journal and refuses a directory in
  which they disagree;  it repairs nothing.
- M33 known-divergence allowlist, each entry backed by an upstream doc
  or source citation. Gate: allowlist review.

  The entries live in `core/known.ml` with their citations.  `core/differ.ml`
  keeps the walk and owns no entry.  An entry names its head:  upstream, when a
  document or a source comment names the difference;  harness, when the
  difference is a property of our legs or of our differ.  A difference that is
  neither is a finding and keeps its Diverge verdict.

  An entry excuses ONE channel of one row, so the walk still reports the first
  unexcused channel.  The two entries M33 ships excuse a class channel whose
  row then reports its message divergence, so no upstream text difference is
  hidden by an excuse.

  `KNOWN.md` is RENDERED from the entries by `m33 render` and the gate compares
  the file with the render byte for byte, so the review document cannot drift
  from the code.  The rendered channel and splits are load-bearing:
  `Known.allow ()` fences every closure with the fields its entry declares, so
  a predicate broadened past them stops firing.  `m33 cite` opens every cited
  range and requires the quoted text to be inside it, and it refuses an empty
  quote.  The journal format does not change, `bin/m27.ml` keeps
  the frozen M26 seed list, and no leg is re-run by this gate.
- M34 campaign 1: 5k+ mixed samples, dedup by construct signature.
  Gate: campaign report.

  `m34 report <dir>` reads an unplanted M31 journal and its M32 trace,
  checks correspondence in both directions, and regenerates every sample
  from the seed. Index, mode, size, environment and body must match before
  the report uses the AST. The default minimum is 5,000 samples, both modes
  must occur, and a run containing only losses is refused.

  Construct signature v1 counts constructors in six separate maps: target,
  body, input types, input initializers, signal types and signal initializers.
  Names are sorted; literal values and variable ids do not enter the maps.
  Divergences group by mode, full verdict and signature, in first appearance
  order. Every member index remains in the report for M35. Known rows form
  no group. All attempted samples, including every loss reason, remain in
  the census and the explicitly labeled attempted-constructor coverage.

  `m34_plants <campaign-dir> <out-dir>` selects agreeing corpus rows that
  observably reach addition and string length. It runs fresh
  unplanted and planted three-leg witnesses for both. The local plants
  replace `f_add` with a sign-flipped result and `f_of_int` with a result
  incremented by one. Each control must agree. Read-only witnesses must
  diverge on value or rendered text with the reference as the odd leg. The
  addition plant also accepts a signal-writing witness whose final signals
  differ between the JS and reference legs. This corpus reaches addition
  through signal increment. Its agreeing read-only samples discard addition
  results or leave addition branches unexecuted.
  The original M28 plants and fixed seed tables retain their behavior.

  `research/campaign-1/` records the one-shot live campaign, its compressed
  journal and trace, report, plant witnesses and source fingerprints.
  `m34_gate.sh` checks those fingerprints, replays the archive, compares the
  report byte for byte, independently checks the divergence membership and
  loss census, and rejects corrupted programs, traces, plants, verdicts and
  insufficient sample counts. Replaying this evidence runs no product leg.
  A changed campaign source requires renewed evidence, never a silent skip.

  The live run may finish a serial prefix with `m34_campaign.py`. Three
  independent workers call `m34_slice` over the unchanged Pipeline batch
  implementation, with distinct Cargo crate names and globally indexed
  slices. The coordinator validates every slice and the whole joined
  report before publication. Cached slices are bound to their prefix,
  parameters, source files and executables. A publication marker retains
  the validated join so an interrupted pair replacement can be completed
  safely on the next invocation.
- M35 repro stream: every non-Known divergence has a minimized repro
  file under repros/. Gate: 1:1 mapping.

  `m35 stream <campaign> <root> <clone>` regenerates the validated M34
  campaign, selects every Diverge row and measures the original verdict
  again without a plant. Each case runs the M29 greedy shrink order;
  pending requests are pooled into crates of at most 100 candidates.
  A final fresh three-leg witness must preserve the original channel and
  split. Only Fixpoint is publishable. The fuel bound is the original
  sample size plus one, enough for every strictly decreasing walk.

  Every seed/index has its own Markdown repro, raw Rust/JS witness and
  recorded round answers under `repros/campaign-1/<index>/`. Construct
  grouping does not discard member identities. Replay regenerates the
  start AST, reconstructs the greedy walk, reinterprets the final sample,
  checks the witness verdict and compares the entire rendered Markdown.
  Source and artifact fingerprints bind these recorded answers to the live
  evidence. Replay rebuilds each recorded answer as the verdict class that
  wrote it, and refuses text that no class writes. The recorded oracle sha
  must equal the sha the caller pins, so the provenance line of the repro
  is checked and not only shaped. Replay does not re-execute the two
  product legs.

  The gate checks the exact divergence-to-directory mapping and rejects
  truncated walks, substituted identities, duplicate identities, missing
  witnesses, forged answer text, a substituted oracle sha and fuel changes.
  Every corruption control names the refusal it expects, so a refusal for
  another cause fails the control. Publication replays every live output
  and then the staged copy that the manifest fingerprints, before an atomic
  directory rename, and refuses an existing destination. The live runner
  records a completion receipt only if producer sources and the executable
  remain unchanged throughout the run; publication requires it.

  The M29 declared-signal restriction remains: a body candidate that stops
  using a signal can fail JS signal arity. Compiler and leg failures also
  exclude candidates. Fixpoint claims are relative to these available
  candidates, not global minimality. Repros are evidence for triage,
  without automatic upstream attribution or filing.
- M36 re-pin playbook: script bumps the topcoat SHA, re-runs, diffs
  verdicts. Gate: idempotent dry-run on the same SHA.
- M37 README and docs final. Gate: quickstart reproduces smoke run.
- M38 final gates + staging: full ladder green, repo staged, commit
  message drafted for the user. Gate: git status clean-staged.

Two milestone slots stay in reserve under the 40 cap for discovered
work.

## 6. Out of scope, v1

`.await` and `Procedure::call` legs (network semantics), full `view!`
DOM rendering (only text-binding evaluation), browser-only APIs beyond
the surrogate vocabulary, upstream PRs from this repo (repros are
drafted for the user to file; nothing is posted by automation).

## 7. Conventions

No OCaml exceptions anywhere (raise, failwith, assert). Indexing and
division only through total combinators. Exhaustive matches, no
wildcard arms on sum types. Option and Result consumed through
combinators. The repo never commits or pushes itself: work is staged
and the commit message is handed to the user.
