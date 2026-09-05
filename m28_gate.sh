#!/bin/zsh
# M28 planted-oracle gate (DESIGN.md M28).  Runs the M27 CLI THREE
# times over the same m24 capture: once with a planted reference leg,
# once with a planted js leg, and once with no plant at all.  The first
# two must show the differ catching a bug it has never seen.  The third
# must reproduce the M27 table byte for byte, which is what "restore
# green" means here.
#
# The plants are selected at RUN TIME by one flag.  Nothing on disk is
# mutated, nothing is rebuilt inside this gate and there is no restore
# step, because there is nothing to restore.  A gate that edits a
# source file, rebuilds and edits it back leaves a window in which a
# crash, a signal or a parallel builder leaves the tree mutated, and
# the "restore" compare then passes against the mutated tree.  Run-time
# selection has no such window.
#
# Two steps:
#   0. Prerequisites, each red with a named reason and a named repair:
#      the built m27.exe, the m24 seed JSONL, the m27 table (and it
#      must be NEWER than m27.exe, or it came from another binary),
#      the built emit_m20.exe, the driver, and the topcoat clone.
#   1. Clear and recreate the out directory, then the three runs.
#
# This gate NEVER builds.  m27_gate.sh runs one line earlier in
# gates.sh and builds both executables;  if the table is older than the
# binary, the ladder was not run in order and the compare in check 4
# would be vacuous.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
cd "$ROOT"

REF_PLANT="ref:display_sign"
JS_PLANT="js:signal_get_plus_one"

# Step 0: prerequisites.
if [ ! -x "$ROOT/_build/default/bin/m27.exe" ]; then
  echo "M28 GATE RED: _build/default/bin/m27.exe missing; m27_gate.sh builds it and runs one line earlier in gates.sh" >&2
  exit 1
fi
if [ ! -x "$ROOT/_build/default/bin/emit_m20.exe" ]; then
  echo "M28 GATE RED: _build/default/bin/emit_m20.exe missing; m27_gate.sh builds it and runs one line earlier in gates.sh" >&2
  exit 1
fi
if [ ! -s "$ROOT/_emit/m24/out/seed.jsonl" ]; then
  echo "M28 GATE RED: _emit/m24/out/seed.jsonl missing or empty; m24_gate.sh writes it and is the prerequisite for this gate" >&2
  exit 1
fi
if [ ! -s "$ROOT/_emit/m27/out/table.txt" ]; then
  echo "M28 GATE RED: _emit/m27/out/table.txt missing or empty; m27_gate.sh writes it and is the prerequisite for this gate" >&2
  exit 1
fi
if [ ! "$ROOT/_emit/m27/out/table.txt" -nt "$ROOT/_build/default/bin/m27.exe" ]; then
  echo "M28 GATE RED: _emit/m27/out/table.txt is older than bin/m27.exe, so it was printed by a different binary; run gates.sh in order" >&2
  exit 1
fi
if [ ! -f "$ROOT/driver-js/driver.mjs" ]; then
  echo "M28 GATE RED: driver-js/driver.mjs missing; the js leg cannot run" >&2
  exit 1
fi
if [ ! -f "$ROOT/../topcoat/crates/topcoat-runtime/browser/src/context.ts" ]; then
  echo "M28 GATE RED: topcoat clone missing at $ROOT/../topcoat (the driver imports its browser surrogate sources in place); this is a prerequisite, not a skip" >&2
  exit 1
fi

# Step 1: the out directory, cleared and recreated, then the three
# runs.  A stale table.txt would turn a run that wrote nothing into a
# vacuous green, so the directory is removed and not overwritten.
OUT="$ROOT/_emit/m28/out"
rm -rf "$OUT"
mkdir -p "$OUT/ref" "$OUT/js" "$OUT/none"

run_leg () {
  # $1 the sub-directory, $2.. the extra flags
  local sub="$1"
  shift
  set +e
  M27_ROOT="$ROOT" "$ROOT/_build/default/bin/m27.exe" seeds \
    "$ROOT/_emit/m24/out/seed.jsonl" "$OUT/$sub" \
    --clone "$ROOT/../topcoat" --root "$ROOT" "$@" \
    > "$OUT/$sub/table.txt" 2> "$OUT/$sub/cli.err"
  print -r -- "$?" > "$OUT/$sub/exit"
  set -e
}

run_leg ref --plant "$REF_PLANT"
run_leg js --plant "$JS_PLANT"
run_leg none

# The M20 no-regression sha, computed from the already-built emitter.
"$ROOT/_build/default/bin/emit_m20.exe" batch src/lib.rs |
  shasum -a 256 | awk '{ print $1 }' > "$OUT/m20.sha"

echo "M28 ref table: $OUT/ref/table.txt"
echo "M28 js table: $OUT/js/table.txt"
echo "M28 none table: $OUT/none/table.txt"

"$ROOT/m28_verdict.sh" "$OUT"
