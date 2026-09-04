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
- M25 driver-js: node script importing browser dist surrogates, stub
  cx, evaluates JS strings, captures value/panic/signal finals.
  Gate: seeds round-trip.
- M26 shell/js_leg.ml + shell/ref_leg.ml: spawn wrapper + adapter to
  obs. Gate: three observations per seed.
- M27 core/differ.ml: verdict ADT (Agree, Diverge with channel and
  legs, Known with tag, LegFail), subset-pure. Gate: unit vectors.
- M28 planted-oracle gate: a deliberately mutated interpreter AND a
  deliberately mutated js stub must BOTH produce Diverge, then
  restore green. Gate: both planted bugs detected.
- M29 minimizer: shrink loop re-executing legs, divergence-preserving.
  Gate: planted divergence minimizes below a size bound.
- M30 repro emitter: self-contained markdown (Rust source, emitted JS,
  three observations, SHAs, seed). Gate: golden repro for the planted
  bug.
- M31 pipeline CLI: run --samples N --seed S, journal + resume.
  Gate: 500-sample smoke completes and replays.

Phase E: campaign and delivery
- M32 correspondence gate: run log validates against model/frame.ml
  edges; a mutated log is rejected. Gate: both directions checked.
- M33 known-divergence allowlist, each entry backed by an upstream doc
  or source citation. Gate: allowlist review.
- M34 campaign 1: 5k+ mixed samples, dedup by construct signature.
  Gate: campaign report.
- M35 repro stream: every non-Known divergence has a minimized repro
  file under repros/. Gate: 1:1 mapping.
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
