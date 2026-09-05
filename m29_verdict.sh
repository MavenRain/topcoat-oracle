#!/bin/zsh
# M29 verdict (M29 spec section 9.2).  Reads the two printed walks of
# m29_gate.sh and turns them into one green line or one named red one.
#
# The expected text of both runs is DERIVED BY HAND in M29 spec section
# 8 from the shrinker's own rules, so this comparison is an independent
# check and not a recording of whatever the program printed.
set -e
OUT="$1"
ROOT="${0:A:h}"
REF_PLANT="ref:display_sign"
JS_PLANT="js:signal_get_plus_one"
REF_BOUND=1
JS_BOUND=3
M20_SHA="c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec"

red () { print -r -- "M29 GATE RED: $1"; exit 1; }

[[ -n "$OUT" && -d "$OUT" ]] || red "the output directory $OUT does not exist"

mkdir -p "$OUT/expected"
cat > "$OUT/expected/$REF_PLANT.txt" <<'EXPECTED'
m29 case: ref:display_sign
m29 start: read_only size 6 diverge:rendered:odd:ref
round 0 size 6 cands 4 accepted 0
round 1 size 4 cands 3 accepted 0
round 2 size 3 cands 2 accepted 0
round 3 size 2 cands 1 accepted 0
round 4 size 1 cands 0 accepted none
m29 body: 0.0
m29 verdict: read_only diverge:rendered:odd:ref
m29 size: 1
m29 stop: fixpoint rounds 5 candidates 10
m29 control: agree
EXPECTED
cat > "$OUT/expected/$JS_PLANT.txt" <<'EXPECTED'
m29 case: js:signal_get_plus_one
m29 start: read_only size 13 diverge:value:odd:js
round 0 size 13 cands 9 accepted 2
round 1 size 8 cands 6 accepted 1
round 2 size 6 cands 4 accepted 1
round 3 size 5 cands 3 accepted 1
round 4 size 4 cands 2 accepted 1
round 5 size 3 cands 1 accepted none
m29 body: v3.get()
m29 signal v3: f64 = 2.5
m29 verdict: read_only diverge:value:odd:js
m29 size: 3
m29 stop: fixpoint rounds 6 candidates 25
m29 control: agree
EXPECTED

accepted_rounds () {
  awk '$1 == "round" && $NF != "none" { n++ } END { print n + 0 }' "$1"
}
start_size () { awk '$2 == "start:" { print $5 }' "$1"; }
final_size () { awk '$2 == "size:" { print $3 }' "$1"; }
stop_word () { awk '$2 == "stop:" { print $3 }' "$1"; }
stop_line () { awk '$2 == "stop:" { print }' "$1"; }
control_word () { awk '$2 == "control:" { print $3 }' "$1"; }
# Field 5 and field 7 of the stop line are the round and candidate counts
# ONLY on a fixpoint or a fuel line.  A stuck line carries free reason
# text after the word, so these two are read after check 2 has already
# refused every stop word but fixpoint (M29 spec section 7.3).
rounds_of () { awk '$2 == "stop:" { print $5 }' "$1"; }
cands_of () { awk '$2 == "stop:" { print $7 }' "$1"; }

# 1.  Both runs exited 0.
for p in "$REF_PLANT" "$JS_PLANT"; do
  [[ -f "$OUT/$p/exit.txt" ]] || red "$p left no exit code; the run did not start"
  e="$(cat "$OUT/$p/exit.txt")"
  [[ "$e" == "0" ]] || red "$p exited $e, expected 0; read the stderr above"
done

# 2.  Both runs stopped on a FIXPOINT.  A fuel stop means the loop ran
#     out of rounds and the result is not minimal.  A STUCK stop means a
#     round got no verdict at all back from the legs, so the run was
#     blind and its small final sample means nothing; the whole stop
#     line is printed because a stuck line carries the named reason
#     after the word (M29 spec section 3, ruling Q8).  This check runs
#     BEFORE anything reads field 5 or field 7 of the stop line.
for p in "$REF_PLANT" "$JS_PLANT"; do
  s="$(stop_word "$OUT/$p/stdout.txt")"
  [[ "$s" == "fixpoint" ]] ||
    red "$p stopped on $s, expected fixpoint; the walk did not reach a minimum.  Its stop line: $(stop_line "$OUT/$p/stdout.txt")"
done

# 3.  At least three accepted rounds each (M29 spec R8), so the loop
#     really shrank and did not stop at the first candidate.
for p in "$REF_PLANT" "$JS_PLANT"; do
  a="$(accepted_rounds "$OUT/$p/stdout.txt")"
  [[ "$a" -ge 3 ]] ||
    red "$p accepted $a rounds, expected at least 3; the case is too easy"
done

# 4.  The final size is at or below the per-plant bound AND strictly
#     below the start size.
rs="$(start_size "$OUT/$REF_PLANT/stdout.txt")"
rf="$(final_size "$OUT/$REF_PLANT/stdout.txt")"
[[ "$rf" -le "$REF_BOUND" ]] ||
  red "$REF_PLANT minimized to size $rf, above the bound $REF_BOUND"
[[ "$rf" -lt "$rs" ]] ||
  red "$REF_PLANT did not shrink: start $rs, final $rf"
js="$(start_size "$OUT/$JS_PLANT/stdout.txt")"
jf="$(final_size "$OUT/$JS_PLANT/stdout.txt")"
[[ "$jf" -le "$JS_BOUND" ]] ||
  red "$JS_PLANT minimized to size $jf, above the bound $JS_BOUND"
[[ "$jf" -lt "$js" ]] ||
  red "$JS_PLANT did not shrink: start $js, final $jf"

# 5.  The control agrees.  A divergence that survives with no plant is
#     a pre-existing one and not the planted bug.  The control crate
#     directory must exist too: a control line the program can print
#     without running anything is not a control (M29 spec 13.3).
for p in "$REF_PLANT" "$JS_PLANT"; do
  [[ -d "$OUT/$p/rc" ]] ||
    red "$p wrote no control crate at rc; the control run did not happen"
  c="$(control_word "$OUT/$p/stdout.txt")"
  [[ -n "$c" ]] || red "$p printed no control line; the control run did not happen"
  [[ "$c" == "agree" ]] ||
    red "$p control is $c, expected agree; the minimized sample diverges with no plant"
done

# 6.  The reference walk, byte for byte.
cmp -s "$OUT/$REF_PLANT/stdout.txt" "$OUT/expected/$REF_PLANT.txt" ||
  red "$REF_PLANT stdout differs from the hand-derived walk; diff:
$(diff "$OUT/expected/$REF_PLANT.txt" "$OUT/$REF_PLANT/stdout.txt" || true)"

# 7.  The js walk, byte for byte.
cmp -s "$OUT/$JS_PLANT/stdout.txt" "$OUT/expected/$JS_PLANT.txt" ||
  red "$JS_PLANT stdout differs from the hand-derived walk; diff:
$(diff "$OUT/expected/$JS_PLANT.txt" "$OUT/$JS_PLANT/stdout.txt" || true)"

# 8.  The M20 emitter did not move.
got="$(cat "$OUT/m20.sha")"
[[ "$got" == "$M20_SHA" ]] ||
  red "the m20 emitter sha is $got, expected $M20_SHA; M29 must not touch M20"

print -r -- "M29 GATE GREEN: $REF_PLANT $(start_size "$OUT/$REF_PLANT/stdout.txt") to $rf in $(rounds_of "$OUT/$REF_PLANT/stdout.txt") rounds over $(cands_of "$OUT/$REF_PLANT/stdout.txt") candidates, $JS_PLANT $js to $jf in $(rounds_of "$OUT/$JS_PLANT/stdout.txt") rounds over $(cands_of "$OUT/$JS_PLANT/stdout.txt") candidates, both fixpoint, both controls agree, m20 sha unchanged"
