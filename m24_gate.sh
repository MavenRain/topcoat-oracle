#!/bin/zsh
# M24 rust-leg gate (DESIGN.md M24).  Runs the OCaml rust leg end to
# end on the seed vector.  bin/m24.exe writes the crate under
# _emit/m24seed, copies driver-rs/harness.rs in as src/harness.rs, runs
# it with the pinned toolchain, resumes it past the case that spins,
# decodes the JSONL with core/wire.ml and prints one row per case.
# m24_verdict.sh adjudicates that table.  Standalone-invocable so the
# mutation teeth can run just this step.
#
# Five steps:
#   0. Prerequisites, each red with a named reason: the topcoat clone,
#      the pinned toolchain, and the harness template.
#   1. Build the CLI.
#   2. Clear and recreate BOTH directories.  A stale table or a stale
#      run.jsonl from an earlier run would turn a run that wrote
#      nothing into a vacuous green.
#   3. Run the CLI.  Bare, never through gateledger: stdout IS the
#      artifact here, and a replayed verdict would hand the verdict
#      script an empty capture.
#   4. The M20 no-regression sha.
#
# The CLI takes ONE directory argument, so the gate copies run.jsonl
# and run.err into _emit/m24/out/ afterwards.  Every artifact of the
# run then sits under that one gitignored directory for the reviewer.
#
# The decoded table is compared with a HAND-DERIVED expected table
# (spec section 7), so the parser is checked against a table it did not
# produce.  Regenerating that table from the parser destroys the gate.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
cd "$ROOT"

# Step 0: prerequisites.
if [ ! -d "$ROOT/../topcoat/crates/topcoat-runtime" ]; then
  echo "M24 GATE RED: topcoat clone missing at $ROOT/../topcoat (the seed crate path-deps it); this is a prerequisite, not a skip" >&2
  exit 1
fi
if ! cargo +nightly-2026-06-22 --version > /dev/null 2>&1; then
  echo "M24 GATE RED: toolchain nightly-2026-06-22 missing (rustup toolchain install nightly-2026-06-22)" >&2
  exit 1
fi
if [ ! -f "$ROOT/driver-rs/harness.rs" ]; then
  echo "M24 GATE RED: driver-rs/harness.rs missing; the emitted crate has no harness to compile" >&2
  exit 1
fi

# Step 1: the CLI.
dune build --root "$ROOT" bin/m24.exe

# Step 2: both directories, cleared and recreated.
OUT="$ROOT/_emit/m24/out"
SEED="$ROOT/_emit/m24seed"
rm -rf "$OUT" "$SEED"
mkdir -p "$OUT" "$SEED"

# Step 3: the run.  M24_ROOT is the explicit route to the repo root, so
# the CLI never falls back to deriving it from the out-dir.
set +e
M24_ROOT="$ROOT" "$ROOT/_build/default/bin/m24.exe" seeds "$SEED" \
  > "$OUT/table.txt" 2> "$OUT/cli.err"
CLI_EXIT=$?
set -e
cp "$SEED/run.jsonl" "$OUT/seed.jsonl"
cp "$SEED/run.err" "$OUT/seed.err"

# Step 4: the M20 no-regression sha.
dune build --root "$ROOT" bin/emit_m20.exe
"$ROOT/_build/default/bin/emit_m20.exe" batch src/lib.rs |
  shasum -a 256 | awk '{ print $1 }' > "$OUT/m20.sha"

echo "M24 table: $OUT/table.txt"
echo "M24 JSONL: $OUT/seed.jsonl"

"$ROOT/m24_verdict.sh" "$OUT" "$CLI_EXIT"
