#!/bin/zsh
set -e
ROOT="${0:A:h}"
# The switch selection is FATAL.  eval "$(opam env --switch=absent ...)" runs
# eval on an empty string and returns 0, so set -e cannot see a missing switch
# and every rung below would build under whatever switch the caller exported.
# Name the switch, prove it exists, then select it. Every gate uses the same
# switch, including when invoked independently of this ladder.
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "gates: RED opam switch $SWITCH is not installed"
  exit 1
}
TCO_OPAM_ENV=$(opam env --switch=$SWITCH --set-switch) || exit 1
eval "$TCO_OPAM_ENV"
dune build --root "$ROOT" @all
dune runtest --root "$ROOT" --force
"$ROOT/_build/default/model/check.exe"
zxlint --errors-only "$ROOT"/core/*.ml
"$ROOT/m20_gate.sh"
"$ROOT/m22_gate.sh"
"$ROOT/m23_gate.sh"
"$ROOT/m24_gate.sh"
"$ROOT/m25_gate.sh"
"$ROOT/m26_gate.sh"
"$ROOT/m27_gate.sh"
"$ROOT/m28_gate.sh"
"$ROOT/m29_gate.sh"
"$ROOT/m30_gate.sh"
"$ROOT/m31_gate.sh"
"$ROOT/m32_gate.sh"
"$ROOT/m33_gate.sh"
"$ROOT/m34_gate.sh"
"$ROOT/m35_gate.sh"
"$ROOT/m36_gate.sh"
python3 -P -m unittest discover -s "$ROOT/test" -p test_gate_switch.py
"$ROOT/m37_gate.sh"
echo "GATES GREEN"
