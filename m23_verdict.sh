#!/bin/zsh
# M23 verdict (DESIGN.md M23).  Args:
#   <out-dir> <seed-exit> <batch-exit> <resumes>
#
# Exit-code, line-count and byte based.  It never greps for a bare
# "error" to decide (the M21 false-red lesson);  rg counts fixed JSON
# keys and nothing else.
#
# The seed comparison is over the VALUE channel: outcome, value,
# rendered_hex, class, msg_hex, js_form, hint and the signal values are
# byte-exact against the table below, while js_hex and debug_hex are
# MASKED first.  Both carry a fresh Signal uuid per run, and the JS
# text itself is a topcoat implementation detail this milestone does
# not pin (build brief R5).  The JS channel is still checked, twice:
# every line must carry a non-empty js_hex, and each case must contain
# one decoded substring that names the shape the case exists to prove.
set -e
OUT="$1"
SEED_EXIT="$2"
BATCH_EXIT="$3"
RESUMES="$4"

M20_SHA="c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec"
# The size of the draw bin/emit_m23.ml asks QCheck for.  kept + dropped
# must equal it exactly, whatever the drop breakdown says.
DRAW=300

red() {
  print -r -- "M23 GATE RED: $1" >&2
  exit 1
}

[ -n "$OUT" ] && [ -d "$OUT" ] || red "no out directory was handed over"

# 1.  A capture that is missing or empty is red, never a vacuous green.
[ -s "$OUT/seed.jsonl" ] || red "the seed capture is empty; the run produced no JSONL at all"

# 2.  The seed table ends with a body that spins, so 3 is the only
# green code: a clean 0 means the timeout never fired.
if [ "$SEED_EXIT" -ne 3 ]; then
  print -r -- "M23 GATE RED: the seed run exited $SEED_EXIT, expected 3 (the timeout of the last case)" >&2
  head -20 "$OUT/seed.err" >&2
  exit 1
fi

SEED_LINES=$(wc -l < "$OUT/seed.jsonl" | tr -d ' ')
[ "$SEED_LINES" -eq 12 ] || red "the seed run wrote $SEED_LINES lines, expected 12"

# 3.  Every line carries a JS payload and every signal a Debug text.
EMPTY_JS=$(rg -c '"js_hex":""' "$OUT/seed.jsonl" || true)
[ -z "$EMPTY_JS" ] || red "$EMPTY_JS seed lines carry an empty js_hex"
EMPTY_DBG=$(rg -c '"debug_hex":""' "$OUT/seed.jsonl" || true)
[ -z "$EMPTY_DBG" ] || red "$EMPTY_DBG seed signals carry an empty debug_hex"

# 4.  The value channel, byte-exact after masking.
sd '"js_hex":"[0-9a-f]*"' '"js_hex":"JS"' < "$OUT/seed.jsonl" |
  sd '"debug_hex":"[0-9a-f]*"' '"debug_hex":"DBG"' > "$OUT/seed.mask"

cat > "$OUT/seed.expected" <<'EXPECTED'
{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"rendered_hex":"312e35","js_consistent":true,"js_hex":"JS","js_form":"direct","hint":"none","signals":[]}
{"case":1,"outcome":"value","value":{"t":"str","hex":"613c623e2b63"},"rendered_hex":"61266c743b622667743b2b63","js_consistent":true,"js_hex":"JS","js_form":"direct","hint":"none","signals":[]}
{"case":2,"outcome":"value","value":{"t":"str","hex":""},"rendered_hex":"","js_consistent":true,"js_hex":"JS","js_form":"direct","hint":"none","signals":[]}
{"case":3,"outcome":"value","value":{"t":"some","v":{"t":"f64","hi":1073217536,"lo":0}},"rendered_hex":"312e35","js_consistent":true,"js_hex":"JS","js_form":"direct","hint":"none","signals":[]}
{"case":4,"outcome":"value","value":{"t":"none"},"rendered_hex":"","js_consistent":true,"js_hex":"JS","js_form":"direct","hint":"none","signals":[]}
{"case":5,"outcome":"panic","class":"unwrap","msg_hex":"63616c6c656420604f7074696f6e3a3a756e77726170282960206f6e206120604e6f6e65602076616c7565","js_hex":"JS","js_form":"closure","hint":"none","signals":[]}
{"case":6,"outcome":"value","value":{"t":"f64","hi":1074003968,"lo":0},"rendered_hex":"322e35","js_consistent":true,"js_hex":"JS","js_form":"direct","hint":"none","signals":[{"id":3,"value":{"t":"f64","hi":1074003968,"lo":0},"debug_hex":"DBG"}]}
{"case":7,"outcome":"panic","class":"signal_write","msg_hex":"65787072657373696f6e7320696e2077686963682061207369676e616c206973207772697474656e20746f2063616e6e6f742062652072756e207365727665722d73696465","js_hex":"JS","js_form":"closure","hint":"none","signals":[{"id":4,"value":{"t":"bool","v":true},"debug_hex":"DBG"}]}
{"case":8,"outcome":"panic","class":"expect_err","msg_hex":"6e6f70653a20226f6b22","js_hex":"JS","js_form":"closure","hint":"expect_err","signals":[]}
{"case":9,"outcome":"panic","class":"expect","msg_hex":"626f6f6d","js_hex":"JS","js_form":"closure","hint":"expect","signals":[]}
{"case":10,"outcome":"panic","class":"other","msg_hex":"6e6f70653a20226f6b22","js_hex":"JS","js_form":"closure","hint":"both","signals":[]}
{"case":11,"outcome":"no_terminate","hint":"none"}
EXPECTED

if ! cmp -s "$OUT/seed.mask" "$OUT/seed.expected"; then
  print -r -- "M23 GATE RED: the seed value channel differs from the expected table" >&2
  diff -u "$OUT/seed.expected" "$OUT/seed.mask" | head -40 >&2
  exit 1
fi

# 5.  The JS channel, one shape per case.  A red here prints the
# decoded text, so the next round needs no rerun to read it.
check_js() {
  local idx="$1"
  local want="$2"
  local hexs
  local text
  hexs=$(rg -N "^\{\"case\":$idx," "$OUT/seed.jsonl" | sd '^.*"js_hex":"([0-9a-f]*)".*$' '$1')
  text=$(print -r -- "$hexs" | xxd -r -p)
  if ! print -r -- "$text" | rg -qF -- "$want"; then
    print -r -- "M23 GATE RED: the JS of seed case $idx lacks its expected substring" >&2
    print -r -- "  want: $want" >&2
    print -r -- "  got:  ${text[1,400]}" >&2
    exit 1
  fi
}

check_js 0 'return __external0;'
check_js 1 'cx.hydrate(&quot;a<b&gt;+c&quot;)'
check_js 2 'cx.hydrate(&quot;&quot;)'
check_js 3 '{&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:1.5}'
check_js 4 '{&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}'
check_js 5 'return () =&gt; '
check_js 6 '{&quot;t&quot;:&quot;Signal&quot;'
check_js 7 '{&quot;t&quot;:&quot;Signal&quot;'
check_js 8 'return () =&gt; '
check_js 9 'return () =&gt; '
check_js 10 'return () =&gt; '

# 5b.  The consistency verdict travels ON the line, so a resumed run
# cannot hide an inconsistent case between two segments.  The harness
# folds exit 4 and reports it after the range;  this check reads the
# JSONL itself and is therefore independent of the exit code.
BAD_SEED=$(rg -c '"js_consistent":false' "$OUT/seed.jsonl" || true)
[ -z "$BAD_SEED" ] || red "$BAD_SEED seed lines carry js_consistent false; the closure JS lost the direct body"

# 6.  The drawn batch.  Exit 3 here means the resume budget ran out.
if [ "$BATCH_EXIT" -eq 3 ]; then
  LAST=$(tail -n 1 "$OUT/batch.jsonl")
  red "the batch still timed out after $RESUMES resumes, which is the budget; last line: $LAST"
fi
if [ "$BATCH_EXIT" -ne 0 ]; then
  print -r -- "M23 GATE RED: the batch run exited $BATCH_EXIT, expected 0" >&2
  head -20 "$OUT/batch.err" >&2
  exit 1
fi

# 7.  One line per kept case, no more and no fewer.  Line 1 of the
# count sidecar is "<kept> <dropped>" and every later line is a
# "<reason> <n>" breakdown, so both numbers are read from line 1 ALONE:
# an awk over the whole file would concatenate the reason lines into
# KEPT and silently break the R9 drop accounting.
KEPT=$(awk 'NR == 1 { print $1 }' "$OUT/batch.count")
DROPPED=$(awk 'NR == 1 { print $2 }' "$OUT/batch.count")
BATCH_LINES=$(wc -l < "$OUT/batch.jsonl" | tr -d ' ')
[ -n "$KEPT" ] || red "the batch count sidecar is empty"
[ -n "$DROPPED" ] || red "the batch count sidecar has no dropped field on line 1"
[ $((KEPT + DROPPED)) -eq "$DRAW" ] || red "the count sidecar says $KEPT kept plus $DROPPED dropped, which is not the drawn $DRAW"
[ "$BATCH_LINES" -eq "$KEPT" ] || red "the batch wrote $BATCH_LINES lines for $KEPT kept cases"

# A drop is allowed but never silent, and a drop that costs more than
# five percent of the batch is a scope finding, not a pass.
if [ "$DROPPED" -gt 0 ]; then
  print -r -- "M23 note: the batch dropped $DROPPED of $((KEPT + DROPPED)) samples"
  if [ $((DROPPED * 20)) -gt $((KEPT + DROPPED)) ]; then
    red "the batch dropped $DROPPED samples, over five percent of the draw; that is a scope finding"
  fi
fi

# 8.  Every batch line carries JS, and no line lost its body.  The
# second check is what makes exit 4 survivable: the batch now folds 4
# and finishes the range, and the gate stitches resume segments
# together, so the line itself has to carry the verdict.
EMPTY_JS_B=$(rg -c '"js_hex":""' "$OUT/batch.jsonl" || true)
[ -z "$EMPTY_JS_B" ] || red "$EMPTY_JS_B batch lines carry an empty js_hex"
BAD_BATCH=$(rg -c '"js_consistent":false' "$OUT/batch.jsonl" || true)
[ -z "$BAD_BATCH" ] || red "$BAD_BATCH batch lines carry js_consistent false; the closure JS lost the direct body"

# 9.  An unclassified panic text is a spec gap.  The one exception is
# a body that carries BOTH expect and expect_err: its message is the
# user string either way, so the classifier cannot name the site and
# the line is expected to land in other (build brief R2).
OTHER=$(rg -N '"class":"other"' "$OUT/batch.jsonl" | rg -vc '"hint":"both"' || true)
[ -z "$OTHER" ] || red "$OTHER batch lines are class other without hint both; the classifier does not know that panic text"

# 10.  M20 must be untouched.
SHA=$(cat "$OUT/m20.sha")
[ "$SHA" = "$M20_SHA" ] || red "the M20 emitted lib.rs sha is $SHA, expected $M20_SHA; M23 changed shell/emit.ml"

NOTERM=$(rg -c '"outcome":"no_terminate"' "$OUT/batch.jsonl" || true)
[ -n "$NOTERM" ] || NOTERM=0

print -r -- "M23 GATE GREEN: seed 12/12 byte-exact on the value channel, exit 3;  batch $BATCH_LINES lines for $KEPT kept plus $DROPPED dropped of $DRAW, $NOTERM no_terminate over $RESUMES resumes, 0 empty js, 0 js_consistent false, 0 unexplained other;  m20 sha unchanged"
