#!/bin/zsh
# m30_verdict.sh: hand derived expectations for m30.  Masks the two volatile
# fields, compares with cmp -s, prints a diff on a mismatch.
set -e

OUT=$1
REF_PLANT=$2
JS_PLANT=$3
CLONE_SHA=51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
M20_SHA=c2803c680acbc1231ff8940eff2a064d8187cffd6d9a30391d057e5b4affa9ec
RED=0

mask () {
  sd -- '- topcoat-oracle: [0-9a-f]{40}' '- topcoat-oracle: SHA' < "$1" > "$1.m1"
  sd -- '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' 'SIGNALID' < "$1.m1" > "$1.mask"
}

check () {
  # $1 name, $2 actual (already masked), $3 expected
  if cmp -s "$2" "$3"; then
    print -r -- "m30_verdict: ok $1"
  else
    print -r -- "m30_verdict: RED $1"
    diff -u "$3" "$2" | head -n 60
    RED=1
  fi
}

cat > "$OUT/exp.ref.stdout" <<'EXP'
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
m30 witness: diverge:rendered:odd:ref
m30 repro: _emit/m30/out/ref:display_sign/repro.md
EXP

cat > "$OUT/exp.js.stdout" <<'EXP'
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
m30 witness: diverge:value:odd:js
m30 repro: _emit/m30/out/js:signal_get_plus_one/repro.md
EXP

cat > "$OUT/exp.ref.md" <<'EXP'
# m30 repro: read_only diverge:rendered:odd:ref in ref:display_sign

## provenance

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: SHA
- plant: ref:display_sign
- origin: case ref:display_sign
- fuel: 24
- witness: _emit/m30/out/ref:display_sign/rp

The divergence below is PLANTED.  The ref:display_sign plant is injected on purpose, so this file proves the harness sees the difference;  it is not a bug report against the clone and it must not be filed.

## program

```rust
0.0
```

## emitted js

- form: direct

```js
cx.hydrate(0.0)
```

## size

- start: 6
- final: 1

## witness

- rust: Vf0:0;|r1:0|
- js: Vf0:0;|r1:0|
- ref: Vf0:0;|r2:-0|
- verdict: read_only diverge:rendered:odd:ref

## trace

```
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
```

## reproduce

```sh
dune exec bin/m30.exe -- repro '_emit/m30/out/ref:display_sign' --plant 'ref:display_sign' --fuel 24 --root '.' --clone './../topcoat'
```

```sh
dune exec bin/m29.exe -- minimize '_emit/m29/out/ref:display_sign' --plant 'ref:display_sign' --fuel 24 --root '.' --clone './../topcoat'
```

## what to look for

The four cells above are the one witness run.  The verdict line names the difference.
The program block is the smallest sample the walk reached that still shows it.
EXP

cat > "$OUT/exp.js.md" <<'EXP'
# m30 repro: read_only diverge:value:odd:js in js:signal_get_plus_one

## provenance

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: SHA
- plant: js:signal_get_plus_one
- origin: case js:signal_get_plus_one
- fuel: 24
- witness: _emit/m30/out/js:signal_get_plus_one/rp

The divergence below is PLANTED.  The js:signal_get_plus_one plant is injected on purpose, so this file proves the harness sees the difference;  it is not a bug report against the clone and it must not be filed.

## program

```rust
let v3 = Signal::new(2.5);
v3.get()
```

## emitted js

- form: direct

```js
(() => { const [__external0] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;SIGNALID&quot;})]; return __external0.get(); })()
```

## size

- start: 13
- final: 3

## witness

- rust: Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
- js: Vf1074528256:0;|r3:3.5|g3:f1074003968:0;
- ref: Vf1074003968:0;|r3:2.5|g3:f1074003968:0;
- verdict: read_only diverge:value:odd:js

## trace

```
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
```

## reproduce

```sh
dune exec bin/m30.exe -- repro '_emit/m30/out/js:signal_get_plus_one' --plant 'js:signal_get_plus_one' --fuel 24 --root '.' --clone './../topcoat'
```

```sh
dune exec bin/m29.exe -- minimize '_emit/m29/out/js:signal_get_plus_one' --plant 'js:signal_get_plus_one' --fuel 24 --root '.' --clone './../topcoat'
```

## what to look for

The four cells above are the one witness run.  The verdict line names the difference.
The program block is the smallest sample the walk reached that still shows it.
EXP

# Ruling Q3: BOTH provenance checks run BEFORE any mask, so masking the
# topcoat-oracle sha costs no coverage.  The topcoat pin is never masked at
# all (hazard 4 of the facts sheet), so it stays literal in the goldens too.
for p in "$REF_PLANT" "$JS_PLANT"; do
  if rg -q -- "^- topcoat: $CLONE_SHA\$" "$OUT/$p/repro.md"; then
    print -r -- "m30_verdict: ok clone pin $p"
  else
    print -r -- "m30_verdict: RED clone pin $p"
    rg -- '^- topcoat' "$OUT/$p/repro.md" || true
    RED=1
  fi
  if rg -q -- '^- topcoat-oracle: [0-9a-f]{40}$' "$OUT/$p/repro.md"; then
    print -r -- "m30_verdict: ok oracle sha shape $p"
  else
    print -r -- "m30_verdict: RED oracle sha shape $p"
    rg -- '^- topcoat-oracle' "$OUT/$p/repro.md" || true
    RED=1
  fi
  for n in topcoat topcoat-oracle; do
    if rg -q -- '^[0-9a-f]{40}$' "$OUT/$p/sha/$n.sha"; then
      print -r -- "m30_verdict: ok sha $p $n"
    else
      print -r -- "m30_verdict: RED sha $p $n"
      RED=1
    fi
  done
done

for f in "$OUT/ref.stdout" "$OUT/js.stdout" "$OUT/$REF_PLANT/repro.md" "$OUT/$JS_PLANT/repro.md"; do
  mask "$f"
done

check "ref stdout" "$OUT/ref.stdout.mask" "$OUT/exp.ref.stdout"
check "js stdout" "$OUT/js.stdout.mask" "$OUT/exp.js.stdout"
check "ref repro" "$OUT/$REF_PLANT/repro.md.mask" "$OUT/exp.ref.md"
check "js repro" "$OUT/$JS_PLANT/repro.md.mask" "$OUT/exp.js.md"

LINES_REF=$(wc -l < "$OUT/$REF_PLANT/repro.md")
LINES_JS=$(wc -l < "$OUT/$JS_PLANT/repro.md")
[[ $LINES_REF -eq 70 ]] || { print -r -- "m30_verdict: RED ref lines $LINES_REF want 70"; RED=1 }
[[ $LINES_JS -eq 73 ]] || { print -r -- "m30_verdict: RED js lines $LINES_JS want 73"; RED=1 }

CRATES=$(rg --files "$OUT" -g Cargo.toml | wc -l | tr -d ' ')
[[ $CRATES -eq 16 ]] || { print -r -- "m30_verdict: RED crates $CRATES want 16"; RED=1 }

REPROS=$(fd -H -I -t d '^repros$' . | wc -l | tr -d ' ')
[[ $REPROS -eq 0 ]] || { print -r -- "m30_verdict: RED a repros/ directory was created"; RED=1 }

print -r -- "m30_verdict: M20_SHA=$M20_SHA"
[[ $RED -eq 0 ]] || exit 1
print -r -- "m30_verdict: GREEN"
