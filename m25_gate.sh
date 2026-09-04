#!/bin/zsh
# M25 js-leg gate (DESIGN.md M25).  Runs the node leg over the JSONL
# the rust leg wrote moments earlier in the same ladder run.
# driver-js/driver.mjs evaluates the JS half of every wire line against
# the target's own browser surrogates, loaded IN PLACE from the topcoat
# clone by node's type transform plus a resolve hook, and writes one
# JSONL line per case.  m25_verdict.sh adjudicates that file.
# Standalone-invocable so the mutation teeth can run just this step.
#
# Four steps:
#   0. Prerequisites, each red with a named reason and a named repair:
#      node, the node version, the pinned @maverick-js/signals under
#      driver-js, the topcoat clone, and the m24 seed JSONL.
#   1. The driver-js unit tests, through the package script.
#   2. Clear and recreate the out directory, then run the driver.  A
#      stale output would turn a run that wrote nothing into a vacuous
#      green.
#   3. The M20 no-regression sha.
#
# The input is the LIVE _emit/m24/out/seed.jsonl.  m24_gate.sh clears
# that directory at its own step 2, so the seed on disk carries THIS
# run's Signal uuids.  A stale file from an earlier run would name
# uuids that no registry we seed can hold, and every signal case would
# go red for the wrong reason.  m25_gate.sh therefore cannot run
# standalone without m24_gate.sh, and that is intended.
#
# The driver writes straight into the out directory and the verdict
# runs on that file, so there is no copy step to fail before the
# verdict can name what is missing.
#
# The run is bare, never through a ledger wrapper: the output file and
# the stderr sidecar are the artifacts, and a replayed verdict would
# hand the verdict script an empty capture.
#
# The twelve lines are compared byte for byte with a HAND-DERIVED table
# (spec section 7), so the driver is checked against a table it did not
# produce.  Regenerating that table from the driver destroys the gate.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
cd "$ROOT"

# Step 0: prerequisites.
if ! command -v node > /dev/null 2>&1; then
  echo "M25 GATE RED: node missing from PATH" >&2
  exit 1
fi
NODE_VERSION=$(node --version)
# Numeric major and minor, never a string compare: v23.9.0 is red and
# v24.0.0 is green.
NODE_OK=$(print -r -- "$NODE_VERSION" |
  awk -F '[v.]' '{ if ($2 > 23 || ($2 == 23 && $3 >= 10)) print "ok" }')
if [ "$NODE_OK" != "ok" ]; then
  echo "M25 GATE RED: node $NODE_VERSION is below v23.10.0, which is the first version whose --experimental-transform-types loads the clone TypeScript" >&2
  exit 1
fi
if [ ! -f "$ROOT/driver-js/node_modules/@maverick-js/signals/package.json" ]; then
  echo "M25 GATE RED: @maverick-js/signals missing under driver-js/node_modules (npm --prefix driver-js ci); this needs network access once" >&2
  exit 1
fi
if [ ! -f "$ROOT/../topcoat/crates/topcoat-runtime/browser/src/context.ts" ]; then
  echo "M25 GATE RED: topcoat clone missing at $ROOT/../topcoat (the driver imports its browser surrogate sources in place); this is a prerequisite, not a skip" >&2
  exit 1
fi
if [ ! -s "$ROOT/_emit/m24/out/seed.jsonl" ]; then
  echo "M25 GATE RED: _emit/m24/out/seed.jsonl missing or empty; m24_gate.sh writes it and is the prerequisite for this gate" >&2
  exit 1
fi

# Step 1: the unit tests.  The script is asserted first, so the gate
# cannot be softened by editing package.json.
if ! rg -Fq -- '"test": "node --test test/*.test.mjs"' "$ROOT/driver-js/package.json"; then
  echo "M25 GATE RED: driver-js/package.json .scripts.test is not the pinned command" >&2
  exit 1
fi
npm --prefix "$ROOT/driver-js" test

# Step 2: the out directory, cleared and recreated, then the run.
OUT="$ROOT/_emit/m25/out"
rm -rf "$OUT"
mkdir -p "$OUT"

set +e
node --experimental-transform-types \
  --import "$ROOT/driver-js/loader.mjs" \
  "$ROOT/driver-js/driver.mjs" \
  --in "$ROOT/_emit/m24/out/seed.jsonl" \
  --out "$OUT/seed.js.jsonl" \
  --clone "$ROOT/../topcoat" \
  2> "$OUT/seed.js.err"
CLI_EXIT=$?
set -e

# Step 3: the M20 no-regression sha.
dune build --root "$ROOT" bin/emit_m20.exe
"$ROOT/_build/default/bin/emit_m20.exe" batch src/lib.rs |
  shasum -a 256 | awk '{ print $1 }' > "$OUT/m20.sha"

echo "M25 JSONL: $OUT/seed.js.jsonl"
echo "M25 stderr: $OUT/seed.js.err"

"$ROOT/m25_verdict.sh" "$OUT" "$CLI_EXIT"
