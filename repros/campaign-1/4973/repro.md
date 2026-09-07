# Campaign repro 5059380:4973

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 20 -> 12
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(1.2345678901234568e17);
let v4 = Signal::new(0.5);
if false { v4.set(2.0) } else { v3.set(-1.0) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;68d51ba6-83f3-41e5-a8f0-976756b5e246&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;998352a1-3ac4-4fa9-b61e-f87ebb5038e6&quot;})]; return () =&gt; (() =&gt; { if (cx.hydrate(false).dehydrate()) { return __external0.set(cx.hydrate(2.0)); } else { return __external1.set(cx.hydrate(1.0).neg()); } })(); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f1132161460:3127054133;g4:f1071644672:0;
- js: Vu|r0:|g3:f1132161460:3127054133;g4:f3220176896:0;
- ref: Vu|r0:|g3:f3220176896:0;g4:f1071644672:0;
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 20 cands 14 accepted 3
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
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4973 . ../topcoat
```

