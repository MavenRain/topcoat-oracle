# Campaign repro 5059380:906

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 26 -> 16
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(false);
let v4 = Signal::new(1.2345678901234568e17);
if false.then_some(true).unwrap() { if v3.get() { v4.set(-0.0); } }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;1e97dc41-1d50-4896-a81c-d8f906d7c851&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;86bd1b84-aa7e-4016-ab58-d9bcfa3a189c&quot;})]; return () =&gt; (() =&gt; { if (cx.hydrate(false).then_some(cx.hydrate(true)).unwrap().dehydrate()) { return (() =&gt; { if (__external0.get().dehydrate()) { __external1.set(cx.hydrate(0.0).neg());  } })(); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b0g4:f1132161460:3127054133;
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b0g4:f1132161460:3127054133;
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b0g4:f1132161460:3127054133;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 26 cands 17 accepted 7
round 1 size 24 cands 16 accepted 7
round 2 size 23 cands 15 accepted 8
round 3 size 22 cands 14 accepted 8
round 4 size 21 cands 13 accepted 8
round 5 size 20 cands 12 accepted 8
round 6 size 19 cands 11 accepted 8
round 7 size 18 cands 10 accepted 8
round 8 size 17 cands 9 accepted 8
round 9 size 16 cands 8 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 906 . ../topcoat
```

