#!/bin/zsh
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
dune build --root "$ROOT" @all
dune runtest --root "$ROOT" --force
"$ROOT/_build/default/model/check.exe"
zxlint --errors-only "$ROOT"/core/*.ml
"$ROOT/m20_gate.sh"
"$ROOT/m22_gate.sh"
"$ROOT/m23_gate.sh"
"$ROOT/m24_gate.sh"
"$ROOT/m25_gate.sh"
echo "GATES GREEN"
