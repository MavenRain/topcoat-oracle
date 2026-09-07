# Campaign repro 5059380:2459

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 19 -> 15
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v0: f64 = 1e16;
let v1: bool = true;
let v2: String = "";
let v3 = Signal::new(1e16);
let v4 = Signal::new("é");
{ { v4.set(v2.clone()); v1 }; v3.set(v0); }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;b89aaf30-5706-43b9-bf17-d3a5b3892602&quot;}), cx.hydrate(&quot;&quot;), cx.hydrate(true), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;84f0760e-ee87-437f-84ba-63272cabc4c2&quot;}), cx.hydrate(1e+16)]; return () =&gt; { (() =&gt; { __external0.set(__external1.clone()); return __external2; })(); __external3.set(__external4);  }; })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f1128383353:937459712;g4:s2:é
- js: Vu|r0:|g3:s0:g4:f1128383353:937459712;
- ref: Vu|r0:|g3:f1128383353:937459712;g4:s0:
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 19 cands 7 accepted 3
round 1 size 18 cands 6 accepted 3
round 2 size 17 cands 5 accepted 3
round 3 size 16 cands 4 accepted 3
round 4 size 15 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2459 . ../topcoat
```

