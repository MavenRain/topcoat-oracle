#!/bin/zsh
# M20 printer-soundness gate (DESIGN.md M20): emit the 1k batch crate
# (seed 0x4d3230, m20 scope) plus the case_neg negative control,
# compile with the pinned toolchain, and adjudicate the log with
# m20_verdict.sh. Standalone-invocable so the mutation teeth can run
# just this step.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
cd "$ROOT"
if [ ! -d "$ROOT/../topcoat/crates/topcoat-runtime" ]; then
  echo "M20 GATE RED: topcoat clone missing at $ROOT/../topcoat (the batch crate path-deps it); this is a prerequisite, not a skip" >&2
  exit 1
fi
if ! cargo +nightly-2026-06-22 --version > /dev/null 2>&1; then
  echo "M20 GATE RED: toolchain nightly-2026-06-22 missing (rustup toolchain install nightly-2026-06-22)" >&2
  exit 1
fi
dune build --root "$ROOT" bin/emit_m20.exe
EXE="$ROOT/_build/default/bin/emit_m20.exe"
OUT="$ROOT/_emit/m20"
mkdir -p "$OUT/src"
"$EXE" batch Cargo.toml > "$OUT/Cargo.toml"
"$EXE" batch src/lib.rs > "$OUT/src/lib.rs"
"$EXE" batch case_neg.span > "$OUT/case_neg.span"
LOG="$ROOT/_emit/m20-check.log"
set +e
gateledger run -- cargo +nightly-2026-06-22 check \
  --manifest-path _emit/m20/Cargo.toml \
  --target-dir research/probes-rs/exprmac/target \
  -j 2 --message-format=short > "$LOG" 2>&1
CARGO_EXIT=$?
set -e
"$ROOT/m20_verdict.sh" "$LOG" "$OUT/case_neg.span" "$CARGO_EXIT"
