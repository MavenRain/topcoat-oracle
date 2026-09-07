# Campaign repro 5059380:3556

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:odd:js
- original mode: read_only
- final mode: read_only
- size: 21 -> 12
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(" pad ");
if (v3.get() <= v3.get()) { false.then_some(false).unwrap() } else { false }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;bf7cfad0-0d8c-4dae-a011-4af0dcbf1e48&quot;})]; return () =&gt; (() =&gt; { if ((__external0.get().le(__external0.get())).dehydrate()) { return cx.hydrate(false).then_some(cx.hydrate(false)).unwrap(); } else { return cx.hydrate(false); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5: pad 
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s5: pad 
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5: pad 
- verdict: diverge:message:odd:js

## Walk

```text
round 0 size 21 cands 12 accepted 5
round 1 size 19 cands 12 accepted 5
round 2 size 18 cands 11 accepted 5
round 3 size 17 cands 10 accepted 5
round 4 size 16 cands 9 accepted 5
round 5 size 15 cands 8 accepted 5
round 6 size 14 cands 7 accepted 5
round 7 size 13 cands 6 accepted 5
round 8 size 12 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3556 . ../topcoat
```

