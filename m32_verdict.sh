#!/bin/zsh
# m32_verdict.sh: checks the bytes m32_gate.sh captured.  Fifteen checks, exit
# 1 on any red;  a check that loops over the three runs says which run, so one
# check can print more than one RED line.  Every string is compared by an rg
# shape or by cmp, never by eye.
set -e

OUT=$1
M31OUT=$2

RED=0

check () {
  local what=$1 got=$2 want=$3
  if cmp -s "$got" "$want"; then
    print -r -- "m32_verdict: ok $what"
  else
    print -r -- "m32_verdict: RED $what"
    diff -u "$want" "$got" | head -n 60
    RED=1
  fi
}

say_red () {
  print -r -- "m32_verdict: RED $1"
  RED=1
}

# mask_dir replaces the run directory of a report line, so two reports of two
# directories can be compared byte for byte.
mask_dir () {
  sd -- '^m32 check [^:]+:' 'm32 check DIR:' < "$1" > "$2"
}

# nojudge drops the LAST step of every trace line, so two traces can be
# compared on their walks up to the judge step.
nojudge () {
  sd -- ',"[a-z_]+"\]\}$' ']}' < "$1" > "$2"
}

# 1  the three positive checks exit 0 and print nothing on stderr
for d in straight resume planted; do
  [[ "$(cat "$OUT/$d.code")" == 0 ]] \
    || say_red "$d check exit $(cat "$OUT/$d.code") want 0"
  [[ ! -s "$OUT/$d.stderr" ]] || say_red "$d check wrote stderr"
done

# 2  the three reports are the hand derived goldens
cat > "$OUT/straight.report.want" <<'REP'
m32 check DIR: 500 lines, dropped_agree 77, dropped_known 0, minimizing_hi 10, gen_bug 0, leg_failed 413, oracle_bug 0
REP
cat > "$OUT/planted.report.want" <<'REP'
m32 check DIR: 100 lines, dropped_agree 14, dropped_known 0, minimizing_hi 3, gen_bug 0, leg_failed 83, oracle_bug 0
REP
mask_dir "$OUT/straight.stdout" "$OUT/straight.report"
mask_dir "$OUT/resume.stdout" "$OUT/resume.report"
mask_dir "$OUT/planted.stdout" "$OUT/planted.report"
check "straight report" "$OUT/straight.report" "$OUT/straight.report.want"
check "resume report equals straight" "$OUT/resume.report" "$OUT/straight.report"
check "planted report" "$OUT/planted.report" "$OUT/planted.report.want"

# 3  the report counts equal the tally of the straight journal's heads.  Each
# read carries "|| true", because a failed parse leaves an empty file, a read
# of an empty file answers non zero, and this script is "set -e": without the
# guard one broken summary line would end the run and hide checks 4 to 15.
# The parse failure itself is already RED through say_red above.  A failed
# read leaves its variables EMPTY, and zsh reads an empty variable in
# arithmetic as 0, so both tally files would hold the same bytes and this
# check would print a passing line for a run it measured nothing on.  The
# shape test below therefore runs BEFORE any arithmetic and requires all
# thirteen fields to be digits;  a run that fails it is RED by its own reason
# line and never reaches the "check" call.  The test is the condition of an
# "if", which "set -e" does not act on, so a red here still runs 4 to 15.
rg -o -r '$1 $2 $3 $4 $5 $6 $7' \
  -- '^m31 agree ([0-9]+) known ([0-9]+) diverge ([0-9]+) leg_fail ([0-9]+) dropped ([0-9]+) no_line ([0-9]+) batch_fail ([0-9]+) other [0-9]+$' \
  "$M31OUT/straight.stdout" > "$OUT/m31.counts" \
  || say_red "the m31 straight summary line did not parse"
read -r A K DV LF DR NL BF < "$OUT/m31.counts" || true
rg -o -r '$1 $2 $3 $4 $5 $6' \
  -- '^m32 check [^:]+: [0-9]+ lines, dropped_agree ([0-9]+), dropped_known ([0-9]+), minimizing_hi ([0-9]+), gen_bug ([0-9]+), leg_failed ([0-9]+), oracle_bug ([0-9]+)$' \
  "$OUT/straight.stdout" > "$OUT/m32.counts" \
  || say_red "the m32 straight report line did not parse"
read -r DA DK MH GB LFD OB < "$OUT/m32.counts" || true
DIGIT='^[0-9]+$'
if [[ $A =~ $DIGIT && $K =~ $DIGIT && $DV =~ $DIGIT && $LF =~ $DIGIT \
      && $DR =~ $DIGIT && $NL =~ $DIGIT && $BF =~ $DIGIT \
      && $DA =~ $DIGIT && $DK =~ $DIGIT && $MH =~ $DIGIT \
      && $GB =~ $DIGIT && $LFD =~ $DIGIT && $OB =~ $DIGIT ]]; then
  print -r -- "$A $K $DV $(( DR + LF + NL + BF ))" > "$OUT/tally.want"
  print -r -- "$DA $DK $MH $(( GB + LFD + OB ))" > "$OUT/tally.got"
  check "report counts against the journal tally" "$OUT/tally.got" "$OUT/tally.want"
else
  say_red "the report counts did not parse into thirteen numbers"
fi

# 4  the resumed trace is the straight trace, byte for byte
check "resume trace" "$M31OUT/resume/trace.jsonl" "$M31OUT/straight/trace.jsonl"

# 5  the two headers of every run agree on their four fields
for d in straight resume planted; do
  head -n 1 "$M31OUT/$d/journal.jsonl" \
    | sd -- '^\{"m31":1,' '{' > "$OUT/$d.jhead.fields"
  head -n 1 "$M31OUT/$d/trace.jsonl" \
    | sd -- '^\{"m32":1,' '{' > "$OUT/$d.thead.fields"
  check "$d header fields" "$OUT/$d.thead.fields" "$OUT/$d.jhead.fields"
done

# 6  the planted trace walks like the straight trace up to the judge step,
#    and its body is expected to differ on 0 lines.  m31_verdict.sh:96
#    compares the planted journal against the straight journal byte for byte
#    outside the f cell, and m31_verdict.sh:84-91 rules (R-B1) that all nine
#    f cell flips lose the js leg, so no verdict moves.  A row's step names
#    follow its cell presence and its verdict head, so no judge step moves
#    either and the two bodies agree byte for byte.
tail -n +2 "$M31OUT/straight/trace.jsonl" | head -n 100 > "$OUT/straight.trace.first100"
tail -n +2 "$M31OUT/planted/trace.jsonl" > "$OUT/planted.trace.body"
nojudge "$OUT/straight.trace.first100" "$OUT/straight.trace.first100.nj"
nojudge "$OUT/planted.trace.body" "$OUT/planted.trace.body.nj"
check "planted trace outside the judge step" \
  "$OUT/planted.trace.body.nj" "$OUT/straight.trace.first100.nj"
#    The bound below is the EXACT pin.  The first green ladder measured
#    TFLIP 0 in "$OUT/planted.trace.flips", the value section 12 derives, so
#    the closing stage replaced the loose first run bound with this line and
#    re ran the gate to green (section 13, the closing step, and section 14
#    item 8).  A measured count other than 0 is a finding: the derivation of
#    section 12 is then what is wrong.
TFLIP=$(diff "$OUT/straight.trace.first100" "$OUT/planted.trace.body" | rg -c -- '^>' || print -r -- 0)
print -r -- "$TFLIP" > "$OUT/planted.trace.flips"
[[ $TFLIP -eq 0 ]] || say_red "planted trace differs on $TFLIP lines want 0"

# 7  the seven negatives exit 1 and print nothing on stdout;  the six awk
#    mutations each changed exactly one line and N6 proved its substitution
for k in 1 2 3 4 5 6 7; do
  [[ "$(cat "$OUT/neg$k.code")" == 1 ]] \
    || say_red "negative $k exit $(cat "$OUT/neg$k.code") want 1"
  [[ ! -s "$OUT/neg$k.stdout" ]] || say_red "negative $k wrote stdout"
done
for k in 1 2 3 4 5 7; do
  [[ "$(cat "$OUT/neg$k.mutated")" == 1 ]] \
    || say_red "negative $k changed $(cat "$OUT/neg$k.mutated") lines want 1"
done
[[ "$(cat "$OUT/neg6.mutated")" == shape ]] \
  || say_red "negative 6 mutation $(cat "$OUT/neg6.mutated") want shape"

# 8  each negative said what it was supposed to say
rg -q -- '^m32 failure: line [0-9]+: the judge step judge_known does not match the verdict head agree$' \
  "$OUT/neg1.stderr" || say_red "negative 1 text"
rg -q -- '^m32 failure: line [0-9]+: the judge step judge_agree does not match the verdict head known$' \
  "$OUT/neg2.stderr" || say_red "negative 2 text"
rg -q -- '^m32 failure: line [0-9]+: the step exec_ref_ok is not an edge from stage=compiled rust=o js=p ref=p verdict=none$' \
  "$OUT/neg3.stderr" || say_red "negative 3 text"
rg -q -- '^m32 failure: line [0-9]+: the step exec_js_okay is not a step of model/frame\.ml$' \
  "$OUT/neg4.stderr" || say_red "negative 4 text"
rg -q -- '^m32 failure: line 1: the journal holds 500 sample lines and the trace holds 499$' \
  "$OUT/neg5.stderr" || say_red "negative 5 text"
rg -q -- '^m32 failure: line 1: the trace header says plant ref:display_sign and the journal header says plant none$' \
  "$OUT/neg6.stderr" || say_red "negative 6 text"
rg -q -- '^m32 failure: line [0-9]+: a diverge verdict must not end in filed$' \
  "$OUT/neg7.stderr" || say_red "negative 7 text"

# 9  the two usage negatives exit 2 and print nothing on stdout
[[ "$(cat "$OUT/neg.absent.code")" == 2 ]] \
  || say_red "absent directory exit $(cat "$OUT/neg.absent.code") want 2"
[[ "$(cat "$OUT/neg.verb.code")" == 2 ]] \
  || say_red "bad verb exit $(cat "$OUT/neg.verb.code") want 2"
rg -q -- '^m32 usage: there is no file at .*/nothere/journal\.jsonl$' \
  "$OUT/neg.absent.stderr" || say_red "absent directory text"
rg -q -- '^m32 usage: m32 check <dir>$' "$OUT/neg.verb.stderr" \
  || say_red "bad verb text"
[[ ! -s "$OUT/neg.absent.stdout" ]] || say_red "absent directory wrote stdout"
[[ ! -s "$OUT/neg.verb.stdout" ]] || say_red "bad verb wrote stdout"

# 10  the negatives touched COPIES only
check "straight journal after the negatives" \
  "$M31OUT/straight/journal.jsonl" "$OUT/straight.journal.copy"
check "straight trace after the negatives" \
  "$M31OUT/straight/trace.jsonl" "$OUT/straight.trace.copy"

# 11  the earlier ladder is unedited and green, and the new suite is 13 of 13
rg -q -- '^m31_verdict: GREEN$' "$OUT/m31.log" || say_red "m31 gate is not green"
rg -q -- '^test_correspond: 13/13$' "$OUT/test.log" || say_red "test_correspond is not 13/13"
rg -q -- '^test_journal: 7/7$' "$OUT/test.log" || say_red "test_journal is not 7/7"

# 12  every trace holds one header and one line per journal sample
for d in straight resume planted; do
  JL=$(wc -l < "$M31OUT/$d/journal.jsonl" | tr -d ' ')
  TL=$(wc -l < "$M31OUT/$d/trace.jsonl" | tr -d ' ')
  [[ $JL -eq $TL ]] || say_red "$d journal lines $JL trace lines $TL"
done

# 13  every trace line of the straight AND of the planted run names a step
#     vocabulary the model knows.  The alternation closes over the WHOLE list,
#     so a bogus second or later step is caught too, and the header is skipped
#     before the match and not after.  The planted run writes its own
#     trace.jsonl beside its own journal.jsonl: section 4.9's `run` binds
#     `let tpath = trace_path c.p_dir` and section 4.8's `fresh_open` writes
#     the trace header at that path.  The planted file needs its own guard,
#     because check 6 reads it only after `nojudge` has dropped the last step
#     of every line, so its 100 judge steps are outside every other byte
#     comparison of this verdict.  The resumed trace needs none: check 4 pins
#     it byte equal to the straight trace.  Either file failing is RED.
SN='(shape_ok|shape_fail|print_ok|compile_ok|compile_fail|exec_rust_ok|exec_rust_crash|exec_js_ok|exec_js_crash|exec_ref_ok|exec_ref_crash|judge_agree|judge_diverge|judge_known|judge_infra|file_unjudged|shrink|shrink_done|stay)'
PAT='^\{"i":[0-9]+,"steps":\["'"$SN"'"(,"'"$SN"'")*\]\}$'
for d in straight planted; do
  tail -n +2 "$M31OUT/$d/trace.jsonl" \
    | rg -v -- "$PAT" > "$OUT/$d.trace.odd" || true
  [[ ! -s "$OUT/$d.trace.odd" ]] || say_red "the $d trace holds an unknown step shape"
done

# 14  the R9b finding as a CONTRADICTION and not as an absolute count: no row
#     pairs an exec_rust_crash step with a NON EMPTY journal r cell.  An
#     exec_rust_crash step is legitimate on a K3 or a K4 row, whose r cell is
#     empty, and a non empty r cell is legitimate on a K5 row, whose trace
#     holds exec_rust_ok.  Only the PAIR is impossible, and that pair is
#     exactly the R9b row: a rust observation the journal kept and a rust leg
#     the trace crashed.  Line k of the trace pairs with line k of the
#     journal, which check 12 already proves is one line per sample.
for d in straight resume planted; do
  N=$(awk 'NR == FNR { if (FNR > 1) t[FNR] = $0; next }
           FNR > 1 && index(t[FNR], "\"exec_rust_crash\"") > 0 \
             && index($0, "\"r\":\"\"") == 0 { c++ }
           END { print c + 0 }' \
        "$M31OUT/$d/trace.jsonl" "$M31OUT/$d/journal.jsonl")
  [[ $N -eq 0 ]] \
    || say_red "$d pairs $N rows with a non empty r cell and an exec_rust_crash step want 0"
done

# 15  the mirror contradiction of check 14, on the same pairing: no row pairs
#     an exec_rust_ok step with an EMPTY journal r cell.  Check C3 refuses
#     that row line by line;  this check states it as one corpus count, so a
#     checker that stopped running still leaves the fact pinned.
for d in straight resume planted; do
  N=$(awk 'NR == FNR { if (FNR > 1) t[FNR] = $0; next }
           FNR > 1 && index(t[FNR], "\"exec_rust_ok\"") > 0 \
             && index($0, "\"r\":\"\"") > 0 { c++ }
           END { print c + 0 }' \
        "$M31OUT/$d/trace.jsonl" "$M31OUT/$d/journal.jsonl")
  [[ $N -eq 0 ]] \
    || say_red "$d pairs $N rows with an empty r cell and an exec_rust_ok step want 0"
done

[[ $RED -eq 0 ]] || exit 1
print -r -- "m32_verdict: GREEN"
