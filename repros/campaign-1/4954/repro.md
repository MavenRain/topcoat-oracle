# Campaign repro 5059380:4954

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 18 -> 11
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(0.1);
let v4 = Signal::new(3.0);
v4.set({ { }; v4.get() - v3.get() })
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;1b591142-a865-4a73-92e5-7df2a7e15074&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;01c358d7-629f-41e5-bb88-bef8795dd051&quot;})]; return () =&gt; __external0.set((() =&gt; { (() =&gt; {  })(); return __external0.get().sub(__external1.get()); })()); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f1069128089:2576980378;g4:f1074266112:0;
- js: Vu|r0:|g3:f3221697331:858993459;g4:f1074266112:0;
- ref: Vu|r0:|g3:f1069128089:2576980378;g4:f1074213683:858993459;
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 18 cands 8 accepted 1
round 1 size 17 cands 7 accepted 1
round 2 size 16 cands 6 accepted 1
round 3 size 15 cands 5 accepted 1
round 4 size 14 cands 4 accepted 1
round 5 size 13 cands 3 accepted 1
round 6 size 12 cands 2 accepted 1
round 7 size 11 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4954 . ../topcoat
```

