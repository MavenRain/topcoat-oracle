#!/bin/zsh
# m31_gate.sh: the pipeline gate.  Builds, runs the m30 gate unedited, runs
# the 500 sample smoke, the resumed run, both replays, the planted run and
# the four negatives, and hands the bytes to m31_verdict.sh.
# set -e, not set -eu: every shipped gate script of this repo uses set -e.
set -e

ROOT=${0:A:h}
cd "$ROOT"

# The same switch every gate from m20 on evals (m29_gate.sh:24), so a lone run
# of this script matches the ladder.
eval "$(opam env --switch=karamel-710 --set-switch)"

OUT=_emit/m31/out
SEED=0x4d3331
OTHER_SEED=0x4d3332
PLANT=ref:display_sign

rm -rf "$OUT"
mkdir -p "$OUT"

# The build log is captured and then truncated.  A pipe into tail would hand
# set -e the exit code of tail, so a failed build has to be tested directly.
print -r -- "m31_gate: build"
dune build > "$OUT/build.log" 2>&1 || {
  print -r -- "m31_gate: RED dune build"
  tail -n 20 "$OUT/build.log"
  exit 1
}

print -r -- "m31_gate: test"
dune runtest --force > "$OUT/test.log" 2>&1 || {
  print -r -- "m31_gate: RED dune runtest"
  tail -n 40 "$OUT/test.log"
  exit 1
}

print -r -- "m31_gate: m30 unedited"
./m30_gate.sh > "$OUT/m30.log" 2>&1 || {
  print -r -- "m31_gate: RED m30_gate.sh"
  tail -n 40 "$OUT/m30.log"
  exit 1
}

print -r -- "m31_gate: straight 500"
dune exec bin/m31.exe -- run "$OUT/straight" --samples 500 --seed "$SEED" \
  > "$OUT/straight.stdout" 2> "$OUT/straight.stderr"

print -r -- "m31_gate: resume 250 then 500"
dune exec bin/m31.exe -- run "$OUT/resume" --samples 250 --seed "$SEED" \
  > "$OUT/resume1.stdout" 2> "$OUT/resume1.stderr"
dune exec bin/m31.exe -- run "$OUT/resume" --samples 500 --seed "$SEED" \
  > "$OUT/resume2.stdout" 2> "$OUT/resume2.stderr"

print -r -- "m31_gate: replay"
dune exec bin/m31.exe -- replay "$OUT/straight" \
  > "$OUT/replay.straight.stdout" 2> "$OUT/replay.straight.stderr"
dune exec bin/m31.exe -- replay "$OUT/resume" \
  > "$OUT/replay.resume.stdout" 2> "$OUT/replay.resume.stderr"

print -r -- "m31_gate: planted 100"
dune exec bin/m31.exe -- run "$OUT/planted" --samples 100 --seed "$SEED" \
  --plant "$PLANT" > "$OUT/planted.stdout" 2> "$OUT/planted.stderr"

# The journal of the straight run is copied before the negatives, so the
# verdict script can prove the refused run left it byte identical.
cp "$OUT/straight/journal.jsonl" "$OUT/straight.journal.copy"

print -r -- "m31_gate: negatives"
set +e
dune exec bin/m31.exe -- run "$OUT/straight" --samples 500 \
  --seed "$OTHER_SEED" > "$OUT/neg.seed.stdout" 2> "$OUT/neg.seed.stderr"
print -r -- $? > "$OUT/neg.seed.code"
dune exec bin/m31.exe -- replay "$OUT/nothere" \
  > "$OUT/neg.replay.stdout" 2> "$OUT/neg.replay.stderr"
print -r -- $? > "$OUT/neg.replay.code"
dune exec bin/m31.exe -- run "$OUT/neg1" --seed "$SEED" \
  > "$OUT/neg.samples.stdout" 2> "$OUT/neg.samples.stderr"
print -r -- $? > "$OUT/neg.samples.code"
dune exec bin/m31.exe -- run "$OUT/neg2" --samples 10 --seed "$SEED" \
  --batch 0 > "$OUT/neg.batch.stdout" 2> "$OUT/neg.batch.stderr"
print -r -- $? > "$OUT/neg.batch.code"
set -e

exec ./m31_verdict.sh "$OUT"
