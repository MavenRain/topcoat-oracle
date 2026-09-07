# Campaign repro 5059380:510

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 31 -> 10
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(0.0);
if false.then_some(true).unwrap() { v3.increment() } else { }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;eb0eed0e-ce7f-412e-8407-e604340a312f&quot;})]; return () =&gt; (() =&gt; { if (cx.hydrate(false).then_some(cx.hydrate(true)).unwrap().dehydrate()) { return __external0.increment(); } else {  } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f0:0;
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:f0:0;
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f0:0;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 31 cands 18 accepted 2
round 1 size 22 cands 15 accepted 5
round 2 size 17 cands 12 accepted 5
round 3 size 16 cands 11 accepted 5
round 4 size 15 cands 10 accepted 5
round 5 size 14 cands 9 accepted 5
round 6 size 13 cands 8 accepted 5
round 7 size 12 cands 7 accepted 5
round 8 size 11 cands 6 accepted 5
round 9 size 10 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 510 . ../topcoat
```

