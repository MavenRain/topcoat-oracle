# Re-pin playbook

M36 compares the current Topcoat checkout with a candidate commit using the
same generated programs. It checks out the candidate in an isolated local
clone, runs all three legs again, and records every verdict and observation
change. It also executes five direct signal-write probes on each revision.

The existing campaign and repros describe their recorded revision. Testing a
candidate does not rewrite that evidence or adopt new expected results.

## Prepare

Use the toolchains and driver dependencies from the README. Build the three
executables from the oracle repository root:

```sh
opam exec --switch=anvil-ocaml -- dune build bin/m31.exe bin/m32.exe m36/probe.exe
```

The target checkout must be clean. Both commits must already be present in
its local Git object database. The runner performs no network fetch; Cargo
runs offline and needs its dependencies cached. A missing dependency is a
failed run with a retained log.

Run the same-revision check first:

```sh
python3 m36_repin.py --clone ../topcoat --to HEAD \
  --out _emit/m36/same-sha --dry-run
```

`--dry-run` still executes the Rust, JS and reference legs. It requires the
candidate to resolve to the baseline SHA and requires zero verdict or
observation changes. It leaves the caller's Topcoat checkout in place.

## Compare a candidate

Pass a locally available commit or ref as `--to` and choose a new output
directory. For example, to compare the currently checked-out commit with its
parent:

```sh
python3 m36_repin.py --clone ../topcoat --to HEAD^ \
  --out _emit/m36/parent --samples 100 --seed 0x4d3336 --batch 100
```

Use `--plant-candidate ref:display_sign` to plant a known bug in the
candidate leg run alone. A planted run is a negative control and never an
adoption decision. The runner refuses a plant together with `--dry-run`.

Use a larger `--samples` count for an adoption decision. The default 100
samples are a smoke comparison. Seed and batch size are identical on both
sides. Losses remain visible, including their full reason text; a run with
no completed comparisons is refused. A verdict change is evidence for
investigation, not automatically a regression or an upstream fix.

The report includes observation changes even when the verdict is unchanged.
This matters for signal-writing samples because their verdict compares only
JS and reference. The five direct probes additionally require Rust to panic
with the signal-write class and require JS and reference to produce unit and
the expected final signal value for `set`, `toggle`, `increment`, `decrement`
and `push_str`. A changed taxonomy or broken adapter stops the comparison.
Inspect its retained probe logs before changing the oracle's assumptions.

The report's probe line repeats what the probe printed. The runner reads the
retained probe log of each side and requires one line per writer and the
probe's own summary line. A probe that exits 0 without them stops the run.

Each side has its own `oracle` and `topcoat` sibling directories. The
pipeline's Rust dependency paths are fixed relative paths, while its
`--clone` option selects the JS sources and provenance. The isolated layout
ensures that both product legs use the same revision. The executions share
only a serialized Rust build cache.

The output retains journals, model traces, probe captures, logs, the report
and a completion receipt with source, executable and artifact fingerprints.
Both traces must pass M32 correspondence. Sample identity, header revisions,
row counts and contiguous indices are checked before comparison. Repeating
the identical command checks completed evidence and returns the same report
bytes. Changed artifacts, changed producers and incomplete output directories
are refused. Use a fresh directory to earn new evidence.

## Adopt after reviewing the evidence

The candidate pin proposal is a review artifact. Adoption requires a separate
change to the maintained pin and its expected behavior:

1. Inspect every changed verdict, observation and loss. Minimize newly
   unexplained divergences and review the five signal-write results.
2. Move the maintained sibling Topcoat checkout to the reviewed full SHA.
   Update the target declaration in `DESIGN.md` and the active pin guards in
   `m30_verdict.sh`, `m31_verdict.sh` and `m33_gate.sh`.
3. Recheck grammar support, browser source imports, Rust toolchain needs,
   the JS package lock and the citations in `core/known.ml`. Recompute any
   changed hand-derived gate expectations from the actual semantics. Do not
   excuse a divergence merely to restore green.
4. Run the complete gate ladder. M34 and M35 check retained original producer
   bytes for historical archives and still perform live semantic replay.
   Changed replay semantics may require a new archive; live production always
   requires matching current source fingerprints and fresh evidence. Recheck
   the Signal Debug envelope used for identity, which fails closed on drift.
   Keep old provenance truthful; never globally replace historical SHAs.
5. Record the comparison and renewed evidence, then stage the reviewed
   changes for the user's commit.

`./m36_gate.sh` runs the regression controls, executes a fresh same-SHA
comparison, and repeats the identical command to exercise the reuse path. The
reuse tooth is the receipt check. The second command rebuilds the request,
recomputes the digest of every retained file and rechecks both isolated
clones before it returns the stored report. The `cmp` of the two reports
records that outcome. The `cmp` cannot fail alone, because a changed request
or a changed artifact stops the second command before it prints anything.

The gate then repeats the comparison with the M28 reference plant on the
candidate leg run only. That planted run must change at least one verdict or
one observation. It is the gate's negative control with the real legs.
`m36_gate.sh` is also part of `./gates.sh`.
