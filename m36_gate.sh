#!/bin/zsh
# Fresh same-SHA measurements followed by checked, byte-identical reuse.
# The floor of 15 adjudicated rows per side is the count this request produced
# on 2026-09-07: 9 agreements and 6 divergences of 100 samples.  A JS or Rust
# driver regression that turns comparisons into leg failures fails the floor
# instead of leaving a green comparison of almost nothing.  The planted control
# below keeps the default floor of 1, because a plant may change which rows
# adjudicate.
set -e
ROOT=${0:A:h}
cd "$ROOT"
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "M36 GATE RED: opam switch $SWITCH is not installed" >&2
  exit 1
}
TCO_OPAM_ENV=$(opam env --switch=$SWITCH --set-switch) || exit 1
eval "$TCO_OPAM_ENV"
dune build bin/m31.exe bin/m32.exe m36/probe.exe
dune runtest m36 --force
python3 -P test/test_m36_repin.py

CLONE=${M36_CLONE:-$ROOT/../topcoat}
REV=$(git -C "$CLONE" rev-parse HEAD)
mkdir -p "$ROOT/_emit/m36"
OUT=$(mktemp -d "$ROOT/_emit/m36/gate.XXXXXX")
python3 -P "$ROOT/m36_repin.py" --clone "$CLONE" --to "$REV" \
  --out "$OUT/comparison" --samples 100 --seed 0x4d3336 --batch 100 \
  --min-compared 15 --dry-run > "$OUT/first.txt"
python3 -P "$ROOT/m36_repin.py" --clone "$CLONE" --to "$REV" \
  --out "$OUT/comparison" --samples 100 --seed 0x4d3336 --batch 100 \
  --min-compared 15 --dry-run > "$OUT/second.txt"
cmp "$OUT/first.txt" "$OUT/second.txt"

# Negative control with the real legs.  The candidate leg run alone gets the
# M28 reference plant, which flips the sign of every float the reference leg
# displays.  This request renders a float in the reference cell of six of its
# 100 rows, one of them adjudicated (measured on the journal of the same
# request: rows 5, 12, 22, 52, 87 and 88, with row 52 an agreement), so the
# plant must move at least one verdict or one observation.  A null here means
# the comparison cannot see a changed leg, which makes the two dry-runs above
# vacuous.
python3 -P "$ROOT/m36_repin.py" --clone "$CLONE" --to "$REV" \
  --out "$OUT/planted" --samples 100 --seed 0x4d3336 --batch 100 \
  --plant-candidate ref:display_sign > "$OUT/planted.txt"
if rg -q -- '^m36 changed_verdicts 0 changed_observations 0 ' "$OUT/planted.txt"; then
  print -r -- "M36 GATE RED: the planted candidate leg changed no verdict and no observation" >&2
  exit 1
fi

cat "$OUT/first.txt"
print -r -- "M36 planted control: $(rg -N -- '^m36 changed_verdicts ' "$OUT/planted.txt")"
print -r -- "M36 GATE GREEN: fresh same-SHA comparison, five writers, planted negative control, idempotent checked reuse"
