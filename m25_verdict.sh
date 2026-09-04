#!/bin/zsh
# M25 verdict (DESIGN.md M25).  Args:
#   <out-dir> <cli-exit>
#
# Exit-code, line-count and byte based.  It never greps for a bare
# "error" to decide (the M21 false-red lesson);  rg counts fixed JSON
# keys and nothing else.
#
# The twelve written lines are compared byte for byte with the
# hand-derived table below.  The mask is one sd of the uuid pattern,
# which check 5 already proves is a no-op;  it is kept as a belt, so the
# day a line legitimately carries a uuid, check 5 goes red first and
# names it.
#
# The table is derived BY HAND from m23_verdict.sh:60-71 and the
# surrogate sources.  It is never regenerated from the driver.  The
# arithmetic:
#
#   f64 halves, DataView.setFloat64 writes big-endian, so hi is the
#   first four bytes:
#     1.5 = 0x3FF8000000000000
#           hi = 0x3FF80000 = 1073741824 - 524288 = 1073217536, lo = 0
#     2.5 = 0x4004000000000000
#           hi = 0x40040000 = 1073741824 + 262144 = 1074003968, lo = 0
#
#   hex payloads, with byte counts:
#     "1.5"      312e35                                    3 bytes
#     "2.5"      322e35                                    3 bytes
#     "a<b>+c"   613c623e2b63                              6 bytes
#     ""         (empty)                                   0 bytes
#     "called `Option.unwrap()` on a `None` value"
#                63616c6c656420604f7074696f6e2e756e777261
#                70282960206f6e206120604e6f6e6560207661
#                6c7565                                   42 bytes
#     "nope: ok" 6e6f70653a206f6b                          8 bytes
#     "boom"     626f6f6d                                  4 bytes
#
#   The Rust leg writes two of those texts differently:
#     "called `Option::unwrap()` on a `None` value"       43 bytes
#     "nope: \"ok\""                                      10 bytes
#   The first pair differs in one position, 3a3a (two colons) against
#   2e (one dot), so the JS text is one byte shorter.  The second pair
#   differs by the two 22 quote bytes that Rust Debug adds and
#   formatPanicValue does not.
#
#   js_form and hint are COPIED from the input line, never recomputed:
#   they are Rust-side facts about which call site produced the text.
#   Cases 0, 1, 2, 3, 4 and 6 are direct;  cases 5, 7, 8, 9 and 10 are
#   closure;  case 11 carries no JS at all.  Hints: case 8 expect_err,
#   case 9 expect, case 10 both, all others none.
#
#   Counts for the summary line: 7 value (0, 1, 2, 3, 4, 6, 7), 4 panic
#   (5, 8, 9, 10), 1 skipped (11), 0 js_error, 0 no_terminate, 0
#   driver_error, 12 cases.
#
# Four rows record a DIVERGENCE from the rust leg, and all four are
# outputs of this milestone rather than defects in it.  M27 adjudicates
# them.  Case 5 classes as other where the rust row says unwrap,
# because the port keeps the Rust spellings and the surrogate writes a
# dot.  Case 1 renders a<b>+c where the rust row renders the escaped
# text.  Case 7 is a unit value with the signal flipped where the rust
# row is a signal_write panic, which is DESIGN section 2 by design.
# Cases 8 and 10 carry "nope: ok" where the rust rows carry the quoted
# Debug form.  Never "correct" the JS leg toward the Rust text.
set -e
OUT="$1"
CLI_EXIT="$2"

M20_SHA="c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec"
SUMMARY="driver-js: cases 12 value 7 panic 4 js_error 0 no_terminate 0 skipped 1 driver_error 0"
UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

red() {
  print -r -- "M25 GATE RED: $1" >&2
  exit 1
}

# 1.  A capture that is missing or empty is red, never a vacuous green.
[ -n "$OUT" ] && [ -d "$OUT" ] || red "no out directory was handed over"
[ -s "$OUT/seed.js.jsonl" ] || red "the written JSONL is empty; the run produced no lines at all"

# 2.  The driver read every selected line and wrote a line for it.
if [ "$CLI_EXIT" -ne 0 ]; then
  print -r -- "M25 GATE RED: the driver exited $CLI_EXIT, expected 0" >&2
  head -20 "$OUT/seed.js.err" >&2
  exit 1
fi

# 3.  One line per seed case.
ROWS=$(wc -l < "$OUT/seed.js.jsonl" | tr -d ' ')
[ "$ROWS" -eq 12 ] || red "the JSONL carries $ROWS lines, expected 12"

# 4.  Exactly one skipped line, and it is the last one, and it is case
# 11.  That is the case the rust leg never captured JS for.
SKIPPED=$(rg -c '"outcome":"skipped"' "$OUT/seed.js.jsonl" || true)
[ "$SKIPPED" = "1" ] || red "the JSONL carries ${SKIPPED:-0} skipped lines, expected exactly 1"
LAST=$(tail -n 1 "$OUT/seed.js.jsonl")
print -r -- "$LAST" | rg -q '"outcome":"skipped"' ||
  red "the last line is not the skipped line"
LAST_CASE=$(print -r -- "$LAST" | rg -o '^\{"case":[0-9]+' | rg -o '[0-9]+')
[ "$LAST_CASE" -eq 11 ] || red "the skipped line is case $LAST_CASE, expected 11"

# 5.  No uuid anywhere in the output.  The wire signal id is a u32 and
# the JS registry key is a uuid;  only the u32 leaves the driver.  A
# uuid here would be unstable across runs and would make check 6
# impossible, and it would mean the positional pairing regressed to
# emitting the registry key.
if rg -q -- "$UUID" "$OUT/seed.js.jsonl"; then
  print -r -- "M25 GATE RED: the JSONL carries a Signal uuid; only the wire u32 id may leave the driver" >&2
  rg -n -- "$UUID" "$OUT/seed.js.jsonl" | head -5 >&2
  exit 1
fi

# 6.  The masked byte-for-byte compare against the hand-derived table.
sd -- "$UUID" 'ID' < "$OUT/seed.js.jsonl" > "$OUT/seed.js.mask"

cat > "$OUT/seed.js.expected" <<'EXPECTED'
{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"rendered_hex":"312e35","js_form":"direct","hint":"none","signals":[]}
{"case":1,"outcome":"value","value":{"t":"str","hex":"613c623e2b63"},"rendered_hex":"613c623e2b63","js_form":"direct","hint":"none","signals":[]}
{"case":2,"outcome":"value","value":{"t":"str","hex":""},"rendered_hex":"","js_form":"direct","hint":"none","signals":[]}
{"case":3,"outcome":"value","value":{"t":"some","v":{"t":"f64","hi":1073217536,"lo":0}},"rendered_hex":"312e35","js_form":"direct","hint":"none","signals":[]}
{"case":4,"outcome":"value","value":{"t":"none"},"rendered_hex":"","js_form":"direct","hint":"none","signals":[]}
{"case":5,"outcome":"panic","class":"other","msg_hex":"63616c6c656420604f7074696f6e2e756e77726170282960206f6e206120604e6f6e65602076616c7565","js_form":"closure","hint":"none","signals":[]}
{"case":6,"outcome":"value","value":{"t":"f64","hi":1074003968,"lo":0},"rendered_hex":"322e35","js_form":"direct","hint":"none","signals":[{"id":3,"value":{"t":"f64","hi":1074003968,"lo":0}}]}
{"case":7,"outcome":"value","value":{"t":"unit"},"rendered_hex":"","js_form":"closure","hint":"none","signals":[{"id":4,"value":{"t":"bool","v":false}}]}
{"case":8,"outcome":"panic","class":"expect_err","msg_hex":"6e6f70653a206f6b","js_form":"closure","hint":"expect_err","signals":[]}
{"case":9,"outcome":"panic","class":"expect","msg_hex":"626f6f6d","js_form":"closure","hint":"expect","signals":[]}
{"case":10,"outcome":"panic","class":"other","msg_hex":"6e6f70653a206f6b","js_form":"closure","hint":"both","signals":[]}
{"case":11,"outcome":"skipped","reason":"no_js"}
EXPECTED

if ! cmp -s "$OUT/seed.js.mask" "$OUT/seed.js.expected"; then
  print -r -- "M25 GATE RED: the written JSONL differs from the hand-derived expected table" >&2
  diff -u "$OUT/seed.js.expected" "$OUT/seed.js.mask" | head -40 >&2
  exit 1
fi

# 7.  The stderr summary line, whole.  node writes its experimental
# warnings to the same stderr, so the match is on the whole line and
# never on the whole file.
if ! rg -Fq -x -- "$SUMMARY" "$OUT/seed.js.err"; then
  print -r -- "M25 GATE RED: the driver stderr does not carry the expected summary line" >&2
  print -r -- "  want: $SUMMARY" >&2
  head -5 "$OUT/seed.js.err" >&2
  exit 1
fi

# 8.  No js_error and no driver_error line, counted on the fixed keys.
# Check 6 already implies both;  these two name the failure in one line
# instead of a forty-line diff.
JS_ERRORS=$(rg -c '"outcome":"js_error"' "$OUT/seed.js.jsonl" || true)
[ -z "$JS_ERRORS" ] || red "the JSONL carries $JS_ERRORS js_error lines, expected 0; the generated JS threw something that is not a Panic"
DRIVER_ERRORS=$(rg -c '"outcome":"driver_error"' "$OUT/seed.js.jsonl" || true)
[ -z "$DRIVER_ERRORS" ] || red "the JSONL carries $DRIVER_ERRORS driver_error lines, expected 0; the driver could not decode or encode a channel"

# 9.  M20 must be untouched.
SHA=$(cat "$OUT/m20.sha")
[ "$SHA" = "$M20_SHA" ] || red "the M20 emitted lib.rs sha is $SHA, expected $M20_SHA; M25 changed shell/emit.ml"

print -r -- "M25 GATE GREEN: 12/12 js lines byte-exact against the hand-derived table, one skipped line, 0 js_error, 0 driver_error, 0 uuids;  m20 sha unchanged"
