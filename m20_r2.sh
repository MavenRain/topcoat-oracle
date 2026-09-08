#!/bin/zsh
# M20 round-2 probe run: build the emitter, write the probe crate,
# compile it against the pinned topcoat clone. The cargo exit code is
# recorded, not fatal: probes are EXPECTED to contain rejects.
set -e
ROOT="${0:A:h}"
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "m20_r2: RED opam switch $SWITCH is not installed"
  exit 1
}
if ! TCO_OPAM_ENV=$(opam env --switch="$SWITCH" --set-switch); then
  print -r -- "m20_r2: RED could not load opam switch $SWITCH"
  exit 1
fi
eval "$TCO_OPAM_ENV"
unset TCO_OPAM_ENV
cd "$ROOT"
dune build --root "$ROOT" bin/emit_m20.exe
EXE="$ROOT/_build/default/bin/emit_m20.exe"
OUT="$ROOT/research/probes-rs/m20r2"
mkdir -p "$OUT/src"
"$EXE" r2 Cargo.toml > "$OUT/Cargo.toml"
"$EXE" r2 src/lib.rs > "$OUT/src/lib.rs"
LOG="$ROOT/research/probes-rs/m20r2/check.log"
set +e
gateledger run -- cargo +nightly-2026-06-22 check \
  --manifest-path research/probes-rs/m20r2/Cargo.toml \
  --target-dir research/probes-rs/exprmac/target \
  -j 2 --message-format=short > "$LOG" 2>&1
echo "cargo-exit $?" >> "$LOG"
echo "log: $LOG"
