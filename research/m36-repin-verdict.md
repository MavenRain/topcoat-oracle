# M36 validation, 2026-09-07

The re-pin workflow was exercised with real Rust, JS and reference legs.
The maintained Topcoat checkout remained clean at
`51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a`.

| Comparison | Samples per side | Verdict changes | Observation changes |
| --- | ---: | ---: | ---: |
| Current SHA against an isolated copy of itself | 100 | 0 | 0 |
| Current SHA against parent `38c07bebe5313a48e3d3c50b9797b931b62d0b99` | 100 | 0 | 0 |

The raw evidence of the first row is retained under `_emit/m36/`. The raw
evidence of the parent row was produced in a scratch work tree outside this
repository and is not retained here. Only the numbers in its row above were
copied from that report.

The session that reviewed this slice measured the same 100-sample request
against the maintained checkout, without the isolated snapshot. Its census
was identical to the isolated census below, so the snapshot reaches the same
producers. That measurement is also recorded outside this repository.

Both comparisons used seed `0x4d3336`, batch size 100 and no plant. Every
side retained all 100 rows: 9 agreements, 6 divergences and 85 leg failures.
The losses were 81 signal-arity failures, 2 JS syntax errors involving
`while`, and 2 skipped cases without JS. These are smoke comparisons with
15 adjudicated samples per side, not evidence of conformance over the full
generated stream. Reusing the completed same-SHA run returned identical
report bytes after verifying its receipt and artifacts. That verification is
the reuse tooth, not the byte comparison of the two reports. A changed
request or a changed artifact stops the second command before it prints.

The standalone `m36_gate.sh` also passed in the maintained oracle repository:
11 Python test groups, 9 OCaml validator checks, two fresh 100-sample runs,
both five-writer probe batches and byte-identical checked reuse. Its exit
code was 0 and its final line was `M36 GATE GREEN`.

That gate run measured the script as it stood before the review of this
slice. The review added two steps: a floor of 15 adjudicated rows per side
for the two dry-runs, and a planted negative control that compares the same
SHA with the M28 reference plant on the candidate leg run alone. No run of
the extended script is recorded here.

All five direct writer probes passed on both revisions. Rust produced the
signal-write panic for each method. JS and reference returned unit and the
hand-derived final signal state for set, toggle, increment, decrement and
push_str.

Additional checks passed:

- Eleven Python regression-test groups, including changed observations with
  unchanged verdicts, identity mismatches, truncated evidence, all-loss runs,
  subprocess failures, producer and artifact tampering, and changed requests.
- Nine OCaml probe-validator checks and the existing OCaml unit suite.
- M34 replay of the 5,000-sample campaign and its corruption controls.
- M35 replay and exact mapping of all 103 minimized repros.

The complete legacy ladder was started and passed M20 through M30. It was
intentionally stopped during M31 after inspection showed that M32 reruns
M31 and M33 reruns M32, repeating the unchanged campaign checks. No gate
script was weakened, and no full-ladder success is claimed here. The M36
gate remains registered in `gates.sh` for a complete release run.
