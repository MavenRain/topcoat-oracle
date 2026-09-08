# M39 validation

Validation date: 2026-09-08. Base commit:
`9d8780b0947a9483d7f2bc28b11dd7d0fdabddee`.
Target: `51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a`.

M39 binds every declared signal to its captured Rust Debug UUID and preserves
unused bindings. The loader resolves symlinked checkout roots before resolving
runtime imports. Invalid or duplicate identities produce named driver errors.
The known-divergence predicates and upstream target remain unchanged.

## Measured behavior

The fresh 500-row M31 run at seed `0x4d3331` completed 449 comparisons
(395 agreements and 54 divergences), compared with 87 completed comparisons
(77 agreements and 10 divergences) in the retained baseline. All 500 program
identities and Rust/reference observations match the baseline. No previously
completed comparison became a loss. Of 394 former signal-arity failures,
361 now adjudicate and 33 expose an existing JavaScript syntax failure.
The remaining 51 losses are 47 syntax failures and four missing-JS skips.

Case 105's mixed signal types now agree instead of throwing a TypeError.
Case 111 now reports the toggled signal under its correct wire id and agrees.
The exact metrics, journal digests and both before/after witnesses are in
`research/m39-signal-identity.json`, which records the 47 syntax failures and
four missing-JS skips behind the 51 losses. Codex checked every recorded
metric and witness against both journals. The M31 rung of the main session
ladder of 2026-09-08 rebuilt `_emit/m31/out/straight/journal.jsonl`. The
main session measured its SHA-256 as
`95f695f28675c1ec43c1a2c96e1a55761560ed3aa0396e468632c85618d5895f`, which
equals the `after_journal_sha256` field of
`research/m39-signal-identity.json`.

## Validation record

Codex ran the milestone ladder in an isolated checkout of the base commit,
in three pieces, never as one uninterrupted `gates.sh` invocation. The first
piece passed the OCaml build and tests, the CTLK checks and the negative
controls, the ZxCaml audit, and M20 through M30. Its logs are
`_emit/m39/ladder-prefix.stdout` and `.stderr`. A second piece failed at M32
and is retained as `_emit/m39/ladder-m32-attempt.stdout` and `.stderr`. The
third piece exited 0 with `GATES GREEN` at 02:32 on 2026-09-08. Its script
is `_emit/m39/continue.zsh` and its logs are `_emit/m39/ladder.stdout` and
`.stderr`.

The main session then ran its own gate battery on the final staged bytes on
2026-09-08, with the sandbox off. `m39_gate.sh` exited 0 at 09:41:16. It
printed `M39 SELFTEST OK: 15 expectation tests` and `M39 GATE GREEN: 11
signal identity cases, physical and symlink clone paths`. Its identity
directory is `_emit/m39/identity.htl3_sdd/` and its log is
`_emit/m39/m39-gate.2026-09-08.log`. `gates.sh` then exited 0 at 10:18:21
with `GATES GREEN` and no `RED` line. It printed `GATE GREEN` for M20, M22,
M23, M24, M25, M26, M27, M28, M29, M34, M35, M36, M37 and M39. Its log is
`_emit/m39/gates.2026-09-08.log`, and the battery timing line is
`_emit/m39/battery-status.2026-09-08.txt`. An earlier own-window ladder on
the round 1 bytes ended `GATES GREEN` at 07:35 on the same day. Its log is
`_emit/m39/gates.2026-09-08.r1bytes.log`.

- The Codex continuation rebuilt `@all`, passed `zxlint`, and ran the full
  OCaml tests through M33. Its nested M31/M32 gates earned fresh journals
  after the citation changes rebuilt the runner. Straight and resumed
  500-row journals and traces are byte-identical. M31 through M33 passed
  their planted, correspondence, census, citation and corruption controls.
- M34 passed all 5,000 archived campaign rows. M35 passed all 103 minimized
  repros, including replay and corruption controls.
- M36 passed 11 unit tests and the real same-revision comparison, with 88
  adjudicated rows per side, no changed verdicts or observations, five
  writer probes per side and identical checked reuse. Its planted control
  changed five verdicts and five observations without losing comparisons.
  The 10:18 ladder repeated this leg with the same counts. Its artifacts are
  `_emit/m36/gate.nhyzDx/`.
- M37 passed its ten tests and the documented quickstart: 100 samples, 88
  adjudicated rows (76 agreements and 12 divergences) and 12 losses. M32
  correspondence, relocated replay and the resume that rebuilt 50 rows all
  passed. The 10:18 ladder repeated this leg. Its artifacts are
  `_emit/m37/gate.m0uli03d/`, `_emit/m37/out/smoke.LOinb0/` and
  `_emit/m37/out/partial.9h0zvqjl/`.
- M39 passed all 11 real-runtime fixtures with a physical checkout and a
  symlink whose path contains spaces. The decoy-string control contains the
  raw text pattern the former scanner misidentified. Exact values and final
  signal states are checked. Every expectation pins the whole row shape, and
  each refusal pins its diagnostic bytes, including the JavaScript error
  name and message of the unknown-identity case. The artifacts of the 10:18
  ladder run of this gate are `_emit/m39/identity.i_9oaefj/`.
- The Codex continuation passed a 103-test JS suite, nine M20 diagnostic
  tests, 17 M31 plant-checker tests, 11 M32 checker tests, 17 archive-source
  tests, and the switch controls across 21 gate scripts. The review repairs
  then added checks to those files. The 10:18 ladder ran the JS suite as 106
  tests, 106 passing and none failing.
- No Rust source changed. `diffclass --in '*.rs'` reported SKIP. The
  required milestone Rust compilation and execution still ran.

The first attempts exposed three gate assumptions that required repair:
M20 mistook the Cargo progress line `Compiling thiserror` for a diagnostic;
M31 assumed every planted reference-render change lost its JS comparison;
M32/M33 pinned the former loss census. The revised controls require the
exact nine reference sign changes and eight newly visible rendered-verdict
changes, with exact indices and all other observations and trace steps
preserved. The outcome split at case 16 retains precedence. Diagnostic and
plant-checker tests reject malformed identities, wrong counts, altered
unrelated fields, wrong judge transitions and unexpected diagnostics. An
earlier standalone M37 attempt also exposed the symlink-root loader failure.
It is not counted as successful validation. The final quickstart and both
M39 path variants passed with that loader repair.

## Review

Two review rounds ran on this slice. The review record is kept outside the
repository. Round 1 kept seven medium findings, J1 through J7: unpinned
detail bytes and unnamed legs in `m39_verdict.py`; an untested historical
manifest branch in `m34_verdict.py` and `m35_verdict.py`; unpinned refusal
counts in `VALIDATION.md` and `KNOWN.md`; plant guards in the M31 and M32
checkers that no test could fail; an archive snapshot with no determinism
pin, producer revision or capture path; and a validation record that never
named its actor. All seven repairs are in the staged files.

Round 2 kept seven more findings, J1 through J7, and repaired all of them.
It first moved the round 1 J1 tests out of an untracked file into the
`m39_verdict.py --selftest` entry point, so the checked-in tree names
nothing that is not on disk. It then pinned the JavaScript error diagnostics
of every refusal outcome, required the driver key set to match, made the
`m39_verdict.ok` dune rule depend on `research/m39-signal-identity.json`,
hardened the archive digest guard with a mutation case and a
capture-then-verify case, and replaced five artifact directory citations
that existed only in the Codex clone. A third fix pass closed the two
findings the round left open. For J6, `driver-js/loader.mjs` now exports
`cloneSrcOf`, which realpaths the clone source directory itself, not only
the clone root, and passes that href to `driver-js/resolve-hook.mjs`. A
symlink below the clone root no longer turns every case into
`worker_error`. For J2, the live branch of
`m34_verdict.load_evidence` refuses the archived campaign manifest; that
refusal is now diagnosable, tested, and recorded as the limit below instead
of removed.

## Current unit suites

The main session ran these commands from the repository root on 2026-09-08.
Every command exited 0.

- `node --test driver-js/test/loader.test.mjs`: 9 tests.
- `node --test driver-js/test/signals.test.mjs`: 11 tests.
- `python3 m39_verdict.py --selftest`: 15 tests.
- `python3 test/test_archive_sources.py`: 27 tests.
- `python3 test/test_m20_verdict.py`: 9 tests.
- `python3 test/test_m31_plant_verdict.py`: 20 tests.
- `python3 test/test_m32_plant_verdict.py`: 13 tests.
- `python3 test/test_campaign_runner.py`: 6 of 6 mocked groups.
- `python3 test/test_repro_stream.py`: 13 tests.
- `python3 -m unittest discover -s test -p test_gate_switch.py`: 3 tests
  over 21 gate scripts.
- `python3 -m unittest discover -s test -p test_m37_quickstart.py`: 10
  tests.

## Evidence and limits

The historical 5,000-row campaign and 103 repro archives retain their
original bytes and manifests. `research/archive-v1/sources.json.gz` holds
the exact 68 producer source files from the base commit, checked against
both existing source inventories. It is verified as data, never extracted or
executed. Historical checks still rebuild reports and replay the recorded
semantics using the live core. Fresh production and publication retain their
live source and executable guards.

Limit measured on 2026-09-08, recorded in `KNOWN.md` under
`L-campaign-1-historical`: the live source inventory of
`m34_verdict.source_inventory` now names two producers that the archived
`research/campaign-1/provenance.json` predates, `archive_sources.py` and
`driver-js/lib/signals.mjs`. The live branch of
`m34_verdict.load_evidence` therefore refuses that manifest with
`incomplete source inventory: live producers not in the campaign manifest:
archive_sources.py, driver-js/lib/signals.mjs`, and `m35_verdict.py run`
and `m35_verdict.py publish` print that refusal as one `m35: RED` line and
exit 1 until a new campaign records the M39 producers. This is the live
guard working as designed: a changed producer must refuse fresh production
and publication. The shipped M34 and M35 gates read the historical branch,
which verifies the archived producer bytes, and are not affected; the M34,
M35 and M39 gates all passed on these bytes.
`test/test_archive_sources.py` pins the gap and the wording of the refusal,
so renewing the evidence turns those tests red until this paragraph and the
`KNOWN.md` entry are renewed with it.

Codex ran its validation in an isolated checkout of the base commit outside
this repository. Its build products and full runtime artifacts stay there.
The reviewed source files and the piece logs were copied into this
repository only after checking that its HEAD and tracked bytes still matched
the baseline. Promotion checked staged file hashes against the validated
source bytes and left HEAD unchanged. The main session then ran its own
battery inside this repository, so the 2026-09-08 logs named above are logs
of this tree. Generated evidence is gitignored. The source changes and this
record are staged for the user's commit.

The recovered comparisons do not establish upstream fault. Historical
campaign losses remain historical losses. No fresh 5,000-row campaign or
replacement repro collection was produced for this change.

# Historical M37 and M38 validation

Validation date: 2026-09-08. Base commit:
`330d68123b49c893ab0b37a0bbdc6c82faafc43a`.
Target: `51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a`.
The round 1 review of this slice ran on 2026-09-07 and kept seven
findings. All seven repairs are in the staged files. Every run below is
a run of the repaired tree.

The change finalizes the README, executes its quickstart as a gate, and
makes every legacy gate select `anvil-ocaml` explicitly. A missing switch
or failed `opam env` stops execution before a build. No oracle producer,
archived observation, known-divergence rule or expected verdict changed.

## Environment

The run uses OCaml 5.3.0, Dune 3.24.0, `ctlk_topos` ba5c567,
QCheck 0.91 and Alcotest 1.9.1 from `anvil-ocaml`, Node v23.10.0,
and Rust `nightly-2026-06-22`. `ctlk_topos` is an opam pin in
`anvil-ocaml` on the local checkout `/Users/oobi/Documents/ctlk-topos`
at ba5c567. The Topcoat checkout was clean at the pin above. The JS
dependencies were already installed from the package lock.

## Checks

- `./m37_gate.sh`: GREEN at 23:07 on 2026-09-07, exit 0. It produced
  100 samples and 15 adjudicated rows (agree 9, known 0, diverge 6)
  over a floor of 10, and exercised both modes. It read the whole M32
  check line and required gen_bug 0, oracle_bug 0, and dropped_agree 9,
  dropped_known 0 and minimizing_hi 6 equal to the journal census. It
  replayed a copy of the evidence at another path, where the journal
  path is the only permitted difference. It also resumed a copy
  truncated to 50 rows, and the resumed legs rebuilt the other 50 rows
  byte-identically. The resume of the complete directory stays as a
  weaker second assertion, because it runs no leg.
- `test/test_m37_quickstart.py`: ten unit tests passed. They reject
  insufficient comparisons, incorrect provenance, bool-typed identities,
  a missing final newline, an unknown verdict head, missing or reordered
  identities, invalid documentation blocks, replay or resume changes,
  and an M32 census that names a bug or disagrees with the journal. The
  last cases drive the whole gate over a stub root with stub legs. The
  gate passes on a correct root. It turns RED for a duplicate or
  absolute artifact line, a stale directory, a substituted checker line,
  a planted `gen_bug` or `oracle_bug`, a leg that exits nonzero, a
  relocated replay that answers about another directory, and a truncated
  resume that rebuilds other bytes.
- `test/test_gate_switch.py`: three scenarios across 20 script
  preambles, 60 subtests passed. The roster now includes `m37_gate.sh`.
  A failed environment selection's partial output was not evaluated. The
  valid selection replaced the inherited switch before the fake build
  started. These controls execute no real build.
- `./gates.sh`: GREEN at 00:53 on 2026-09-08, exit 0, final line
  `GATES GREEN`. This includes the OCaml build and tests, CTLK positive
  and negative controls, ZxCaml subset checks, all milestone gates
  through M37, and the switch tests. M34 checked all 5,000 campaign
  rows. M35 checked all 103 minimized repros. M36's same-revision
  comparison changed no verdicts or observations, while its planted
  control changed one verdict and five observations. Its five writer
  probes and checked reuse also passed. M37 again produced the same
  census, correspondence, relocated replay and truncated resume.
- An earlier ladder at 00:03 on 2026-09-08 went RED at the M32 rung for
  one environment reason. The switch held a `ctlk_topos` that was
  installed from a deleted directory. The opam pin above repaired the
  switch at 00:11, at the same version, with no source change.
- `git diff --check` and the changed-file em dash scan passed.
  `diffclass --in '*.rs'` reported no changed Rust files. The full ladder
  still runs its required Rust compile and execution checks.

## Evidence and limits

The quickstart gate retained `_emit/m37/gate.qbtoqfx6/`,
`_emit/m37/out/smoke.mrzRPU/`, its relocated replay under
`_emit/m37/out/replay.faxtgopv/` and its truncated resume under
`_emit/m37/out/partial.jhgis_08/`. The full ladder retained
`_emit/m37/gate.pkvpmbsy/`, `_emit/m37/out/smoke.SWrbTK/`,
`_emit/m37/out/replay.g6iq7kfx/` and `_emit/m37/out/partial.qwvau73n/`.
Both run logs are retained as `_emit/m38/gates.2026-09-08.log` and
`_emit/m37/m37-gate.2026-09-07.log`. M36 retained
`_emit/m36/gate.CgOlh8/`. The Codex ladder of 21:18 on 2026-09-07 is
history under `_emit/m38/gates.stdout`; it predates the review.
Generated evidence is gitignored. The source changes and this record are
staged for the user's commit.

M34 and M35 validate the archived campaign and all 103 repros against
their original source fingerprints. Their replay gates do not rerun the
archived Rust and JS observations. M36 and M37 execute fresh
observations. The campaign's 4,197 losses remain documented. Passing
gates does not turn those attempts into completed comparisons, and does
not establish which implementation caused an unexplained divergence.
