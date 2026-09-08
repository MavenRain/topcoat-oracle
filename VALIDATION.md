# M37 and M38 validation

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
