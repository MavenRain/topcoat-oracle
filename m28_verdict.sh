#!/bin/zsh
# M28 verdict (DESIGN.md M28).  Args:
#   <out-dir>
#
# Nine numbered checks over the three tables m28_gate.sh printed.
#
# Checks 2 and 3 compare against HAND-DERIVED tables (spec section 9).
# Every row of each one is the M27 row or a row derived by hand from
# the plant, and neither is ever regenerated from the program.
#
# Check 5 is the DESIGN gate statement and it is written so that it
# does NOT read the heredocs.  A builder who pasted the program's own
# output into check 2 would pass check 2 and fail check 5, because
# check 5 only ever compares the planted table with the UNPLANTED one
# from the same run.  That is the negative control N1 of spec 13.4.
set -e
OUT="$1"

red () {
  print -r -- "M28 GATE RED: $1" >&2
  exit 1
}

ROOT="${0:A:h}"
ROOT_M27_TABLE="$ROOT/_emit/m27/out/table.txt"
REF_PLANT="ref:display_sign"
JS_PLANT="js:signal_get_plus_one"
M20_SHA="c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec"
REF_SUMMARY="m27: cases 12 rust 12 js 12 ref 12 agree 4 diverge 7 known 0 leg_fail 1 excused 1 by_design 1 hint_mismatch 0"
JS_SUMMARY="m27: cases 12 rust 12 js 12 ref 12 agree 6 diverge 5 known 0 leg_fail 1 excused 1 by_design 1 hint_mismatch 0"
NONE_SUMMARY="m27: cases 12 rust 12 js 12 ref 12 agree 7 diverge 4 known 0 leg_fail 1 excused 1 by_design 1 hint_mismatch 0"
UUID="[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

# 1.  The three exit codes.  A Diverge verdict never changes the exit
# code (bin/m27.ml, spec 0.5), so a planted run that found its bug
# still exits 0.  A non-zero code here means a leg failed or a case was
# lost, which is a different thing from the bug we planted.
for sub in ref js none; do
  CODE=$(cat "$OUT/$sub/exit")
  [ "$CODE" = "0" ] ||
    red "the $sub run exited $CODE, expected 0; a plant changes verdicts and never the exit code, so this is a leg failure or a lost case"
done

# The derivation of both heredocs, spec 9.1.  The base is the M27
# table of m27_verdict.sh:121-170, which is itself hand-derived.
# Three steps, once per plant.  1.  Decide which LEG ROWS the plant
# can reach.  For the ref plant that is the F rows whose rendered
# field came from V_f64_bits, because shell/ref_leg.ml:41 is the only
# arm that consults f_display.  For the js plant that is the J rows of
# a case whose emitted body reads a NUMBER signal, because
# lib/plant.mjs's plantedSurrogate passes everything else through.
# 2.  Rewrite the reached cell with core/obs.ml:72-93's encoding.  The
# rendered field is LENGTH PREFIXED, so a sign flip changes r3:1.5 to
# r4:-1.5 and the prefix moves with the text.  3.  Re-walk the six
# channels for that case in order, outcome, class, message, value,
# rendered and signals, and stop at the first unexcused divergence.
# Every row not named in the derivation is copied from the M27
# heredoc verbatim.  Neither table was printed by a program.

# 2.  The planted-reference table, byte for byte.  Six rows move and
# no others: 0 F and 3 F to |r4:-1.5|, 6 F to |r4:-2.5|, and the V
# rows 0, 3 and 6 to diverge:rendered:odd:ref.  The VALUE field holds,
# because the plant runs inside the renderer and never inside
# encode_value, and the SIGNALS field holds, because encode_signals
# encodes value bits and never calls f_display.  The carried M27
# divergences stand: case 1 odd:rust, case 5 odd:js on class, cases 8
# and 10 odd:js on message, case 7 agree by the two-way rule and case
# 11 leg_fail.
cat > "$OUT/ref.expected" <<'EXPECTED_REF'
0 R Vf1073217536:0;|r3:1.5|
0 J Vf1073217536:0;|r3:1.5|
0 F Vf1073217536:0;|r4:-1.5|
0 V read_only diverge:rendered:odd:ref
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
3 F VSf1073217536:0;|r4:-1.5|
3 V read_only diverge:rendered:odd:ref
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
6 F Vf1074003968:0;|r4:-2.5|g3:f1074003968:0;
6 V read_only diverge:rendered:odd:ref
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
EXPECTED_REF
if ! cmp -s "$OUT/ref.expected" "$OUT/ref/table.txt"; then
  print -r -- "M28 GATE RED: the planted-reference table differs from the hand-derived expected table" >&2
  diff -u "$OUT/ref.expected" "$OUT/ref/table.txt" | head -40 >&2
  exit 1
fi

# 3.  The planted-js table, byte for byte.  Two rows move and no
# others: 6 J, because the wrapped WriteSignal's get returns an F64 of
# 3.5 whose hi word is 1074528256 and whose nodeText is three bytes so
# the prefix stays r3, and 6 V to diverge:value:odd:js, because value
# precedes rendered and signals so the walk stops at value.  The
# signals cell reads the REGISTRY, which was seeded through an f64
# node and holds the true 2.5.
cat > "$OUT/js.expected" <<'EXPECTED_JS'
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
6 J Vf1074528256:0;|r3:3.5|g3:f1074003968:0;
6 F Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
6 V read_only diverge:value:odd:js
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
EXPECTED_JS
if ! cmp -s "$OUT/js.expected" "$OUT/js/table.txt"; then
  print -r -- "M28 GATE RED: the planted-js table differs from the hand-derived expected table" >&2
  diff -u "$OUT/js.expected" "$OUT/js/table.txt" | head -40 >&2
  exit 1
fi

# 4.  RESTORE GREEN.  The unplanted run of the SAME binary reproduces
# the table m27_gate.sh printed minutes earlier in this ladder run.
# This is the whole restore story: no file was edited, so the proof
# that nothing was left mutated is that the unplanted table did not
# move.
if ! cmp -s "$ROOT_M27_TABLE" "$OUT/none/table.txt"; then
  print -r -- "M28 GATE RED: the no-plant table differs from _emit/m27/out/table.txt; the plant leaked into the unplanted run" >&2
  diff -u "$ROOT_M27_TABLE" "$OUT/none/table.txt" | head -40 >&2
  exit 1
fi

# 5.  DETECTION, and it never reads a heredoc.  The V rows of the
# planted table are compared with the V rows of the UNPLANTED table of
# the same run.  Two things are asserted: enough rows moved, and every
# row that moved names the planted leg as the odd party.  A plant that
# moved a row the wrong way, or that moved a row by making some OTHER
# leg odd, is red here even when checks 2 and 3 pass.
v_rows () { rg -N -e '^[0-9]+ V ' -- "$1"; }
v_rows "$OUT/none/table.txt" > "$OUT/none.v"
v_rows "$OUT/ref/table.txt" > "$OUT/ref.v"
v_rows "$OUT/js/table.txt" > "$OUT/js.v"

changed () { paste "$1" "$2" | awk -F '\t' '$1 != $2 { print $2 }'; }

changed "$OUT/none.v" "$OUT/ref.v" > "$OUT/ref.changed"
REF_N=$(awk 'END { print NR }' "$OUT/ref.changed")
[ "$REF_N" -ge 2 ] ||
  red "the ref plant $REF_PLANT moved $REF_N verdict rows, expected at least 2; the plant was parsed but not applied, or it landed on a field no seed reaches"
REF_BAD=$(awk '$0 !~ /:odd:ref$/ { print; exit }' "$OUT/ref.changed")
[ -z "$REF_BAD" ] ||
  red "a verdict row moved under the ref plant without naming the reference as the odd leg: $REF_BAD"

changed "$OUT/none.v" "$OUT/js.v" > "$OUT/js.changed"
JS_N=$(awk 'END { print NR }' "$OUT/js.changed")
[ "$JS_N" -ge 1 ] ||
  red "the js plant $JS_PLANT moved $JS_N verdict rows, expected at least 1; the plant was parsed but not forwarded to the worker, or the worker ignored it"
JS_BAD=$(awk '$0 !~ /:odd:js$/ { print; exit }' "$OUT/js.changed")
[ -z "$JS_BAD" ] ||
  red "a verdict row moved under the js plant without naming the js leg as the odd leg: $JS_BAD"

# 6.  ISOLATION.  A plant must move ONE leg.  The rust rows are a
# replayed capture and can never move.  A ref plant must leave the js
# rows alone, and a js plant must leave the reference rows alone.  This
# is the check that catches a plant wired into the shared path instead
# of into one leg.
leg_rows () { rg -N -e "^[0-9]+ $2 " -- "$1"; }
for sub in ref js; do
  leg_rows "$OUT/$sub/table.txt" R > "$OUT/$sub.r"
done
leg_rows "$OUT/none/table.txt" R > "$OUT/none.r"
cmp -s "$OUT/ref.r" "$OUT/none.r" ||
  red "the rust rows moved under the ref plant; the rust leg is a replayed capture and no plant may reach it"
cmp -s "$OUT/js.r" "$OUT/none.r" ||
  red "the rust rows moved under the js plant; the rust leg is a replayed capture and no plant may reach it"

leg_rows "$OUT/ref/table.txt" J > "$OUT/ref.j"
leg_rows "$OUT/none/table.txt" J > "$OUT/none.j"
cmp -s "$OUT/ref.j" "$OUT/none.j" ||
  red "the js rows moved under the ref plant; Plant.js_args must answer [] for a ref plant"

leg_rows "$OUT/js/table.txt" F > "$OUT/js.f"
leg_rows "$OUT/none/table.txt" F > "$OUT/none.f"
cmp -s "$OUT/js.f" "$OUT/none.f" ||
  red "the reference rows moved under the js plant; Plant.ops must answer Ops.interp_ops for a js plant"

# 7.  The three CLI summary lines, whole.  The counts are asserted
# together, so one verdict that moved shows up here as well as in
# checks 2, 3 and 4.  node writes its experimental warnings to the same
# stream, so the match is on the whole LINE and never on the whole
# file.
rg -Fq -x -- "$REF_SUMMARY" "$OUT/ref/cli.err" ||
  red "the ref run stderr does not carry the expected summary line; want: $REF_SUMMARY"
rg -Fq -x -- "$JS_SUMMARY" "$OUT/js/cli.err" ||
  red "the js run stderr does not carry the expected summary line; want: $JS_SUMMARY"
rg -Fq -x -- "$NONE_SUMMARY" "$OUT/none/cli.err" ||
  red "the no-plant run stderr does not carry the expected summary line; want: $NONE_SUMMARY"

# 8.  The plant: line is present when a plant is set and ABSENT when
# none is.  An unconditional line would change the stderr of every m27
# run, and a missing one would let a run that silently dropped the flag
# look like a planted run.
rg -Fq -x -- "plant: $REF_PLANT" "$OUT/ref/cli.err" ||
  red "the ref run stderr does not carry the line 'plant: $REF_PLANT'; the flag was dropped before the report"
rg -Fq -x -- "plant: $JS_PLANT" "$OUT/js/cli.err" ||
  red "the js run stderr does not carry the line 'plant: $JS_PLANT'; the flag was dropped before the report"
if rg -q -e '^plant: ' -- "$OUT/none/cli.err"; then
  red "the no-plant run stderr carries a plant: line; the unplanted run must be byte-identical to an m27 run"
fi

# 9.  M20 must be untouched, and no uuid may leave the driver in any of
# the three runs.  The wire signal id is a u32 and the JS registry key
# is a uuid.
SHA=$(cat "$OUT/m20.sha")
[ "$SHA" = "$M20_SHA" ] ||
  red "the M20 emitted lib.rs sha is $SHA, expected $M20_SHA; M28 changed shell/emit.ml"
for sub in ref js none; do
  if rg -q -- "$UUID" "$OUT/$sub/seed.js.jsonl"; then
    print -r -- "M28 GATE RED: the $sub js JSONL carries a Signal uuid; only the wire u32 id may leave the driver" >&2
    rg -n -- "$UUID" "$OUT/$sub/seed.js.jsonl" | head -5 >&2
    exit 1
  fi
done

print -r -- "M28 GATE GREEN: ref plant $REF_PLANT detected on $REF_N rows (odd:ref), js plant $JS_PLANT detected on $JS_N rows (odd:js), the no-plant table equals the m27 table byte for byte;  m20 sha unchanged"
