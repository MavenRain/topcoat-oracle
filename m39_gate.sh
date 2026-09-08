#!/bin/zsh
# Check signal identity against the target's actual browser surrogate classes.
set -e
ROOT=${0:A:h}
cd "$ROOT"
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "M39 GATE RED: opam switch $SWITCH is not installed" >&2
  exit 1
}
TCO_OPAM_ENV=$(opam env --switch=$SWITCH --set-switch) || exit 1
eval "$TCO_OPAM_ENV"
python3 -P test/test_archive_sources.py
python3 -P "$ROOT/m39_verdict.py" --selftest
python3 -P "$ROOT/m39_verdict.py" "$ROOT" "$ROOT/../topcoat"
