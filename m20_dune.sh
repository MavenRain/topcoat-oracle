#!/bin/zsh
# Helper: dune build @all + runtest with the repo switch, from any cwd.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"
dune build --root "$ROOT" @all
dune runtest --root "$ROOT" --force
