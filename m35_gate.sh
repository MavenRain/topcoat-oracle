#!/bin/zsh
set -e
ROOT=${0:A:h}
cd "$ROOT"
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "m35_gate: RED opam switch $SWITCH is not installed"
  exit 1
}
eval "$(opam env --switch=$SWITCH --set-switch)"
dune build bin/m35.exe
python3 ./m35_verdict.py check "$ROOT"
