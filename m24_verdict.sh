#!/bin/zsh
# M24 verdict (DESIGN.md M24).  Args:
#   <out-dir> <cli-exit>
#
# Exit-code, line-count and byte based.  It never greps for a bare
# "error" to decide (the M21 false-red lesson);  rg counts fixed JSON
# keys and nothing else.
#
# The printed table is compared byte for byte with the hand-derived
# table below, with ONE column masked: the trailing js byte count.
# js_hex carries a fresh Signal uuid per run, so neither its bytes nor
# its length is stable.  Check 5 pins that column separately: every row
# but the no-terminate row must carry a non-zero count, and the
# no-terminate row must carry zero.
#
# The cell column can contain spaces, because a panic message can, so
# every awk read here uses $1, $2 or $NF only and the rest is compared
# byte for byte.
set -e
OUT="$1"
CLI_EXIT="$2"

M20_SHA="c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec"
SUMMARY="m24 seeds: kept 12 lines 12 resumes 1 exits 3,0 inconsistent 0"

red() {
  print -r -- "M24 GATE RED: $1" >&2
  exit 1
}

# 1.  A capture that is missing or empty is red, never a vacuous green.
[ -n "$OUT" ] && [ -d "$OUT" ] || red "no out directory was handed over"
[ -s "$OUT/table.txt" ] || red "the printed table is empty; the run produced no rows at all"

# 2.  The CLI decoded every line and the counts agreed.
if [ "$CLI_EXIT" -ne 0 ]; then
  print -r -- "M24 GATE RED: the CLI exited $CLI_EXIT, expected 0" >&2
  head -20 "$OUT/cli.err" >&2
  exit 1
fi

# 3.  One row per seed case.
ROWS=$(wc -l < "$OUT/table.txt" | tr -d ' ')
[ "$ROWS" -eq 12 ] || red "the table carries $ROWS rows, expected 12"

# 4.  Exactly one no-terminate row, and it is the last one.  Every
# other cell starts with V or P, so $2 is T on that row alone.
T_ROWS=$(awk '$2 == "T"' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$T_ROWS" -eq 1 ] || red "the table carries $T_ROWS rows whose cell is T, expected exactly 1"
LAST_CELL=$(tail -n 1 "$OUT/table.txt" | awk '{ print $2 }')
LAST_CASE=$(tail -n 1 "$OUT/table.txt" | awk '{ print $1 }')
[ "$LAST_CELL" = "T" ] || red "the last row's cell is $LAST_CELL, expected the no-terminate row"
[ "$LAST_CASE" -eq 11 ] || red "the no-terminate row is case $LAST_CASE, expected 11"

# 5.  The js byte count, which the compare below masks.  A row that
# carries no JS is a lost channel, not a formatting detail.
ZERO_JS=$(awk '$2 != "T" && $NF == 0' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$ZERO_JS" -eq 0 ] || red "$ZERO_JS rows carry a zero js byte count; every case but the no-terminate one emits JS"
T_JS=$(awk '$2 == "T" && $NF != 0' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$T_JS" -eq 0 ] || red "the no-terminate row carries a non-zero js byte count; that line carries no JS at all"

# 6.  The masked byte-for-byte compare against the hand-derived table.
sd ' [0-9]+$' ' JS' < "$OUT/table.txt" > "$OUT/table.mask"

cat > "$OUT/table.expected" <<'EXPECTED'
0 Vf1073217536:0;|r3:1.5| direct none 1 JS
1 Vs6:a<b>+c|r12:a&lt;b&gt;+c| direct none 1 JS
2 Vs0:|r0:| direct none 1 JS
3 VSf1073217536:0;|r3:1.5| direct none 1 JS
4 Vn|r0:| direct none 1 JS
5 Punwrap:43:called `Option::unwrap()` on a `None` value|r0:| closure none 1 JS
6 Vf1074003968:0;|r3:2.5|g3:f1074003968:0; direct none 1 JS
7 Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g4:b1 closure none 1 JS
8 Pexpect_err:10:nope: "ok"|r0:| closure expect_err 1 JS
9 Pexpect:4:boom|r0:| closure expect 1 JS
10 Pother:10:nope: "ok"|r0:| closure both 1 JS
11 T absent none 1 JS
EXPECTED

if ! cmp -s "$OUT/table.mask" "$OUT/table.expected"; then
  print -r -- "M24 GATE RED: the printed table differs from the hand-derived expected table" >&2
  diff -u "$OUT/table.expected" "$OUT/table.mask" | head -40 >&2
  exit 1
fi

# 7.  The run summary, byte for byte.  This one line carries all three
# exit expectations: the seed run exits 3 once because case 11 spins,
# the resume loop runs exactly once, and the resumed run exits 0 and
# writes nothing because case 11 is the last case.
if ! rg -Fq -x -- "$SUMMARY" "$OUT/cli.err"; then
  print -r -- "M24 GATE RED: cli.err does not carry the expected summary line" >&2
  print -r -- "  want: $SUMMARY" >&2
  head -5 "$OUT/cli.err" >&2
  exit 1
fi

# 8.  The JSONL the leg read back, counted on the fixed key and never
# on a bare word.
JSONL_ROWS=$(wc -l < "$OUT/seed.jsonl" | tr -d ' ')
[ "$JSONL_ROWS" -eq 12 ] || red "the seed JSONL carries $JSONL_ROWS lines, expected 12"
NOTERM=$(rg -c '"outcome":"no_terminate"' "$OUT/seed.jsonl" || true)
[ "$NOTERM" = "1" ] || red "the seed JSONL carries $NOTERM no_terminate lines, expected 1"

# 9.  M20 must be untouched.
SHA=$(cat "$OUT/m20.sha")
[ "$SHA" = "$M20_SHA" ] || red "the M20 emitted lib.rs sha is $SHA, expected $M20_SHA; M24 changed shell/emit.ml"

print -r -- "M24 GATE GREEN: 12/12 rows byte-exact against the hand-derived table, one T row, exits 3,0 over 1 resume, 0 inconsistent;  m20 sha unchanged"
