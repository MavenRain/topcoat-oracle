#!/bin/zsh
# M27 verdict (DESIGN.md M27).  Args:
#   <out-dir> <cli-exit>
#
# Exit-code, line-count and byte based.  It never greps for a bare
# "error" to decide (the M21 false-red lesson);  rg counts fixed JSON
# keys and nothing else.
#
# The 48 printed lines are compared byte for byte with the
# hand-derived table below.  Its first 36 lines are the M26 table of
# m26_verdict.sh:155-192, whose three cells per case were computed
# three different ways and none of them by running the program.  Its
# twelve V lines are walked by hand here, over the channels of spec
# section 3, and check 5 asserts the 36 leg lines against the m26 table
# this ladder run wrote minutes earlier.  It is never regenerated from
# the program.
#
# The walk, spec section 7.  Leg_fail runs first, before any
# projection.  The two-way rule then selects the parties: a Read_only
# sample has three, and a Signal_writing sample has two, the js leg and
# the reference, because the server panics on every signal write by
# design (DESIGN.md:67-69).  The six channels are then compared in ONE
# fixed order, outcome, class, message, value, rendered and signals,
# and a channel is compared only when every party projects a value on
# it.  Signals compare by id, never by order.  Each divergent channel
# is tested against the known list, which is [ i1 ];  the walk records
# an excused tag and CONTINUES, so an entry can never mask a later
# unexcused channel.  The verdict is the first unexcused divergence,
# else the first excused tag as known, else agree.
#
# The twelve walks, one line each:
#
#   0  read_only, three parties, every channel equal.  agree.
#   1  read_only, rendered is a&lt;b&gt;+c (12) in R against a<b>+c (6)
#      in J and F, so rj and rf are false and jf is true.
#      diverge:rendered:odd:rust.  This is D2.
#   2  read_only, every channel equal.  agree.
#   3  read_only, every channel equal.  agree.
#   4  read_only, every channel equal.  agree.
#   5  read_only, all three panicked, class is unwrap in R and F and
#      other in J, so rf is the only agreement.  i1 needs odd:ref, so
#      the channel is unexcused and the walk stops before message,
#      which also differs.  diverge:class:odd:js.  This is D1.
#   6  read_only, one signal each, id 3 with an equal encoding both
#      ways.  agree.
#   7  signal_writing, TWO parties.  The R cell is a signal_write panic
#      and is NOT a party, so the walk compares J and F only: value u
#      and u, signal 4 false on both.  agree.  This is D3, by design,
#      and the CLI counts it once as by_design 1.
#   8  read_only, class expect_err three times, message is nope: "ok"
#      (10) in R and F against nope: ok (8) in J.
#      diverge:message:odd:js.  This is D4.
#   9  read_only, every channel equal.  agree.
#  10  read_only, class is other in R and J and expect_err in F, which
#      is odd:ref, and i1 EXCUSES exactly that shape.  The walk
#      continues to message, where R and F carry nope: "ok" (10) and J
#      carries nope: ok (8).  i1 does not apply to message, so the
#      verdict is diverge:message:odd:js and excused is [ I1 ].  With
#      an EMPTY known list the same walk stops at class and gives
#      diverge:class:odd:ref;  the unit vectors assert both.
#  11  read_only, the J cell is skipped:no_js, which the CLI turns into
#      an absent party.  Leg_fail precedes every projection, so the
#      verdict is leg_fail:js:skipped:no_js and no channel is read.
#
# Counting those: agree on 0, 2, 3, 4, 6, 7 and 9 is 7;  diverge on 1,
# 5, 8 and 10 is 4;  known on none is 0, because the only excused
# channel in the corpus is followed by an unexcused one;  leg_fail on
# 11 is 1.  7 + 4 + 0 + 1 = 12.  excused is 1, case 10.  by_design is
# 1, case 7.  hint_mismatch is 0, as in M26.
#
# Four cases record a DIVERGENCE between the legs, and all four are
# outputs of this pipeline rather than defects in it.  M27 adjudicates
# them and reports them;  it does not repair them.  Never correct one
# leg toward another.
set -e
OUT="$1"
CLI_EXIT="$2"

# The m26 table sits beside this run's own output, two levels up from
# $OUT and back down, so the script has no second argument to forget.
M26_OUT="${OUT:h:h}/m26/out"

M20_SHA="c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec"
JS_SUMMARY="driver-js: cases 12 value 7 panic 4 js_error 0 no_terminate 0 skipped 1 driver_error 0"
CLI_SUMMARY="m27: cases 12 rust 12 js 12 ref 12 agree 7 diverge 4 known 0 leg_fail 1 excused 1 by_design 1 hint_mismatch 0"
UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

red() {
  print -r -- "M27 GATE RED: $1" >&2
  exit 1
}

# 1.  A capture that is missing is red, never a vacuous green.
[ -n "$OUT" ] && [ -d "$OUT" ] || red "no out directory was handed over"

# 2.  The CLI exited 0.  This check runs BEFORE the emptiness test and
# before the table diff, because a broken spawn prints no rows at all
# and the reason must be named rather than reported as an empty table.
if [ "$CLI_EXIT" -ne 0 ]; then
  print -r -- "M27 GATE RED: the CLI exited $CLI_EXIT, expected 0" >&2
  head -20 "$OUT/cli.err" >&2
  exit 1
fi
[ -s "$OUT/table.txt" ] || red "the printed table is empty; the run produced no rows at all"

# 3.  Forty-eight rows, twelve of each kind.  awk reads $2 only,
# because a cell can carry spaces.
ROWS=$(wc -l < "$OUT/table.txt" | tr -d ' ')
[ "$ROWS" -eq 48 ] || red "the table carries $ROWS rows, expected 48"
R_ROWS=$(awk '$2 == "R"' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$R_ROWS" -eq 12 ] || red "the table carries $R_ROWS rust rows, expected 12"
J_ROWS=$(awk '$2 == "J"' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$J_ROWS" -eq 12 ] || red "the table carries $J_ROWS js rows, expected 12"
F_ROWS=$(awk '$2 == "F"' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$F_ROWS" -eq 12 ] || red "the table carries $F_ROWS reference rows, expected 12"
V_ROWS=$(awk '$2 == "V"' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$V_ROWS" -eq 12 ] || red "the table carries $V_ROWS verdict rows, expected 12"

# 4.  The 48-line table, byte for byte.  Nothing is masked: every one
# of the 48 rows is stable across runs.
cat > "$OUT/table.expected" <<'EXPECTED'
0 R Vf1073217536:0;|r3:1.5|
0 J Vf1073217536:0;|r3:1.5|
0 F Vf1073217536:0;|r3:1.5|
0 V read_only agree
1 R Vs6:a<b>+c|r12:a&lt;b&gt;+c|
1 J Vs6:a<b>+c|r6:a<b>+c|
1 F Vs6:a<b>+c|r6:a<b>+c|
1 V read_only diverge:rendered:odd:rust
2 R Vs0:|r0:|
2 J Vs0:|r0:|
2 F Vs0:|r0:|
2 V read_only agree
3 R VSf1073217536:0;|r3:1.5|
3 J VSf1073217536:0;|r3:1.5|
3 F VSf1073217536:0;|r3:1.5|
3 V read_only agree
4 R Vn|r0:|
4 J Vn|r0:|
4 F Vn|r0:|
4 V read_only agree
5 R Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|
5 J Pother:42:called `Option.unwrap()` on a `None` value|r0:|
5 F Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|
5 V read_only diverge:class:odd:js
6 R Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
6 J Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
6 F Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
6 V read_only agree
7 R Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g4:b1
7 J Vu|r0:|g4:b0
7 F Vu|r0:|g4:b0
7 V signal_writing agree
8 R Pexpect_err:10:nope: "ok"|r0:|
8 J Pexpect_err:8:nope: ok|r0:|
8 F Pexpect_err:10:nope: "ok"|r0:|
8 V read_only diverge:message:odd:js
9 R Pexpect:4:boom|r0:|
9 J Pexpect:4:boom|r0:|
9 F Pexpect:4:boom|r0:|
9 V read_only agree
10 R Pother:10:nope: "ok"|r0:|
10 J Pother:8:nope: ok|r0:|
10 F Pexpect_err:10:nope: "ok"|r0:|
10 V read_only diverge:message:odd:js
11 R T|r0:|
11 J skipped:no_js
11 F T|r0:|
11 V read_only leg_fail:js:skipped:no_js
EXPECTED

if ! cmp -s "$OUT/table.expected" "$OUT/table.txt"; then
  print -r -- "M27 GATE RED: the printed table differs from the hand-derived expected table" >&2
  diff -u "$OUT/table.expected" "$OUT/table.txt" | head -40 >&2
  exit 1
fi

# 5.  The 36 leg rows equal the m26 table.  This proves the legs ran as
# they did in M26 and that the verdict rewrote nothing.  The pattern is
# anchored at the line start, so a V row can never be selected and a
# cell that carries " R " can never add one.  rg preserves file order.
# The m26 table is fresh because gates.sh runs m26_gate.sh immediately
# before m27_gate.sh in the same ladder.  This check subsumes the M26
# masked compare against the m25 expectation, which m26_verdict.sh ran
# minutes ago over the same driver output.
rg -N -e '^[0-9]+ (R|J|F) ' -- "$OUT/table.txt" > "$OUT/legs.txt"
if ! cmp -s "$OUT/legs.txt" "$M26_OUT/table.txt"; then
  print -r -- "M27 GATE RED: the R, J and F rows differ from _emit/m26/out/table.txt; the m27 CLI did not reproduce the m26 legs" >&2
  diff -u "$M26_OUT/table.txt" "$OUT/legs.txt" | head -40 >&2
  exit 1
fi

# 6.  The CLI stderr summary line, whole.  The four verdict counts, the
# excused count and the by_design count are asserted together, so one
# verdict that moved shows up here as well as in check 4.
if ! rg -Fq -x -- "$CLI_SUMMARY" "$OUT/cli.err"; then
  print -r -- "M27 GATE RED: the CLI stderr does not carry the expected summary line" >&2
  print -r -- "  want: $CLI_SUMMARY" >&2
  head -5 "$OUT/cli.err" >&2
  exit 1
fi

# 7.  The driver stderr summary line, whole.  node writes its
# experimental warnings to the same stream, so the match is on the
# whole line and never on the whole file.
if ! rg -Fq -x -- "$JS_SUMMARY" "$OUT/seed.js.err"; then
  print -r -- "M27 GATE RED: the driver stderr does not carry the expected summary line" >&2
  print -r -- "  want: $JS_SUMMARY" >&2
  head -5 "$OUT/seed.js.err" >&2
  exit 1
fi

# 8.  No uuid anywhere in the js output.  The wire signal id is a u32
# and the JS registry key is a uuid;  only the u32 leaves the driver.
if rg -q -- "$UUID" "$OUT/seed.js.jsonl"; then
  print -r -- "M27 GATE RED: the js JSONL carries a Signal uuid; only the wire u32 id may leave the driver" >&2
  rg -n -- "$UUID" "$OUT/seed.js.jsonl" | head -5 >&2
  exit 1
fi

# 9.  No js_error and no driver_error line, counted on the fixed keys.
JS_ERRORS=$(rg -c '"outcome":"js_error"' "$OUT/seed.js.jsonl" || true)
[ -z "$JS_ERRORS" ] || red "the js JSONL carries $JS_ERRORS js_error lines, expected 0; the generated JS threw something that is not a Panic"
DRIVER_ERRORS=$(rg -c '"outcome":"driver_error"' "$OUT/seed.js.jsonl" || true)
[ -z "$DRIVER_ERRORS" ] || red "the js JSONL carries $DRIVER_ERRORS driver_error lines, expected 0; the driver could not decode or encode a channel"

# 10.  M20 must be untouched.
SHA=$(cat "$OUT/m20.sha")
[ "$SHA" = "$M20_SHA" ] || red "the M20 emitted lib.rs sha is $SHA, expected $M20_SHA; M27 changed shell/emit.ml"

print -r -- "M27 GATE GREEN: 48/48 rows byte-exact against the hand-derived table, 36 leg rows equal the m26 table, 12 verdicts (agree 7, diverge 4, known 0, leg_fail 1), 0 hint mismatch;  m20 sha unchanged."
