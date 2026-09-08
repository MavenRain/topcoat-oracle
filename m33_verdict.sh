#!/bin/zsh
# m33_verdict.sh: checks the bytes m33_gate.sh captured.  Fifteen checks, exit 1
# on any red.  Every comparison is a cmp against a heredoc golden or an rg
# shape.  The goldens are hand derived in M33 spec section 10 and are never
# regenerated from a run.
set -e

OUT=$1
M31OUT=$2
# The clone revision m33_gate.sh:32 pins, passed on by m33_gate.sh:191.  Check
# 14 binds every journal header to it, so a journal written against another
# checkout of the target is a red gate and not silent evidence.
REV=$3

RED=0

check () {
  local what=$1 got=$2 want=$3
  if cmp -s "$got" "$want"; then
    print -r -- "m33_verdict: ok $what"
  else
    print -r -- "m33_verdict: RED $what"
    diff -u "$want" "$got" | head -n 60
    RED=1
  fi
}

say_red () {
  print -r -- "m33_verdict: RED $1"
  RED=1
}

# 1  the two positives exit 0 and write nothing on stderr
for v in render cite; do
  [[ "$(cat "$OUT/$v.code")" == 0 ]] \
    || say_red "$v exit $(cat "$OUT/$v.code") want 0"
  [[ ! -s "$OUT/$v.stderr" ]] || say_red "$v wrote stderr"
done

# 2  KNOWN.md is the render, byte for byte (ruling R4)
check "KNOWN.md equals the render" KNOWN.md "$OUT/render.md"

# 3  the cite report is the hand derived golden (M33 spec 10.2)
cat > "$OUT/cite.want" <<'CITE'
ok I1 core/interp.ml:244-251
ok I2 driver-js/lib/classify.mjs:16-19
ok W-f64-display crates/topcoat-runtime/browser/src/surrogate/f64.ts:40-51
ok W-string-order crates/topcoat-runtime/browser/src/surrogate/string.ts:16-20
ok W-string-trim crates/topcoat-runtime/browser/src/surrogate/string.ts:7-14
ok W-nan-null research/m23-driver-probe.md:253-255
ok W-integral-f64 research/m23-driver-probe.md:256-259
ok X-signal-arity driver-js/lib/signals.mjs:96-99
ok X-no-js driver-js/lib/line.mjs:331-338
ok X-js-syntax driver-js/worker.mjs:337-340
ok X-js-type crates/topcoat-runtime/browser/src/surrogate/signal.ts:35-37
CITE
check "cite report" "$OUT/cite.stdout" "$OUT/cite.want"

# 4  the straight census includes the M39 comparisons recovered from the
# original signal-arity losses. Check 14 derives it independently from rows.
cat > "$OUT/straight.census.want" <<'CEN'
agree 395
diverge:class:two_way 1
diverge:message:odd:js 32
diverge:message:two_way 17
diverge:outcome:odd:js 2
diverge:signals:two_way 1
diverge:value:odd:js 1
leg_fail:js:js_error:11:SyntaxError:24:Unexpected token 'while' 47
leg_fail:js:skipped:no_js 4
CEN
check "straight census" "$OUT/straight.census" "$OUT/straight.census.want"

# 5  the planted census is the hand derived golden
cat > "$OUT/planted.census.want" <<'CEN'
agree 68
diverge:message:odd:js 7
diverge:message:two_way 4
diverge:outcome:odd:js 1
diverge:rendered:odd:ref 8
leg_fail:js:js_error:11:SyntaxError:24:Unexpected token 'while' 12
CEN
check "planted census" "$OUT/planted.census" "$OUT/planted.census.want"

# 6  the resumed run agrees with the straight run
check "resume census equals straight" "$OUT/resume.census" "$OUT/straight.census"

# 7  the I2 shape is LIVE and no row of it is left on the class channel.  The
# wanted count is DERIVED from the census of the same run and not from a
# second constant beside the golden, so one edit cannot move both.  rg reads
# the journal line by line and the census went through awk, sort and uniq, so
# the two routes must still agree.
for d in straight planted; do
  N=$(rg -c -- '"verdict":"diverge:message:' "$M31OUT/$d/journal.jsonl" || print -r -- 0)
  WANT=$(awk '$1 ~ /^diverge:message:/ { s += $NF } END { print s + 0 }' \
           "$OUT/$d.census")
  [[ $N -eq $WANT ]] \
    || say_red "$d holds $N message rows, its census counts $WANT"
  if rg -q -- '"verdict":"diverge:class:odd:js"' "$M31OUT/$d/journal.jsonl"
  then
    say_red "$d still holds a diverge:class:odd:js row"
  fi
done

# 8  the one class row M33 does NOT excuse is still reported (M33 spec 10.5).
# The count itself is pinned by the golden of check 4;  this check only
# requires the journal and its census to agree on it.
N=$(rg -c -- '"verdict":"diverge:class:two_way"' \
      "$M31OUT/straight/journal.jsonl" || print -r -- 0)
WANT=$(awk '$1 == "diverge:class:two_way" { s += $NF } END { print s + 0 }' \
         "$OUT/straight.census")
[[ $N -eq $WANT ]] \
  || say_red "straight holds $N unexcused class rows, its census counts $WANT"

# 9  the two root negatives: exit 1, empty stdout, the named row on stderr
[[ "$(cat "$OUT/neg1.code")" == 1 ]] \
  || say_red "neg1 exit $(cat "$OUT/neg1.code") want 1"
[[ ! -s "$OUT/neg1.stdout" ]] || say_red "neg1 wrote stdout"
rg -q -- '^m33 cite failure: W-f64-display: there is no file at ' \
  "$OUT/neg1.stderr" || say_red "neg1 stderr does not name W-f64-display"
[[ "$(cat "$OUT/neg2.code")" == 1 ]] \
  || say_red "neg2 exit $(cat "$OUT/neg2.code") want 1"
[[ ! -s "$OUT/neg2.stdout" ]] || say_red "neg2 wrote stdout"
rg -q -- '^m33 cite failure: I1: there is no file at ' \
  "$OUT/neg2.stderr" || say_red "neg2 stderr does not name I1"

# 10  the three usage negatives: exit 2, empty stdout, the usage line
for k in 3 4 5; do
  [[ "$(cat "$OUT/neg$k.code")" == 2 ]] \
    || say_red "neg$k exit $(cat "$OUT/neg$k.code") want 2"
  [[ ! -s "$OUT/neg$k.stdout" ]] || say_red "neg$k wrote stdout"
  rg -q -- '^m33 usage: m33 render \| m33 cite <clone-root> <repo-root>$' \
    "$OUT/neg$k.stderr" || say_red "neg$k stderr is not the usage line"
done

# 11  the render comparison bites: one mutated line, and cmp says so
[[ "$(cat "$OUT/neg6.mutated")" == 1 ]] \
  || say_red "neg6 mutated $(cat "$OUT/neg6.mutated") lines want 1"
if cmp -s "$OUT/neg6.md" "$OUT/render.md"; then
  say_red "neg6 mutated KNOWN.md still compares equal to the render"
else
  print -r -- "m33_verdict: ok neg6 rejected"
fi

# 12  the QUOTE check bites: the cited file is present and long enough, the
# needle came from the RENDER and not from a copy of it, the real file holds
# it and the mutated copy does not, the copy keeps the line count so the I1
# range is still in bounds, and cite exits 1 with empty stdout and the named
# row and reason on stderr
[[ "$(cat "$OUT/neg7.needle")" == "$(rg -o -N -r '$1' -e '^- quote: (.+)$' KNOWN.md | head -n 1)" ]] \
  || say_red "neg7 needle is not the rendered I1 quote"
[[ "$(cat "$OUT/neg7.quote.before")" -ge 1 ]] \
  || say_red "the cited file does not hold the I1 quote before the mutation"
[[ "$(cat "$OUT/neg7.quote")" == 0 ]] \
  || say_red "neg7 file still holds the I1 quote"
[[ "$(cat "$OUT/neg7.lines")" == "$(cat "$OUT/neg7.lines.before")" ]] \
  || say_red "neg7 moved the line count of the cited file"
[[ "$(cat "$OUT/neg7.lines")" -ge 251 ]] \
  || say_red "neg7 file holds $(cat "$OUT/neg7.lines") lines, short of the I1 range"
[[ "$(cat "$OUT/neg7.code")" == 1 ]] \
  || say_red "neg7 exit $(cat "$OUT/neg7.code") want 1"
[[ ! -s "$OUT/neg7.stdout" ]] || say_red "neg7 wrote stdout"
rg -q -- '^m33 cite failure: I1: the quote is not in core/interp\.ml:244-251: ' \
  "$OUT/neg7.stderr" || say_red "neg7 stderr does not reject the I1 quote"

# 13  the document carries its three headings and one cite per row
for h in '^## Entries$' '^## Documented, not excused today$' \
         '^## Not on the allowlist$'; do
  rg -q -- "$h" KNOWN.md || say_red "KNOWN.md has no heading matching $h"
done
N=$(rg -c -- '^- cite: ' KNOWN.md || print -r -- 0)
[[ $N -eq 11 ]] || say_red "KNOWN.md carries $N cite lines want 11"
N=$(rg -c -- '^- quote: ' KNOWN.md || print -r -- 0)
[[ $N -eq 11 ]] || say_red "KNOWN.md carries $N quote lines want 11"
# The hook assertion pins the POSITION as well as the text: m33_gate.sh must
# be the line that follows m32_gate.sh, and gates.sh must still abort on a
# red gate.  Text alone would stay green if the call moved above m32 or if
# gates.sh dropped set -e.
rg -q -U -- '^"\$ROOT/m32_gate\.sh"\n"\$ROOT/m33_gate\.sh"$' gates.sh \
  || say_red "gates.sh does not run m33_gate.sh right after m32_gate.sh"
rg -q -- '^set -e$' gates.sh || say_red "gates.sh does not set -e"
# set -e is only as good as its last word: a later set +e turns the ladder
# into a best effort run in which a red rung is a printed line and nothing
# else.
if rg -q -- '^set \+e$' gates.sh; then
  say_red "gates.sh turns set -e off"
fi
# The ladder driver must PROVE its opam switch exists before it selects it,
# with the same name m33_gate.sh:18-23 uses.  eval "$(opam env --switch=absent
# ...)" evaluates an empty string and returns 0, so a missing switch is
# invisible to set -e and every rung builds under the ambient switch.
# The pattern spans the WHOLE guard, up to and including the exit.  The first
# two lines alone leave the body free: a guard whose exit 1 became a colon
# still prints the red line, still returns 0, and every rung then builds under
# the ambient switch.  That one edit is the exact hazard, so the pin ends at
# the exit and at the closing brace.
rg -q -U -- '^SWITCH=anvil-ocaml\nopam switch list --short \| rg -qx -- "\$SWITCH" \|\| \{\n  print -r -- "gates: RED opam switch \$SWITCH is not installed"\n  exit 1\n\}$' \
  gates.sh || say_red "gates.sh does not prove its opam switch before selecting it"
# The last rung carries the same guard with its own name, so pin it the same
# way and for the same reason.
rg -q -U -- '^SWITCH=anvil-ocaml\nopam switch list --short \| rg -qx -- "\$SWITCH" \|\| \{\n  print -r -- "m33_gate: RED opam switch \$SWITCH is not installed"\n  exit 1\n\}$' \
  m33_gate.sh || say_red "m33_gate.sh does not prove its opam switch before selecting it"
if rg -q -- 'switch=karamel-710' gates.sh; then
  say_red "gates.sh still selects the karamel-710 switch"
fi

# 14  the journals are m31 journals, and the census IS the census of them.
# Checks 4 to 8 are counts of ONE field, so a hand written file that holds the
# golden multiplicities and nothing else passes all of them.  Bind each census
# to the journal that produced it.
#   - line 1 must be the m31 header bin/m31.ml writes
#     (core/journal.ml:130-137) and it must name the clone revision the gate
#     pins, so no journal of another checkout is accepted;
#   - every other line must be the NINE row fields in the ONE order
#     core/journal.ml:141-153 writes them, with a JSON string in every string
#     place, so a reordered row and a padded tenth field are both rejected;
#   - the i column must be the corpus index 0 to N-1 that
#     core/journal.ml:283-299 replays, so a constant i is rejected;
#   - the census must agree with the journal VERDICT BY VERDICT and not on
#     the total alone;
#   - the row count must equal the corpus size the run pins.
# The seed, the batch and the plant of the header stay FREE on purpose: the
# census goldens of checks 4 to 6 are the goldens of m31_gate.sh:16-18, and a
# run at another seed moves those counts, so the goldens already reject it.
# The revision does not move any count, which is why it needs its own pin.
# The row pattern is built once in BEGIN out of the JSON string shape
# ["([^"\]|\.)*"], because a bare .* in a string place absorbs a tenth field.
for d in straight resume planted; do
  J="$M31OUT/$d/journal.jsonl"
  if [ ! -s "$J" ]; then
    say_red "$d journal is missing or empty"
    continue
  fi
  if ! print -r -- "$REV" | rg -q -- '^[0-9a-f]{40}$'; then
    say_red "$d journal is unbound: argument 3 is not a 40 character clone revision"
    continue
  fi
  head -n 1 "$J" \
    | rg -q -- '^\{"m31":1,"seed":[0-9]+,"batch":[0-9]+,"plant":"[^"]*","topcoat":"'"$REV"'"\}$' \
    || say_red "$d journal line 1 is not an m31 header for clone $REV"
  L=$(awk 'END { print NR }' < "$J")
  H=$(awk '/^\{"m31":1,"seed":[0-9]+,"batch":[0-9]+,"plant":"[^"]*","topcoat":"[0-9a-f]{40}"\}$/ { n++ }
           END { print n + 0 }' "$J")
  awk 'BEGIN {
         s = "\"([^\"\\\\]|\\\\.)*\""
         pat = "^\\{\"i\":[0-9]+,\"mode\":" s ",\"size\":[0-9]+,\"verdict\":" s \
               ",\"r\":" s ",\"j\":" s ",\"f\":" s ",\"env\":\\[(" s "(," s \
               ")*)?\\],\"body\":" s "\\}$"
       }
       $0 ~ pat {
         match($0, /^\{"i":[0-9]+/)
         n = index($0, "\"verdict\":\"")
         t = substr($0, n + 11)
         q = index(t, "\"")
         print substr($0, 6, RLENGTH - 5) "\t" substr(t, 1, q - 1)
       }' "$J" > "$OUT/$d.rows"
  F=$(awk 'END { print NR }' < "$OUT/$d.rows")
  [[ $((H + F)) -eq $L ]] \
    || say_red "$d journal holds $L lines, $H headers and $F m31 rows"
  D=$(awk '{ print $1 }' "$OUT/$d.rows" | sort -u | awk 'END { print NR }')
  [[ $D -eq $F ]] \
    || say_red "$d journal holds $F rows under $D distinct i values"
  MAXI=$(awk '{ v = $1 + 0
                if (v > m) m = v }
              END { print m + 0 }' "$OUT/$d.rows")
  [[ $MAXI -eq $((F - 1)) ]] \
    || say_red "$d journal counts to i=$MAXI over $F rows, want i=$((F - 1))"
  awk '{ sub(/^[0-9]+\t/, ""); print }' "$OUT/$d.rows" \
    | sort | uniq -c \
    | awk '{ c = $1; sub(/^ *[0-9]+ /, ""); print $0 " " c }' \
    | sort > "$OUT/$d.derived"
  check "$d census is the journal verdict by verdict" \
    "$OUT/$d.census" "$OUT/$d.derived"
  case "$d" in
    straight|resume) [[ $F -eq 500 ]] || say_red "$d holds $F rows want 500" ;;
    planted) [[ $F -eq 100 ]] || say_red "$d holds $F rows want 100" ;;
  esac
done

# 15  the render comparison bites on a SOURCE change.  A copy of the tree with
# one changed line in core/known.ml builds, renders a document that carries
# the change, and that document is not KNOWN.md.  Check 2 is the only thing
# that holds the review document to the code, and this is its negative.
[[ "$(cat "$OUT/neg8.mutated")" == 1 ]] \
  || say_red "neg8 mutated $(cat "$OUT/neg8.mutated") lines want 1"
[[ "$(cat "$OUT/neg8.build.code")" == 0 ]] \
  || say_red "neg8 mutant tree did not build"
[[ "$(cat "$OUT/neg8.code")" == 0 ]] \
  || say_red "neg8 mutant render exit $(cat "$OUT/neg8.code") want 0"
rg -q -- '^# Known divergences \(m33 negative\)$' "$OUT/neg8.md" \
  || say_red "neg8 render does not carry the mutated line"
if cmp -s "$OUT/neg8.md" KNOWN.md; then
  say_red "neg8 mutant render still equals KNOWN.md"
else
  print -r -- "m33_verdict: ok neg8 rejected"
fi

[[ $RED -eq 0 ]] || exit 1
print -r -- "m33_verdict: GREEN"
