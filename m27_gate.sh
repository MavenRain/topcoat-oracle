#!/bin/zsh
# M27 verdict gate (DESIGN.md M27).  Runs bin/m27.exe over the JSONL
# the rust leg wrote moments earlier in the same ladder run, spawns the
# node driver over that SAME file, evaluates every seed case in
# core/interp.ml, and prints FOUR observations per case: R for the rust
# leg, J for the js leg, F for the reference leg, and V for the verdict
# core/differ.ml gives over those three cells.
# m27_verdict.sh adjudicates the printed table.  Standalone-invocable
# so the mutation teeth can run just this step.
#
# Three steps:
#   0. Prerequisites, each red with a named reason and a named repair:
#      node, the node version, the pinned @maverick-js/signals under
#      driver-js, the topcoat clone, the m24 seed JSONL, the m25
#      expectation, the m26 table, and the built CLI.
#   1. Clear and recreate the out directory, then run the CLI.  A stale
#      table.txt would turn a run that wrote nothing into a vacuous
#      green.
#   2. The M20 no-regression sha.
#
# All three inputs are LIVE.  m24_gate.sh clears its own out directory
# and writes _emit/m24/out/seed.jsonl with THIS run's Signal uuids,
# m25_verdict.sh writes _emit/m25/out/seed.js.expected, and
# m26_gate.sh writes _emit/m26/out/table.txt.  None is a checked-in
# fixture, so this gate cannot run standalone without those three
# gates, and each one is named when its output is missing.
#
# The run is bare, never through a ledger wrapper: stdout IS the
# artifact and a replayed verdict would hand the verdict script an
# empty capture.
#
# The 48 printed lines are compared byte for byte with a HAND-DERIVED
# table (spec section 7).  Its first 36 lines are the M26 table and its
# twelve V lines are walked by hand over the channels of spec section
# 3, never by running the program.  Regenerating either part from the
# program destroys the gate.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
cd "$ROOT"

# Step 0: prerequisites.
if ! command -v node > /dev/null 2>&1; then
  echo "M27 GATE RED: node missing from PATH" >&2
  exit 1
fi
NODE_VERSION=$(node --version)
# Numeric major and minor, never a string compare: v23.9.0 is red and
# v24.0.0 is green.
NODE_OK=$(print -r -- "$NODE_VERSION" |
  awk -F '[v.]' '{ if ($2 > 23 || ($2 == 23 && $3 >= 10)) print "ok" }')
if [ "$NODE_OK" != "ok" ]; then
  echo "M27 GATE RED: node $NODE_VERSION is below v23.10.0, which is the first version whose --experimental-transform-types loads the clone TypeScript" >&2
  exit 1
fi
if [ ! -f "$ROOT/driver-js/node_modules/@maverick-js/signals/package.json" ]; then
  echo "M27 GATE RED: @maverick-js/signals missing under driver-js/node_modules (npm --prefix driver-js ci); this needs network access once" >&2
  exit 1
fi
if [ ! -f "$ROOT/../topcoat/crates/topcoat-runtime/browser/src/context.ts" ]; then
  echo "M27 GATE RED: topcoat clone missing at $ROOT/../topcoat (the driver imports its browser surrogate sources in place); this is a prerequisite, not a skip" >&2
  exit 1
fi
if [ ! -s "$ROOT/_emit/m24/out/seed.jsonl" ]; then
  echo "M27 GATE RED: _emit/m24/out/seed.jsonl missing or empty; m24_gate.sh writes it and is the prerequisite for this gate" >&2
  exit 1
fi
if [ ! -s "$ROOT/_emit/m25/out/seed.js.expected" ]; then
  echo "M27 GATE RED: _emit/m25/out/seed.js.expected missing or empty; m25_gate.sh writes it and is the prerequisite for this gate" >&2
  exit 1
fi
if [ ! -s "$ROOT/_emit/m26/out/table.txt" ]; then
  echo "M27 GATE RED: _emit/m26/out/table.txt missing or empty; m26_gate.sh writes it and is the prerequisite for this gate" >&2
  exit 1
fi
dune build --root "$ROOT" bin/m27.exe
if [ ! -x "$ROOT/_build/default/bin/m27.exe" ]; then
  echo "M27 GATE RED: _build/default/bin/m27.exe missing after the build" >&2
  exit 1
fi

# Step 1: the out directory, cleared and recreated, then the run.
OUT="$ROOT/_emit/m27/out"
rm -rf "$OUT"
mkdir -p "$OUT"

set +e
M27_ROOT="$ROOT" "$ROOT/_build/default/bin/m27.exe" seeds \
  "$ROOT/_emit/m24/out/seed.jsonl" "$OUT" \
  --clone "$ROOT/../topcoat" --root "$ROOT" \
  > "$OUT/table.txt" 2> "$OUT/cli.err"
CLI_EXIT=$?
set -e

# Step 2: the M20 no-regression sha.
dune build --root "$ROOT" bin/emit_m20.exe
"$ROOT/_build/default/bin/emit_m20.exe" batch src/lib.rs |
  shasum -a 256 | awk '{ print $1 }' > "$OUT/m20.sha"

echo "M27 table: $OUT/table.txt"
echo "M27 stderr: $OUT/cli.err"
echo "M27 JSONL: $OUT/seed.js.jsonl"

"$ROOT/m27_verdict.sh" "$OUT" "$CLI_EXIT"
