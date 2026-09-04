#!/bin/zsh
# M26 verdict (DESIGN.md M26).  Args:
#   <out-dir> <cli-exit>
#
# Exit-code, line-count and byte based.  It never greps for a bare
# "error" to decide (the M21 false-red lesson);  rg counts fixed JSON
# keys and nothing else.
#
# The 36 printed lines are compared byte for byte with the
# hand-derived table below.  Three cells per case, computed three
# different ways, none of them by running the program: the R cells are
# the M24 rows of m24_verdict.sh:66-77 with their four trailing
# columns dropped, the J cells are the twelve m25 lines of
# m25_verdict.sh:117-130 mapped through core/wire_js.ml, and the F
# cells are traced by hand through core/interp.ml.  It is never
# regenerated from the program.  The arithmetic:
#
#   f64 halves, big-endian, so hi is the first four bytes:
#     1.5 = 0x3FF8000000000000
#           hi = 0x3FF80000 = 1073741824 - 524288 = 1073217536, lo = 0
#     2.5 = 0x4004000000000000
#           hi = 0x40040000 = 1073741824 + 262144 = 1074003968, lo = 0
#   Obs.encode_value writes f<hi>:<lo>; so 1.5 is f1073217536:0; and
#   2.5 is f1074003968:0;.
#
#   hex payloads of the js lines, with byte counts:
#     "1.5"      312e35                                    3 bytes
#     "2.5"      322e35                                    3 bytes
#     "a<b>+c"   613c623e2b63                              6 bytes
#     ""         (empty)                                   0 bytes
#     "called `Option.unwrap()` on a `None` value"        42 bytes
#     "nope: ok" 6e6f70653a206f6b                          8 bytes
#     "boom"     626f6f6d                                  4 bytes
#   The 42-byte one in four runs: 63616c6c656420 is "called " (7),
#   604f7074696f6e2e756e77726170282960 is `Option.unwrap()` (17),
#   206f6e206120 is " on a " (6), 604e6f6e6560 is `None` (6), and
#   2076616c7565 is " value" (6).  7 + 17 + 6 + 6 + 6 = 42.
#
#   The rust and the reference legs write two of those texts
#   differently:
#     "called `Option::unwrap()` on a `None` value"       43 bytes
#     "nope: \"ok\""                                      10 bytes
#   The first pair differs in one position, 3a3a (two colons) against
#   2e (one dot), so the js text is one byte shorter.  The second pair
#   differs by the two 22 quote bytes that Rust Debug adds and
#   formatPanicValue does not.
#
#   The R cell of case 11 is T|r0:| and not the bare T of the M24 row.
#   Rust_leg.row (shell/rust_leg.ml:568-573) special-cases
#   O_no_terminate so its own verdict can find the row with $2 == "T".
#   Obs.encode always writes the rendered channel and the signal
#   channel, and test/test_rust_leg.ml:14-17 makes exactly this
#   substitution for exactly this reason.
#
#   The J cell of case 11 is skipped:no_js.  skipped is not an
#   Obs.outcome, so the js leg prints its own token and core/obs.ml is
#   not extended.
#
#   The F column, traced through core/interp.ml on Driver.seed_cases
#   with Ops.interp_ops and fuel 10000: case 5 is P_unwrap at :581-583,
#   case 8 is P_expect_err with debug_value adding the quote bytes at
#   :619-621, case 9 is P_expect with the bare message at :597, case 10
#   evaluates the LEFT operand first (:248-251) so it is the expect_err
#   site that raises, case 7 flips the signal store and returns unit at
#   :633-640, and case 11 spends its fuel at :214 and is O_no_terminate
#   at :704.  The rendered channel is Rust Display with NO html
#   escaping, so case 1 renders six bytes and not the escaped twelve.
#
#   The hint check: Driver.hint_of is a static scan of the body, so
#   cases 0 to 7 and 11 are none, case 8 expect_err, case 9 expect and
#   case 10 both.  Those are the hints the rust lines carry
#   (m24_verdict.sh:66-77, column 4), so hint_mismatch is 0.
#
# Four rows record a DIVERGENCE between the legs, and all four are
# outputs of this milestone rather than defects in it.  M27
# adjudicates them.  Case 5 classes as other in the js leg where the
# rust and the reference legs say unwrap, because the port keeps the
# Rust spellings and the surrogate writes a dot.  Case 1 renders
# a<b>+c in the js and the reference legs where the rust row renders
# the escaped text.  Case 7 is a unit value with the signal flipped in
# the js and the reference legs where the rust row is a signal_write
# panic, which is DESIGN section 2 by design.  Cases 8 and 10 carry
# "nope: ok" in the js leg where the other two carry the quoted Debug
# form.  Never correct one leg toward another.
set -e
OUT="$1"
CLI_EXIT="$2"

# The m25 expectation sits beside this run's own output, two levels up
# from $OUT and back down, so the script has no second argument to
# forget.
ROOT_EMIT_M25="${OUT:h:h}/m25/out"

M20_SHA="c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec"
JS_SUMMARY="driver-js: cases 12 value 7 panic 4 js_error 0 no_terminate 0 skipped 1 driver_error 0"
CLI_SUMMARY="m26: cases 12 rust 12 js 12 ref 12 js_obs 11 skipped 1 js_error 0 driver_error 0 lossy 0 hint_mismatch 0"
UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

red() {
  print -r -- "M26 GATE RED: $1" >&2
  exit 1
}

# 1.  A capture that is missing is red, never a vacuous green.
[ -n "$OUT" ] && [ -d "$OUT" ] || red "no out directory was handed over"

# 2.  The CLI exited 0.  This check runs BEFORE the emptiness test and
# before the table diff, because a broken spawn prints no rows at all
# and the reason must be named rather than reported as an empty table.
if [ "$CLI_EXIT" -ne 0 ]; then
  print -r -- "M26 GATE RED: the CLI exited $CLI_EXIT, expected 0" >&2
  head -20 "$OUT/cli.err" >&2
  exit 1
fi
[ -s "$OUT/table.txt" ] || red "the printed table is empty; the run produced no rows at all"

# 3.  Thirty-six rows, twelve of each kind.  awk reads $2 only, because
# a cell can carry spaces.
ROWS=$(wc -l < "$OUT/table.txt" | tr -d ' ')
[ "$ROWS" -eq 36 ] || red "the table carries $ROWS rows, expected 36"
R_ROWS=$(awk '$2 == "R"' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$R_ROWS" -eq 12 ] || red "the table carries $R_ROWS rust rows, expected 12"
J_ROWS=$(awk '$2 == "J"' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$J_ROWS" -eq 12 ] || red "the table carries $J_ROWS js rows, expected 12"
F_ROWS=$(awk '$2 == "F"' "$OUT/table.txt" | wc -l | tr -d ' ')
[ "$F_ROWS" -eq 12 ] || red "the table carries $F_ROWS reference rows, expected 12"

# 4.  One js line per seed case.
JS_ROWS=$(wc -l < "$OUT/seed.js.jsonl" | tr -d ' ')
[ "$JS_ROWS" -eq 12 ] || red "the js JSONL carries $JS_ROWS lines, expected 12"

# 5.  No uuid anywhere in the js output.  The wire signal id is a u32
# and the JS registry key is a uuid;  only the u32 leaves the driver.
# This is m25_verdict.sh:103-112 re-run over the file THIS gate
# produced.
if rg -q -- "$UUID" "$OUT/seed.js.jsonl"; then
  print -r -- "M26 GATE RED: the js JSONL carries a Signal uuid; only the wire u32 id may leave the driver" >&2
  rg -n -- "$UUID" "$OUT/seed.js.jsonl" | head -5 >&2
  exit 1
fi

# 6.  The js JSONL equals the m25 expectation.  This is the check that
# proves the spawn wrapper ran the REAL driver over the REAL input and
# not a cached or hand-written file.  The mask is the one m25_verdict.sh
# applies at :115, and check 5 already proves it is a no-op.
sd -- "$UUID" 'ID' < "$OUT/seed.js.jsonl" > "$OUT/seed.js.mask"
if ! cmp -s "$OUT/seed.js.mask" "$ROOT_EMIT_M25/seed.js.expected"; then
  print -r -- "M26 GATE RED: the js JSONL differs from the m25 expectation; the spawn did not run the real driver over the real input" >&2
  diff -u "$ROOT_EMIT_M25/seed.js.expected" "$OUT/seed.js.mask" | head -40 >&2
  exit 1
fi

# 7.  The 36-line table, byte for byte.  Nothing is masked: every one
# of the 36 cells is stable across runs.
cat > "$OUT/table.expected" <<'EXPECTED'
0 R Vf1073217536:0;|r3:1.5|
0 J Vf1073217536:0;|r3:1.5|
0 F Vf1073217536:0;|r3:1.5|
1 R Vs6:a<b>+c|r12:a&lt;b&gt;+c|
1 J Vs6:a<b>+c|r6:a<b>+c|
1 F Vs6:a<b>+c|r6:a<b>+c|
2 R Vs0:|r0:|
2 J Vs0:|r0:|
2 F Vs0:|r0:|
3 R VSf1073217536:0;|r3:1.5|
3 J VSf1073217536:0;|r3:1.5|
3 F VSf1073217536:0;|r3:1.5|
4 R Vn|r0:|
4 J Vn|r0:|
4 F Vn|r0:|
5 R Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|
5 J Pother:42:called `Option.unwrap()` on a `None` value|r0:|
5 F Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|
6 R Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
6 J Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
6 F Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
7 R Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g4:b1
7 J Vu|r0:|g4:b0
7 F Vu|r0:|g4:b0
8 R Pexpect_err:10:nope: "ok"|r0:|
8 J Pexpect_err:8:nope: ok|r0:|
8 F Pexpect_err:10:nope: "ok"|r0:|
9 R Pexpect:4:boom|r0:|
9 J Pexpect:4:boom|r0:|
9 F Pexpect:4:boom|r0:|
10 R Pother:10:nope: "ok"|r0:|
10 J Pother:8:nope: ok|r0:|
10 F Pexpect_err:10:nope: "ok"|r0:|
11 R T|r0:|
11 J skipped:no_js
11 F T|r0:|
EXPECTED

if ! cmp -s "$OUT/table.expected" "$OUT/table.txt"; then
  print -r -- "M26 GATE RED: the printed table differs from the hand-derived expected table" >&2
  diff -u "$OUT/table.expected" "$OUT/table.txt" | head -40 >&2
  exit 1
fi

# 8.  The driver stderr summary line, whole.  node writes its
# experimental warnings to the same stream, so the match is on the
# whole line and never on the whole file.
if ! rg -Fq -x -- "$JS_SUMMARY" "$OUT/seed.js.err"; then
  print -r -- "M26 GATE RED: the driver stderr does not carry the expected summary line" >&2
  print -r -- "  want: $JS_SUMMARY" >&2
  head -5 "$OUT/seed.js.err" >&2
  exit 1
fi

# 9.  The CLI stderr summary line, whole.
if ! rg -Fq -x -- "$CLI_SUMMARY" "$OUT/cli.err"; then
  print -r -- "M26 GATE RED: the CLI stderr does not carry the expected summary line" >&2
  print -r -- "  want: $CLI_SUMMARY" >&2
  head -5 "$OUT/cli.err" >&2
  exit 1
fi

# 10.  No js_error and no driver_error line, counted on the fixed keys.
# Check 6 already implies both;  these two name the failure in one line
# instead of a forty-line diff.
JS_ERRORS=$(rg -c '"outcome":"js_error"' "$OUT/seed.js.jsonl" || true)
[ -z "$JS_ERRORS" ] || red "the js JSONL carries $JS_ERRORS js_error lines, expected 0; the generated JS threw something that is not a Panic"
DRIVER_ERRORS=$(rg -c '"outcome":"driver_error"' "$OUT/seed.js.jsonl" || true)
[ -z "$DRIVER_ERRORS" ] || red "the js JSONL carries $DRIVER_ERRORS driver_error lines, expected 0; the driver could not decode or encode a channel"

# 11.  M20 must be untouched.
SHA=$(cat "$OUT/m20.sha")
[ "$SHA" = "$M20_SHA" ] || red "the M20 emitted lib.rs sha is $SHA, expected $M20_SHA; M26 changed shell/emit.ml"

print -r -- "M26 GATE GREEN: 36/36 rows byte-exact against the hand-derived table, 12 js lines equal the m25 expectation, 0 js_error, 0 driver_error, 0 lossy, 0 hint mismatch;  m20 sha unchanged."
