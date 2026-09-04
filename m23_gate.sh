#!/bin/zsh
# M23 rust-leg driver gate (DESIGN.md M23).  Emits the two driver
# crates, copies driver-rs/harness.rs in as src/harness.rs, runs both
# with the pinned toolchain and adjudicates the JSONL with
# m23_verdict.sh.  Standalone-invocable so the mutation teeth can run
# just this step.
#
# Six steps:
#   0. Prerequisites, each red with a named reason: the topcoat clone,
#      the pinned toolchain, and the harness template.
#   1. Build the emitter.
#   2. The SEED vector.  Its last case spins forever, so exit 3 is the
#      expected code and the timeout is under test, not tolerated.
#   2b. The harness unit tests, through the seed crate.  They pin the
#      JS body check, whose only failure mode is answering true too
#      often, which no JSONL comparison would ever show.
#   3. The DRAWN batch of 300.  A case that spins costs one exit 3;
#      the gate resumes at the next index, up to 20 times, and counts
#      the no_terminate lines instead of going red on them.
#   4. The M20 no-regression sha.
#
# Every run keeps its JSONL under _emit/m23/out/, which is gitignored.
#
# The harness is COPIED, never emitted, so the file rustc compiles is
# the file in the repo, byte for byte.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
cd "$ROOT"

# Step 0: prerequisites.
if [ ! -d "$ROOT/../topcoat/crates/topcoat-runtime" ]; then
  echo "M23 GATE RED: topcoat clone missing at $ROOT/../topcoat (the driver crates path-dep it); this is a prerequisite, not a skip" >&2
  exit 1
fi
if ! cargo +nightly-2026-06-22 --version > /dev/null 2>&1; then
  echo "M23 GATE RED: toolchain nightly-2026-06-22 missing (rustup toolchain install nightly-2026-06-22)" >&2
  exit 1
fi
if [ ! -f "$ROOT/driver-rs/harness.rs" ]; then
  echo "M23 GATE RED: driver-rs/harness.rs missing; the emitted crates have no harness to compile" >&2
  exit 1
fi

# The run outputs are KEPT, under the gitignored _emit tree, so a red
# run can be read afterwards without a rerun.  The directory is cleared
# first: a stale seed.jsonl from an earlier run would turn a run that
# wrote nothing into a vacuous green.
OUT="$ROOT/_emit/m23/out"
rm -rf "$OUT"
mkdir -p "$OUT"

# Step 1: the emitter.
dune build --root "$ROOT" bin/emit_m23.exe
EXE="$ROOT/_build/default/bin/emit_m23.exe"

# Step 2: the seed vector.  The crate directory stays in the repo under
# the _emit ignore rule, so a red run leaves the exact source rustc saw.
SEED="$ROOT/_emit/m23seed"
mkdir -p "$SEED/src"
"$EXE" seed Cargo.toml > "$SEED/Cargo.toml"
"$EXE" seed src/main.rs > "$SEED/src/main.rs"
cp "$ROOT/driver-rs/harness.rs" "$SEED/src/harness.rs"
# NOT through gateledger.  The ledger caches a compile-only VERDICT and
# replays a hit with no stdout;  here stdout IS the artifact, so a hit
# would hand the verdict script an empty capture.  The two run steps
# below are therefore bare cargo.
set +e
cargo +nightly-2026-06-22 run --quiet \
  --manifest-path _emit/m23seed/Cargo.toml \
  --target-dir research/probes-rs/exprmac/target \
  -j 2 > "$OUT/seed.jsonl" 2> "$OUT/seed.err"
SEED_EXIT=$?
set -e

# Step 2b: the harness unit tests.  driver-rs/harness.rs carries a
# cfg(test) module for the JS body check, and the seed crate is the one
# place that compiles the template, so this is where they run.  A body
# check that agrees too easily stops reporting instead of failing, so
# every test there has a negative that must be rejected.  Bare cargo,
# for the same reason as the two run steps: this gate has to stand on
# its own with nothing but rustup and dune, and a ledger that replays a
# recorded verdict would make a mutation tooth's green unfalsifiable.
set +e
cargo +nightly-2026-06-22 test --quiet \
  --manifest-path _emit/m23seed/Cargo.toml \
  --target-dir research/probes-rs/exprmac/target \
  -j 2 > "$OUT/unit.log" 2>&1
UNIT_EXIT=$?
set -e
if [ "$UNIT_EXIT" -ne 0 ]; then
  echo "M23 GATE RED: the harness unit tests exited $UNIT_EXIT (log $OUT/unit.log)" >&2
  tail -30 "$OUT/unit.log" >&2
  exit 1
fi

# Step 3: the drawn batch of 300 at seed 0x4d3233.
BATCH="$ROOT/_emit/m23"
mkdir -p "$BATCH/src"
"$EXE" batch Cargo.toml > "$BATCH/Cargo.toml"
"$EXE" batch src/main.rs > "$BATCH/src/main.rs"
"$EXE" batch count > "$OUT/batch.count"
cp "$ROOT/driver-rs/harness.rs" "$BATCH/src/harness.rs"
set +e
cargo +nightly-2026-06-22 run --quiet \
  --manifest-path _emit/m23/Cargo.toml \
  --target-dir research/probes-rs/exprmac/target \
  -j 2 -- --timeout-ms 2000 > "$OUT/batch.jsonl" 2> "$OUT/batch.err"
BATCH_EXIT=$?
set -e

# The resume loop.  A no_terminate line is data, not a failure: the
# process exits 3 after writing it, and the gate restarts the already
# built binary at the next index.  Resuming through cargo would spend a
# cargo invocation per spinning case, so the binary is run directly.
BIN="$ROOT/research/probes-rs/exprmac/target/debug/m23batch"
RESUMES=0
if [ "$BATCH_EXIT" -eq 3 ] && [ ! -x "$BIN" ]; then
  echo "M23 GATE RED: the batch binary is missing at $BIN, so the batch cannot be resumed past its first no_terminate case" >&2
  exit 1
fi
set +e
while [ "$BATCH_EXIT" -eq 3 ] && [ "$RESUMES" -lt 20 ]; do
  NEXT=$(( $(tail -n 1 "$OUT/batch.jsonl" | sd '^\{"case":([0-9]+),.*$' '$1') + 1 ))
  RESUMES=$(( RESUMES + 1 ))
  "$BIN" --timeout-ms 2000 --from "$NEXT" >> "$OUT/batch.jsonl" 2>> "$OUT/batch.err"
  BATCH_EXIT=$?
done
set -e

# Step 4: the M20 no-regression sha.
dune build --root "$ROOT" bin/emit_m20.exe
"$ROOT/_build/default/bin/emit_m20.exe" batch src/lib.rs |
  shasum -a 256 | awk '{ print $1 }' > "$OUT/m20.sha"

echo "M23 seed JSONL:  $OUT/seed.jsonl"
echo "M23 batch JSONL: $OUT/batch.jsonl"

"$ROOT/m23_verdict.sh" "$OUT" "$SEED_EXIT" "$BATCH_EXIT" "$RESUMES"
