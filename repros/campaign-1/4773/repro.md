# Campaign repro 5059380:4773

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 11 -> 5
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v0: f64 = f64::INFINITY;
let v3 = Signal::new(1.2345678901234568e17);
v3.set(v0)
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;ba4c9f8e-3107-46d4-90ff-031292542235&quot;}), cx.hydrate(null)]; return () =&gt; __external0.set(__external1); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f1132161460:3127054133;
- js: Vu|r0:|g3:u
- ref: Vu|r0:|g3:f2146435072:0;
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 11 cands 7 accepted 1
round 1 size 10 cands 6 accepted 1
round 2 size 9 cands 5 accepted 1
round 3 size 8 cands 4 accepted 1
round 4 size 7 cands 3 accepted 1
round 5 size 6 cands 2 accepted 1
round 6 size 5 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4773 . ../topcoat
```

