#!/bin/zsh
# M26 three-leg gate (DESIGN.md M26).  Runs bin/m26.exe over the JSONL
# the rust leg wrote moments earlier in the same ladder run, spawns the
# node driver over that SAME file, evaluates every seed case in
# core/interp.ml, and prints three observations per case: R for the
# rust leg, J for the js leg, F for the reference leg.
# m26_verdict.sh adjudicates the printed table.  Standalone-invocable
# so the mutation teeth can run just this step.
#
# Three steps:
#   0. Prerequisites, each red with a named reason and a named repair:
#      node, the node version, the pinned @maverick-js/signals under
#      driver-js, the topcoat clone, the m24 seed JSONL, the m25
#      expectation, and the built CLI.
#   1. Clear and recreate the out directory, then run the CLI.  A stale
#      table.txt would turn a run that wrote nothing into a vacuous
#      green.
#   2. The M20 no-regression sha.
#
# Both inputs are LIVE.  m24_gate.sh clears its own out directory and
# writes _emit/m24/out/seed.jsonl with THIS run's Signal uuids, and
# m25_verdict.sh writes _emit/m25/out/seed.js.expected.  Neither is a
# checked-in fixture, so this gate cannot run standalone without those
# two gates, and each one is named when its output is missing.
#
# The run is bare, never through a ledger wrapper: stdout IS the
# artifact and a replayed verdict would hand the verdict script an
# empty capture.
#
# The 36 printed lines are compared byte for byte with a HAND-DERIVED
# table (spec section 8), computed from the wire and from
# core/interp.ml and never from the program.  Regenerating that table
# from the program destroys the gate.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
cd "$ROOT"

# Step 0: prerequisites.
if ! command -v node > /dev/null 2>&1; then
  echo "M26 GATE RED: node missing from PATH" >&2
  exit 1
fi
NODE_VERSION=$(node --version)
# Numeric major and minor, never a string compare: v23.9.0 is red and
# v24.0.0 is green.
NODE_OK=$(print -r -- "$NODE_VERSION" |
  awk -F '[v.]' '{ if ($2 > 23 || ($2 == 23 && $3 >= 10)) print "ok" }')
if [ "$NODE_OK" != "ok" ]; then
  echo "M26 GATE RED: node $NODE_VERSION is below v23.10.0, which is the first version whose --experimental-transform-types loads the clone TypeScript" >&2
  exit 1
fi
if [ ! -f "$ROOT/driver-js/node_modules/@maverick-js/signals/package.json" ]; then
  echo "M26 GATE RED: @maverick-js/signals missing under driver-js/node_modules (npm --prefix driver-js ci); this needs network access once" >&2
  exit 1
fi
if [ ! -f "$ROOT/../topcoat/crates/topcoat-runtime/browser/src/context.ts" ]; then
  echo "M26 GATE RED: topcoat clone missing at $ROOT/../topcoat (the driver imports its browser surrogate sources in place); this is a prerequisite, not a skip" >&2
  exit 1
fi
if [ ! -s "$ROOT/_emit/m24/out/seed.jsonl" ]; then
  echo "M26 GATE RED: _emit/m24/out/seed.jsonl missing or empty; m24_gate.sh writes it and is the prerequisite for this gate" >&2
  exit 1
fi
if [ ! -s "$ROOT/_emit/m25/out/seed.js.expected" ]; then
  echo "M26 GATE RED: _emit/m25/out/seed.js.expected missing or empty; m25_gate.sh writes it and is the prerequisite for this gate" >&2
  exit 1
fi
dune build --root "$ROOT" bin/m26.exe
if [ ! -x "$ROOT/_build/default/bin/m26.exe" ]; then
  echo "M26 GATE RED: _build/default/bin/m26.exe missing after the build" >&2
  exit 1
fi

# Step 1: the out directory, cleared and recreated, then the run.
OUT="$ROOT/_emit/m26/out"
rm -rf "$OUT"
mkdir -p "$OUT"

set +e
M26_ROOT="$ROOT" "$ROOT/_build/default/bin/m26.exe" seeds \
  "$ROOT/_emit/m24/out/seed.jsonl" "$OUT" \
  --clone "$ROOT/../topcoat" --root "$ROOT" \
  > "$OUT/table.txt" 2> "$OUT/cli.err"
CLI_EXIT=$?
set -e

# Step 2: the M20 no-regression sha.
dune build --root "$ROOT" bin/emit_m20.exe
"$ROOT/_build/default/bin/emit_m20.exe" batch src/lib.rs |
  shasum -a 256 | awk '{ print $1 }' > "$OUT/m20.sha"

echo "M26 table: $OUT/table.txt"
echo "M26 stderr: $OUT/cli.err"
echo "M26 JSONL: $OUT/seed.js.jsonl"

"$ROOT/m26_verdict.sh" "$OUT" "$CLI_EXIT"
