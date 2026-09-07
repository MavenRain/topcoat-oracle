#!/bin/zsh
# m30_gate.sh: the repro writer gate.  Runs the walk for both plants, writes
# both repro files, and hands the bytes to m30_verdict.sh.
# set -e, not set -eu: every shipped gate script of this repo uses set -e.
set -e

ROOT=${0:A:h}
cd "$ROOT"

# The same switch every gate from m20 on evals (m29_gate.sh:24), so a lone run
# of this script matches the ladder.
eval "$(opam env --switch=karamel-710 --set-switch)"

OUT=_emit/m30/out
REF_PLANT=ref:display_sign
JS_PLANT=js:signal_get_plus_one
FUEL=24

# Leave the plant directories absent so both CLI runs exercise creation of
# a fresh output directory.  OUT itself holds the captured gate logs.
rm -rf "$OUT"
mkdir -p "$OUT"

# Record the state of every repros/ directory before the two runs below, so
# the verdict can prove the runs neither created nor changed anything there.
./m30_verdict.sh --snapshot "$OUT/repros.before"

# The build log is captured and then truncated.  A pipe into tail would hand
# set -e the exit code of tail, so a failed build has to be tested directly.
print -r -- "m30_gate: build"
dune build > "$OUT/build.log" 2>&1 || { print -r -- "m30_gate: RED dune build"; tail -n 20 "$OUT/build.log"; exit 1; }

print -r -- "m30_gate: m29 unedited"
./m29_gate.sh > "$OUT/m29.log" 2>&1 || { print -r -- "m30_gate: RED m29_gate.sh"; tail -n 40 "$OUT/m29.log"; exit 1; }

print -r -- "m30_gate: ref"
dune exec bin/m30.exe -- repro "$OUT/$REF_PLANT" --plant "$REF_PLANT" --fuel "$FUEL" > "$OUT/ref.stdout" 2> "$OUT/ref.stderr"

print -r -- "m30_gate: js"
dune exec bin/m30.exe -- repro "$OUT/$JS_PLANT" --plant "$JS_PLANT" --fuel "$FUEL" > "$OUT/js.stdout" 2> "$OUT/js.stderr"

exec ./m30_verdict.sh "$OUT" "$REF_PLANT" "$JS_PLANT"
