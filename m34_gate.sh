#!/bin/zsh
# Replay the archived M34 campaign without starting a product leg. The archive
# is evidence from a real run; source fingerprints make stale evidence fail.
set -e
ROOT=${0:A:h}
cd "$ROOT"
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "m34_gate: RED opam switch $SWITCH is not installed"
  exit 1
}
eval "$(opam env --switch=$SWITCH --set-switch)"
OUT=_emit/m34/check
mkdir -p "$OUT"
dune build bin/m34.exe bin/m34_plants.exe
python3 ./m34_verdict.py prepare "$ROOT" "$OUT"
_build/default/bin/m34.exe report "$OUT/archive" > "$OUT/report.md"
_build/default/bin/m34.exe report "$OUT/archive" > "$OUT/replay.md"
cmp "$OUT/report.md" "$OUT/replay.md"
cmp "$OUT/report.md" research/campaign-1/report.md
python3 ./m34_verdict.py check "$ROOT" "$OUT"
print -r -- "M34 GATE GREEN: 5000 mixed samples, complete divergence membership, stable report, corruption controls rejected"
