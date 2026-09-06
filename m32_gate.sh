#!/bin/zsh
# m32_gate.sh: the correspondence gate.  Builds, runs the m31 gate unedited,
# checks the three run directories the m31 gate wrote, then mutates COPIES of
# them seven ways and requires each mutation to be rejected.  No new seed: the
# m32 gate reruns ./m31_gate.sh, the full sample ladder, about 640 s, and adds
# no crate build BEYOND that rerun.  The checks consume the runs that rerun
# wrote (ruling R16).
set -e

ROOT=${0:A:h}
cd "$ROOT"

eval "$(opam env --switch=karamel-710 --set-switch)"

OUT=_emit/m32/out
M31OUT=_emit/m31/out

rm -rf "$OUT"
mkdir -p "$OUT"

print -r -- "m32_gate: build"
dune build > "$OUT/build.log" 2>&1 || {
  print -r -- "m32_gate: RED dune build"
  tail -n 20 "$OUT/build.log"
  exit 1
}

print -r -- "m32_gate: test"
dune runtest --force > "$OUT/test.log" 2>&1 || {
  print -r -- "m32_gate: RED dune runtest"
  tail -n 40 "$OUT/test.log"
  exit 1
}

print -r -- "m32_gate: m31 unedited"
./m31_gate.sh > "$OUT/m31.log" 2>&1 || {
  print -r -- "m32_gate: RED m31_gate.sh"
  tail -n 40 "$OUT/m31.log"
  exit 1
}

print -r -- "m32_gate: positives"
for d in straight resume planted; do
  set +e
  dune exec bin/m32.exe -- check "$M31OUT/$d" \
    > "$OUT/$d.stdout" 2> "$OUT/$d.stderr"
  print -r -- $? > "$OUT/$d.code"
  set -e
done

cp "$M31OUT/straight/journal.jsonl" "$OUT/straight.journal.copy"
cp "$M31OUT/straight/trace.jsonl" "$OUT/straight.trace.copy"

# ---------- the seven negatives, on COPIES only ----------
# Six of the seven mutations are awk programs, never grep and never sed.  N6
# is a whole file substitution by cp, because its point is a header mismatch
# and not a line edit.  Each of the six awk mutations writes the number of
# lines it changed into "$OUT/negK.mutated", and m32_verdict.sh requires that
# number to be 1: a mutation that hits no line would leave a genuine log and
# the negative would wrongly exit 0.  N6 writes the word "shape" instead, and
# only after it has PROVED the substitution happened, because a count of 1 for
# a whole file swap would be a fabricated number and check 7 would be
# tautological for that negative.

J="$M31OUT/straight/journal.jsonl"
T="$M31OUT/straight/trace.jsonl"

# L is the file line of the first judge_agree of the straight trace.  The
# journal and the trace carry their samples in the same order, so line L of
# the journal is the same sample.
L=$(awk '/"judge_agree"/{print NR; exit}' "$T")
# D is the file line of the first diverge row of the straight journal.
D=$(awk '/"verdict":"diverge/{print NR; exit}' "$J")
print -r -- "$L" > "$OUT/first_agree.line"
print -r -- "$D" > "$OUT/first_diverge.line"

mkneg () {  # mkneg <k>: a fresh copy of the straight run directory
  local k=$1
  rm -rf "$OUT/neg$k"
  mkdir -p "$OUT/neg$k"
  cp "$J" "$OUT/neg$k/journal.jsonl"
  cp "$T" "$OUT/neg$k/trace.jsonl"
}

changed () {  # changed <orig> <new> -> the count of REWRITTEN lines
  # This counts the ">" side of the diff, so it answers 0 for a pure deletion.
  # N5 deletes a line and therefore counts itself, see below.
  diff "$1" "$2" | rg -c -- '^>' || print -r -- 0
}

for k in 1 2 3 4 5 6 7; do mkneg $k; done

# N1  the first judge_agree becomes judge_known: the walk is valid and the
#     disposition is wrong.
awk -v L="$L" 'NR==L{sub(/"judge_agree"/,"\"judge_known\"")} {print}' \
  "$T" > "$OUT/neg1/trace.jsonl"
changed "$T" "$OUT/neg1/trace.jsonl" > "$OUT/neg1.mutated"

# N2  the journal verdict of that line becomes "known:i1", trace intact.
awk -v L="$L" 'NR==L{sub(/"verdict":"agree"/,"\"verdict\":\"known:i1\"")} {print}' \
  "$J" > "$OUT/neg2/journal.jsonl"
changed "$J" "$OUT/neg2/journal.jsonl" > "$OUT/neg2.mutated"

# N3  the exec_js_ok of that line is removed: the walk stops at exec_ref_ok,
#     which is not an edge from a world whose js leg is still pending, and it
#     never reaches judge_agree.  C3 is what catches this row when direction
#     1 is weakened;  see the T1 tooth of section 13.
awk -v L="$L" 'NR==L{sub(/"exec_js_ok",/,"")} {print}' \
  "$T" > "$OUT/neg3/trace.jsonl"
changed "$T" "$OUT/neg3/trace.jsonl" > "$OUT/neg3.mutated"

# N4  a step of that line is misspelled.
awk -v L="$L" 'NR==L{sub(/"exec_js_ok"/,"\"exec_js_okay\"")} {print}' \
  "$T" > "$OUT/neg4/trace.jsonl"
changed "$T" "$OUT/neg4/trace.jsonl" > "$OUT/neg4.mutated"

# N5  the last sample line of the trace is removed: the counts disagree.
#     A deletion writes no ">" line into the diff, so "changed" would answer 0
#     here.  N5 counts its own mutation as the line count delta instead.
TOT=$(wc -l < "$T" | tr -d ' ')
awk -v t="$TOT" 'NR<t' "$T" > "$OUT/neg5/trace.jsonl"
NEW5=$(wc -l < "$OUT/neg5/trace.jsonl" | tr -d ' ')
print -r -- $(( TOT - NEW5 )) > "$OUT/neg5.mutated"

# N6  the planted trace under the straight journal: the headers disagree.
#     This is a whole file substitution, so it has no one line count.  The
#     proof that the substitution happened is a shape proof: the copy carries
#     the planted plant field AND is not byte equal to the straight trace.
cp "$M31OUT/planted/trace.jsonl" "$OUT/neg6/trace.jsonl"
if rg -q -- '"plant":"ref:display_sign"' "$OUT/neg6/trace.jsonl" \
   && ! cmp -s "$T" "$OUT/neg6/trace.jsonl"; then
  print -r -- shape > "$OUT/neg6.mutated"
else
  print -r -- none > "$OUT/neg6.mutated"
fi

# N7  a diverge line's trace is extended with shrink_done: the walk is valid
#     and the line then ends in filed.
awk -v L="$D" 'NR==L{sub(/\]\}$/,",\"shrink_done\"]}")} {print}' \
  "$T" > "$OUT/neg7/trace.jsonl"
changed "$T" "$OUT/neg7/trace.jsonl" > "$OUT/neg7.mutated"

print -r -- "m32_gate: negatives"
set +e
for k in 1 2 3 4 5 6 7; do
  dune exec bin/m32.exe -- check "$OUT/neg$k" \
    > "$OUT/neg$k.stdout" 2> "$OUT/neg$k.stderr"
  print -r -- $? > "$OUT/neg$k.code"
done
# N8 and N9 are the two usage negatives: a missing directory and a bad verb.
dune exec bin/m32.exe -- check "$OUT/nothere" \
  > "$OUT/neg.absent.stdout" 2> "$OUT/neg.absent.stderr"
print -r -- $? > "$OUT/neg.absent.code"
dune exec bin/m32.exe -- verify "$M31OUT/straight" \
  > "$OUT/neg.verb.stdout" 2> "$OUT/neg.verb.stderr"
print -r -- $? > "$OUT/neg.verb.code"
set -e

exec ./m32_verdict.sh "$OUT" "$M31OUT"
