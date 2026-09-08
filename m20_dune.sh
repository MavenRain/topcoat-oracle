#!/bin/zsh
# Helper: dune build @all + runtest with the repo switch, from any cwd.
set -e
ROOT="${0:A:h}"
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "m20_dune: RED opam switch $SWITCH is not installed"
  exit 1
}
if ! TCO_OPAM_ENV=$(opam env --switch="$SWITCH" --set-switch); then
  print -r -- "m20_dune: RED could not load opam switch $SWITCH"
  exit 1
fi
eval "$TCO_OPAM_ENV"
unset TCO_OPAM_ENV
dune build --root "$ROOT" @all
dune runtest --root "$ROOT" --force
