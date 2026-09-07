#!/bin/zsh
# m33_gate.sh: the allowlist gate.  Builds, tests, runs the m32 gate unedited,
# renders KNOWN.md, checks every citation against the two roots, counts the
# verdict census of the journals the m31 ladder wrote, and runs eight negatives
# on COPIES and on wrong roots only.  It never edits a source file and it
# re-runs no leg: the census is a count of verdict FIELDS and no row is
# re-judged, because the journal carries no decoder back into an observation
# (facts A-5).
set -e

ROOT=${0:A:h}
cd "$ROOT"

# The switch selection is FATAL.  eval "$(opam env --switch=absent ...)" runs
# eval on an empty string and returns 0, so set -e cannot see a missing
# switch and the whole ladder would silently build under whatever switch the
# caller exported.  Name the switch, prove it exists, then select it.
SWITCH=anvil-ocaml
opam switch list --short | rg -qx -- "$SWITCH" || {
  print -r -- "m33_gate: RED opam switch $SWITCH is not installed"
  exit 1
}
eval "$(opam env --switch=$SWITCH --set-switch)"

OUT=_emit/m33/out
M31OUT=_emit/m31/out
CLONE=${M33_CLONE:-$HOME/Documents/topcoat}

# The clone is an external checkout and four of the eleven cite rows are
# validated against it, so the revision is PINNED here.  A moved clone is a
# red gate and not a silently different evidence base.
CLONE_REV=51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
[[ "$(git -C "$CLONE" rev-parse HEAD)" == "$CLONE_REV" ]] || {
  print -r -- "m33_gate: RED clone $CLONE is not at $CLONE_REV"
  exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT"

print -r -- "m33_gate: build"
dune build > "$OUT/build.log" 2>&1 || {
  print -r -- "m33_gate: RED dune build"
  tail -n 20 "$OUT/build.log"
  exit 1
}

print -r -- "m33_gate: test"
dune runtest --force > "$OUT/test.log" 2>&1 || {
  print -r -- "m33_gate: RED dune runtest"
  tail -n 40 "$OUT/test.log"
  exit 1
}

print -r -- "m33_gate: m32 unedited"
./m32_gate.sh > "$OUT/m32.log" 2>&1 || {
  print -r -- "m33_gate: RED m32_gate.sh"
  tail -n 40 "$OUT/m32.log"
  exit 1
}

print -r -- "m33_gate: positives"
set +e
dune exec bin/m33.exe -- render > "$OUT/render.md" 2> "$OUT/render.stderr"
print -r -- $? > "$OUT/render.code"
dune exec bin/m33.exe -- cite "$CLONE" "$ROOT" \
  > "$OUT/cite.stdout" 2> "$OUT/cite.stderr"
print -r -- $? > "$OUT/cite.code"
set -e

# The census.  awk lifts the whole verdict FIELD of every journal line, and
# the counts are sorted so two runs compare byte for byte.  The offset 11 is
# the length of the key text "verdict":" that index finds.
# The journals are written by the m31 ladder above, not by this gate, so
# prove they were written by THIS build before counting them.  Without the
# check the allowlist could be gutted and the census evidence would still
# pass, because checks 4 to 8 would read the journals of an older binary.
# The wording follows m28_gate.sh:53-54.
for d in straight resume planted; do
  if [ ! -s "$M31OUT/$d/journal.jsonl" ]; then
    print -r -- "m33_gate: RED $M31OUT/$d/journal.jsonl missing or empty; m31_gate.sh writes it and is the prerequisite for this gate"
    exit 1
  fi
  if [ ! "$M31OUT/$d/journal.jsonl" -nt _build/default/bin/m31.exe ]; then
    print -r -- "m33_gate: RED $M31OUT/$d/journal.jsonl is older than bin/m31.exe, so it was written by a different binary; run gates.sh in order"
    exit 1
  fi
done

census () {
  awk '{ n = index($0, "\"verdict\":\"")
         if (n > 0) { s = substr($0, n + 11)
                      q = index(s, "\"")
                      if (q > 1) print substr(s, 1, q - 1) } }' "$1" \
    | sort | uniq -c \
    | awk '{ c = $1; sub(/^ *[0-9]+ /, ""); print $0 " " c }' \
    | sort > "$2"
}
census "$M31OUT/straight/journal.jsonl" "$OUT/straight.census"
census "$M31OUT/resume/journal.jsonl" "$OUT/resume.census"
census "$M31OUT/planted/journal.jsonl" "$OUT/planted.census"

# ---------- the eight negatives ----------
# None of them edits a source file.  N1 and N2 point a root at a directory
# that holds no cited file.  N3, N4 and N5 are usage negatives.  N6 mutates a
# COPY of KNOWN.md and requires the byte comparison to bite.  N7 mutates a
# COPY of a cited file and requires the QUOTE check to bite, which N1 and N2
# cannot show: they only remove the file.  N8 mutates a COPY of the SOURCE
# tree, builds m33 there and requires the render to move, which is the
# negative for the KNOWN.md comparison of check 2.
print -r -- "m33_gate: negatives"
set +e
dune exec bin/m33.exe -- cite "$OUT/nothere" "$ROOT" \
  > "$OUT/neg1.stdout" 2> "$OUT/neg1.stderr"
print -r -- $? > "$OUT/neg1.code"
dune exec bin/m33.exe -- cite "$CLONE" "$OUT/nothere" \
  > "$OUT/neg2.stdout" 2> "$OUT/neg2.stderr"
print -r -- $? > "$OUT/neg2.code"
dune exec bin/m33.exe -- > "$OUT/neg3.stdout" 2> "$OUT/neg3.stderr"
print -r -- $? > "$OUT/neg3.code"
dune exec bin/m33.exe -- verify > "$OUT/neg4.stdout" 2> "$OUT/neg4.stderr"
print -r -- $? > "$OUT/neg4.code"
dune exec bin/m33.exe -- cite "$CLONE" \
  > "$OUT/neg5.stdout" 2> "$OUT/neg5.stderr"
print -r -- $? > "$OUT/neg5.code"
set -e

cp KNOWN.md "$OUT/known.copy"
awk '/^- head: harness$/ && !done { print "- head: upstream"; done = 1; next }
     { print }' "$OUT/known.copy" > "$OUT/neg6.md"
awk 'NR == FNR { a[FNR] = $0; next }
     { if (a[FNR] != $0) c++ }
     END { print c + 0 }' "$OUT/known.copy" "$OUT/neg6.md" > "$OUT/neg6.mutated"

# N7.  A scratch repo root whose core/interp.ml is the REAL file with the one
# CITED line rewritten and every other line untouched.  The file is PRESENT,
# the I1 range 244-251 is in bounds, the line count does not move, and the
# quote is absent, so the quote check is the only arm that can reject it.
# N1 and N2 only delete the file, so neither can show this.  I1 is the first
# cite row, so the failure is deterministic and no later row is reached.
# The needle is READ OUT of the render, so this negative follows the entry
# text instead of a hand copy of it that can go stale.
mkdir -p "$OUT/mutroot/core"
Q=$(awk '/^### I1$/ { f = 1; next }
         f && /^- quote: / { sub(/^- quote: /, ""); print; exit }' "$OUT/render.md")
print -r -- "$Q" > "$OUT/neg7.needle"
rg -c -F -- "$Q" core/interp.ml > "$OUT/neg7.quote.before" \
  || print -r -- 0 > "$OUT/neg7.quote.before"
awk -v q="$Q" \
  '{ if (index($0, q) > 0) print "(* line blanked for the m33 N7 negative *)"
     else print }' core/interp.ml > "$OUT/mutroot/core/interp.ml"
awk 'END { print NR }' < core/interp.ml > "$OUT/neg7.lines.before"
awk 'END { print NR }' < "$OUT/mutroot/core/interp.ml" > "$OUT/neg7.lines"
NQ=$(rg -c -F -- "$Q" "$OUT/mutroot/core/interp.ml" || print -r -- 0)
print -r -- "$NQ" > "$OUT/neg7.quote"
set +e
dune exec bin/m33.exe -- cite "$CLONE" "$OUT/mutroot" \
  > "$OUT/neg7.stdout" 2> "$OUT/neg7.stderr"
print -r -- $? > "$OUT/neg7.code"
set -e

# N8.  The render negative for check 2 (ruling R4).  N6 mutates a copy of
# KNOWN.md and shows only that cmp separates two files.  This one mutates a
# COPY of the SOURCE tree, builds m33 inside that copy and requires its render
# to move away from KNOWN.md, which is the property the gate claims: a source
# change the document does not carry reddens the comparison.  No source file
# is edited: the whole tree is a copy under $OUT, which dune ignores because
# _emit starts with an underscore.
print -r -- "m33_gate: render negative"
rm -rf "$OUT/rendroot"
mkdir -p "$OUT/rendroot"
cp dune-project "$OUT/rendroot/"
cp -R core shell bin model "$OUT/rendroot/"
awk '{ if ($0 == "      \"# Known divergences\\n\";")
         print "      \"# Known divergences (m33 negative)\\n\";"
       else print }' core/known.ml > "$OUT/rendroot/core/known.ml"
awk 'NR == FNR { a[FNR] = $0; next }
     { if (a[FNR] != $0) c++ }
     END { print c + 0 }' core/known.ml "$OUT/rendroot/core/known.ml" \
  > "$OUT/neg8.mutated"
set +e
dune build --root "$OUT/rendroot" bin/m33.exe \
  > "$OUT/neg8.build.log" 2>&1
print -r -- $? > "$OUT/neg8.build.code"
"$OUT/rendroot/_build/default/bin/m33.exe" render \
  > "$OUT/neg8.md" 2> "$OUT/neg8.stderr"
print -r -- $? > "$OUT/neg8.code"
set -e

# The pinned clone revision goes to the verdict script as the third argument,
# so check 14 can require every journal header to name it.  Without it the
# header check accepts any forty hex bytes and no journal is bound to the
# evidence base this gate pins at line 32.
set +e
./m33_verdict.sh "$OUT" "$M31OUT" "$CLONE_REV"
V=$?
set -e
print -r -- "GATE-EXIT=$V"
exit $V
