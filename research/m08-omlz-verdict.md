# M08 verdict: omlz dual-gate probe (2026-08-27)

Recorded verdict: **omlz check is DEGRADED to inactive for core/.**
The enforced dual gate is dune + zxlint (`gates.sh`); `omlz check`
cannot gate the real multi-module core today. Two independent
toolchain blockers, both reproduced minimally under
`research/probes/` (probe sources with `.stdout`/`.stderr` captures
alongside):

## Blocker A: no multi-file story

- `open Prelude` (sibling-file open, the one documented ZxCaml module
  mechanism, ADR-016) is accepted by the frontend and then crashes
  Core IR lowering with an internal panic: the literal bytes
  `UnsupportedNode ... lower Core IR:` with no diagnostic code, no
  location, nothing after the colon (`m11_open_unused.ml`,
  `m04_open_only.ml` — the open crashes even when unused).
- Qualified access without open (`Prelude.len`) fails differently:
  `Unbound module "Prelude"`, exit 2.
- `open Option` (bundled stdlib) is cleanly rejected up front with
  E0103 "use qualified access" — the sibling-open crash is therefore
  an omlz bug, not a subset rule.

## Blocker B: cross-function tuple projection from a cons-match

A top-level function that matches `kv :: rest` and projects `fst kv`
/ `snd kv` (or `let (a, b) = kv`), called from another function,
crashes lowering (`UnsupportedNode`, or `UnsupportedPattern` for the
let-destructure form) even with zero recursion, zero Option, zero
open (`n_e1_nonrec_cons_fst.ml`, `n_g2_cons_let_destructure.ml`,
`n_b3_assoc_only.ml` = prelude's `assoc_opt` in isolation). The
identical logic inlined directly in `entrypoint` passes
(`n_g1_let_cons_fst.ml`). This is exactly the shape of `assoc_opt`,
which the wf/interp environment needs, so even a concatenate-all-
of-core-into-one-file gate script would crash on it.

## What IS positively verified

`probe_selfcontained.ml` (single file, entrypoint, no open): the
seven prelude combinators `nth_opt`, `div_opt`, `fold`, `map`, `len`,
`rev`, `append` plus `Option.fold ~none ~some` consumption pass
`omlz check` exit 0 and zxlint exit 0. Also confirmed rejected by the
subset on the way (now avoided throughout core/): tuple pattern
nested in a cons pattern, `()` parameter patterns (Tpat_construct,
E0092 — core uses `fun _ ->` for thunk-shaped closures).

## Gate consequences

- `gates.sh` runs `zxlint --errors-only core/*.ml` (wired, M08) and
  the dune build; that pair is the enforced dual gate for core/.
- M09/M16 "(+ omlz check when active)" resolves to INACTIVE with this
  file as the recorded evidence.
- Re-probe trigger: an omlz release that fixes sibling `open` or the
  cons-match tuple projection; re-run
  `omlz-run.sh check research/probes/probe_prelude.ml` (the failing
  multi-file exhibit kept on purpose) and
  `probe_selfcontained.ml`.

omlz pin at probe time: omlz 0.1.0 via
`~/Documents/claude1/zxcaml-bench/omlz-run.sh` (switch zxcaml-p1).
