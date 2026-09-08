#!/bin/zsh
# M37 gate (DESIGN.md M37).  Runs standalone or from gates.sh.
set -e
ROOT=${0:A:h}
cd "$ROOT"

# The switch selection is FATAL.  eval "$(opam env --switch=absent ...)" runs
# eval on an empty string and returns 0, so set -e cannot see a missing switch
# and the documented block would build under whatever switch the caller
# exported.  Name the switch, prove it exists, then select it.
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "m37_gate: RED opam switch $SWITCH is not installed"
  exit 1
}
if ! TCO_OPAM_ENV=$(opam env --switch="$SWITCH" --set-switch); then
  print -r -- "m37_gate: RED could not load opam switch $SWITCH"
  exit 1
fi
eval "$TCO_OPAM_ENV"
unset TCO_OPAM_ENV

python3 -P -m unittest discover -s test -p test_m37_quickstart.py
exec python3 -P "$ROOT/m37_verdict.py" run "$ROOT"
