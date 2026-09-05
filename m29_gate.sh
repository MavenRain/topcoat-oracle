#!/bin/zsh
# M29 minimizer gate (DESIGN.md M29).  Runs bin/m29.exe TWICE, once per
# plant, over the two cases of shell/m29_cases.ml.  Each run shrinks a
# planted divergence to a fixpoint and prints its whole walk;
# m29_verdict.sh reads the two printed walks.
#
# The gate NEVER edits a source file.  Both plants are selected at RUN
# TIME by one flag, exactly as the M28 gate selects them, so there is no
# mutation window and no restore step.
#
# The runs DO build crates: one per shrink round plus one for the start
# measurement plus one for the control, under _emit/m29/out/<plant>/,
# FOURTEEN in total: 5 rounds for the reference case plus 6 for the js
# case is 11 rounds entered, minus the ONE round that offers zero
# candidates and calls no leg (reference round 4), plus 2 start
# measurements and 2 controls (M29 spec section 12).  The program writes
# them;  this script only clears and creates the two plant directories.
#
# M28 residual R2, the shared preamble of the nine gate scripts, is out
# of M29 scope (M29 spec section 1.2), so the preamble below repeats the
# M28 one on purpose.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
cd "$ROOT"

CLONE="$ROOT/../topcoat"
OUT="$ROOT/_emit/m29/out"
REF_PLANT="ref:display_sign"
JS_PLANT="js:signal_get_plus_one"

red () { print -r -- "M29 GATE RED: $1"; exit 1; }

# 0.  Prerequisites, each with a named reason and a named repair.
[[ -x "$ROOT/_build/default/bin/m29.exe" ]] ||
  red "bin/m29.exe is not built; run: dune build bin/m29.exe"
[[ -x "$ROOT/_build/default/bin/emit_m20.exe" ]] ||
  red "bin/emit_m20.exe is not built; run: dune build bin/emit_m20.exe"
[[ -d "$CLONE" ]] ||
  red "the topcoat clone is missing at $CLONE; clone it beside this repo"
# The node driver entry file is driver-js/driver.mjs.  There is no
# driver-js/run.mjs.  m28_gate.sh:57 checks this same path, and
# Js_leg.default_config's driver_dir names the directory it sits in.
[[ -f "$ROOT/driver-js/driver.mjs" ]] ||
  red "the node driver is missing at driver-js/driver.mjs"
# The rust harness source is the path Rust_leg.default_config names:
# harness_src = root ^ "/driver-rs/harness.rs" (shell/rust_leg.ml:87).
# There is no rust-harness/ directory in this repo.
[[ -f "$ROOT/driver-rs/harness.rs" ]] ||
  red "the rust harness source is missing at driver-rs/harness.rs, which is what Rust_leg.default_config names"
command -v cargo > /dev/null ||
  red "cargo is not on PATH; the rust leg cannot run"
command -v node > /dev/null ||
  red "node is not on PATH; the js leg cannot run"

# 1.  A clean output tree.  A stale round directory must never be read
#     as a fresh one, so the whole tree goes first.
rm -rf "$OUT"
mkdir -p "$OUT/$REF_PLANT" "$OUT/$JS_PLANT"

# 2.  The two runs.  stdout is captured, stderr is left on the terminal,
#     and the exit code is recorded rather than trusted, so
#     m29_verdict.sh names a non-zero exit as its own check.
set +e
"$ROOT/_build/default/bin/m29.exe" minimize "$OUT/$REF_PLANT" \
  --plant "$REF_PLANT" --root "$ROOT" --clone "$CLONE" \
  > "$OUT/$REF_PLANT/stdout.txt"
print -r -- "$?" > "$OUT/$REF_PLANT/exit.txt"
"$ROOT/_build/default/bin/m29.exe" minimize "$OUT/$JS_PLANT" \
  --plant "$JS_PLANT" --root "$ROOT" --clone "$CLONE" \
  > "$OUT/$JS_PLANT/stdout.txt"
print -r -- "$?" > "$OUT/$JS_PLANT/exit.txt"
set -e

# 3.  The m20 sha, recorded here and checked in the verdict script, so
#     an M29 change that moves the M20 emitter is caught by this gate
#     too.
"$ROOT/_build/default/bin/emit_m20.exe" batch src/lib.rs | shasum -a 256 |
  awk '{ print $1 }' > "$OUT/m20.sha"

# 4.  The verdict.
"$ROOT/m29_verdict.sh" "$OUT"
