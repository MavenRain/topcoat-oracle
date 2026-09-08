#!/bin/zsh
# m31_verdict.sh: checks the bytes m31_gate.sh captured.  Thirteen checks, one
# RED line each, exit 1 on any red.
set -e

OUT=$1

CLONE_SHA=51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
M20_SHA=c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec

RED=0

# The one mask: the journal spelling of the clone sha, and only after that sha
# has been pinned by rg (ruling C5).  The summary spelling needs no rule: the
# summary is matched by rg SHAPE and never compared as bytes (ruling G4).
mask () {
  sd -- '"topcoat":"[0-9a-f]{40}"' '"topcoat":"SHA40"' < "$1" > "$2"
}

check () {
  local what=$1 got=$2 want=$3
  if cmp -s "$got" "$want"; then
    print -r -- "m31_verdict: ok $what"
  else
    print -r -- "m31_verdict: RED $what"
    diff -u "$want" "$got" | head -n 60
    RED=1
  fi
}

say_red () {
  print -r -- "m31_verdict: RED $1"
  RED=1
}

J="$OUT/straight/journal.jsonl"
RJ="$OUT/resume/journal.jsonl"
PJ="$OUT/planted/journal.jsonl"

# 1  the exit codes of the four negatives
[[ "$(cat "$OUT/neg.seed.code")" == 1 ]] || say_red "negative wrong seed exit $(cat "$OUT/neg.seed.code") want 1"
[[ "$(cat "$OUT/neg.replay.code")" == 1 ]] || say_red "negative replay exit $(cat "$OUT/neg.replay.code") want 1"
[[ "$(cat "$OUT/neg.samples.code")" == 2 ]] || say_red "negative no samples exit $(cat "$OUT/neg.samples.code") want 2"
[[ "$(cat "$OUT/neg.batch.code")" == 2 ]] || say_red "negative batch zero exit $(cat "$OUT/neg.batch.code") want 2"

# 2  the straight journal is one header and 500 sample lines
LINES=$(wc -l < "$J" | tr -d ' ')
[[ $LINES -eq 501 ]] || say_red "straight journal lines $LINES want 501"

# 3  the clone sha is pinned, then the header equals the golden
rg -q -- "\"topcoat\":\"$CLONE_SHA\"" "$J" || say_red "straight header clone sha is not $CLONE_SHA"
head -n 1 "$J" > "$OUT/straight.header"
mask "$OUT/straight.header" "$OUT/straight.header.masked"
cat > "$OUT/straight.header.want" <<'HDR'
{"m31":1,"seed":5059377,"batch":100,"plant":"none","topcoat":"SHA40"}
HDR
check "straight header" "$OUT/straight.header.masked" "$OUT/straight.header.want"

# 4  the indices are 0 .. 499, contiguous, in order
tail -n +2 "$J" | sd -- '^\{"i":([0-9]+),.*$' '$1' > "$OUT/straight.idx"
seq 0 499 > "$OUT/straight.idx.want"
check "straight contiguity" "$OUT/straight.idx" "$OUT/straight.idx.want"

# 5  replay of the straight run prints the run's own stdout
check "straight replay stdout" "$OUT/replay.straight.stdout" "$OUT/straight.stdout"

# 6  replay of the resumed run prints the second invocation's stdout
check "resume replay stdout" "$OUT/replay.resume.stdout" "$OUT/resume2.stdout"

# 7  the resumed journal is the straight journal, byte for byte
check "resume journal" "$RJ" "$J"

# 8  no batch failed and no verdict head was unknown
rg -q -- '^m31 agree [0-9]+ known [0-9]+ diverge [0-9]+ leg_fail [0-9]+ dropped [0-9]+ no_line [0-9]+ batch_fail 0 other 0$' "$OUT/straight.stdout" \
  || say_red "straight summary has a batch_fail or an other"
rg -q -- '^m31 journal .*/straight/journal\.jsonl lines 500$' "$OUT/straight.stdout" \
  || say_red "straight summary does not close on 500 lines"

# 9  the planted run found the plant, and all three journals pin the clone sha
rg -q -- "\"topcoat\":\"$CLONE_SHA\"" "$PJ" \
  || say_red "planted header clone sha is not $CLONE_SHA"
rg -q -- "\"topcoat\":\"$CLONE_SHA\"" "$RJ" \
  || say_red "resume header clone sha is not $CLONE_SHA"
# M39 recovers these previously lost comparisons. The independent checker
# pins all nine float witnesses and their sign mutations, derives the eight
# rendered splits and the one pre-existing outcome split, and requires every
# program, environment and product-leg cell to remain unchanged.
python3 -P "${0:A:h}/m31_plant_verdict.py" "$J" "$PJ" \
  || say_red "planted journal reference mutation or verdict mismatch"
rg -q -- '^m31 seed 0x4d3331 samples 100 batch 100 plant ref:display_sign topcoat [0-9a-f]{40}$' "$OUT/planted.stdout" \
  || say_red "planted summary head is wrong"

# 10  the refused run left the journal untouched
check "journal after the refused run" "$J" "$OUT/straight.journal.copy"

# 11  the negatives said what they were supposed to say
rg -q -- '^m31 failure: the journal at .*/straight/journal\.jsonl was written with seed 0x4d3331 .* this run asked for seed 0x4d3332 ' "$OUT/neg.seed.stderr" \
  || say_red "negative wrong seed text"
rg -q -- '^m31 failure: there is no journal at .*/nothere/journal\.jsonl$' "$OUT/neg.replay.stderr" \
  || say_red "negative replay text"
rg -q -- '^m31 usage: run needs --samples N$' "$OUT/neg.samples.stderr" \
  || say_red "negative no samples text"
rg -q -- '^m31 usage: --batch wants an integer of 1 or more: 0$' "$OUT/neg.batch.stderr" \
  || say_red "negative batch zero text"
[[ ! -s "$OUT/neg.seed.stdout" ]] || say_red "negative wrong seed wrote stdout"
[[ ! -s "$OUT/neg.replay.stdout" ]] || say_red "negative replay wrote stdout"
[[ ! -s "$OUT/neg.samples.stdout" ]] || say_red "negative no samples wrote stdout"
[[ ! -s "$OUT/neg.batch.stdout" ]] || say_red "negative batch zero wrote stdout"

# 12  the earlier ladder is unedited and green, and the new suite is 7 of 7.
# The suite prints its own count line, so the count line is pinned and not an
# "^ok " tally: dune runtest prints every suite of the repository, and
# m31_gate.sh runs it with --force, because dune answers a cached runtest with
# an empty log.
rg -q -- '^m30_verdict: GREEN$' "$OUT/m30.log" || say_red "m30 gate is not green"
CRATES=$(rg --files "$OUT" -g Cargo.toml | wc -l | tr -d ' ')
[[ $CRATES -eq 12 ]] || say_red "batch crate directory count $CRATES want 12"
rg -q -- '^test_journal: 7/7$' "$OUT/test.log" || say_red "test_journal is not 7/7"

# 13  every no_terminate cell is pinned, and every rust timeout is a loop
# A no_terminate observation is encoded "T" by Obs.encode_outcome
# (core/obs.ml:78) and the whole cell reads T|r<len>:<rendered>| through
# the field value prefix T|r on any of the three cells r, j and f.  The rust
# harness writes it when a case passes the 2000 ms wall clock
# (driver-rs/harness.rs:773, shell/rust_leg.ml:85) and the reference
# interpreter writes it when a case spends its 10000 fuel
# (shell/ref_leg.ml:26).  This corpus holds seven such lines in the straight
# journal and the same seven in the resumed one (i = 190, 278, 301, 339, 449,
# 450 and 479: seven f cells, four r cells, eleven cells), and none in the
# planted one.  The count is pinned per journal, and every r cell that reads
# T sits on a line whose f cell reads T too: a rust timeout on a line the
# reference finished within its fuel would be the clock artifact section
# 16.1 step 2 names, and stays red (ruling R-B2).
noterm_cells () { rg -o -- '"[rjf]":"T\|r' "$1" | wc -l | tr -d ' '; }
rust_t_lines () { rg -- '"r":"T\|r' "$1" | wc -l | tr -d ' '; }
loop_lines () { rg -- '"r":"T\|r.*"f":"T\|r' "$1" | wc -l | tr -d ' '; }
[[ $(noterm_cells "$J") -eq 11 ]] || say_red "straight no_terminate cells $(noterm_cells "$J") want 11"
[[ $(noterm_cells "$RJ") -eq 11 ]] || say_red "resume no_terminate cells $(noterm_cells "$RJ") want 11"
[[ $(noterm_cells "$PJ") -eq 0 ]] || say_red "planted no_terminate cells $(noterm_cells "$PJ") want 0"
[[ $(rust_t_lines "$J") -eq 4 && $(loop_lines "$J") -eq 4 ]] \
  || say_red "straight rust timeouts $(rust_t_lines "$J") loops $(loop_lines "$J") want 4 and 4"
[[ $(rust_t_lines "$RJ") -eq 4 && $(loop_lines "$RJ") -eq 4 ]] \
  || say_red "resume rust timeouts $(rust_t_lines "$RJ") loops $(loop_lines "$RJ") want 4 and 4"

print -r -- "m31_verdict: M20_SHA=$M20_SHA"
[[ $RED -eq 0 ]] || exit 1
print -r -- "m31_verdict: GREEN"
