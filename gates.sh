#!/bin/zsh
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
dune build --root "$ROOT" @all
dune runtest --root "$ROOT" --force
"$ROOT/_build/default/model/check.exe"
echo "GATES GREEN"
