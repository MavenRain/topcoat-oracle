# Campaign repro 5059380:2024

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 38 -> 26
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v2: String = "😀";
let v3 = Signal::new("😀");
let v4 = Signal::new(1.5);
let v5 = Signal::new(-0.0);
if v1 { if false { v5.set(if true { 0.5 } else { 3.0 }) } else { v4.set(1.5) } } else { v3.set(v2.clone()) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4] = [cx.hydrate(false), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;ea28f743-571c-4af7-8ea3-45f5d3479fae&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;e3c4c8c8-59ef-491f-b463-0e1e085eb2d8&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;22b51383-95d9-4830-8a2a-6e7be3b63011&quot;}), cx.hydrate(&quot;😀&quot;)]; return () =&gt; (() =&gt; { if (__external0.dehydrate()) { return (() =&gt; { if (cx.hydrate(false).dehydrate()) { return __external1.set((() =&gt; { if (cx.hydrate(true).dehydrate()) { return cx.hydrate(0.5); } else { return cx.hydrate(3.0); } })()); } else { return __external2.set(cx.hydrate(1.5)); } })(); } else { return __external3.set(__external4.clone()); } })(); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:s4:😀g4:f1073217536:0;g5:f2147483648:0;
- js: Vu|r0:|g3:s4:😀g4:f1073217536:0;g5:s4:😀
- ref: Vu|r0:|g3:s4:😀g4:f1073217536:0;g5:f2147483648:0;
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 38 cands 18 accepted 6
round 1 size 36 cands 18 accepted 9
round 2 size 31 cands 14 accepted 9
round 3 size 30 cands 13 accepted 9
round 4 size 29 cands 12 accepted 9
round 5 size 28 cands 11 accepted 9
round 6 size 27 cands 10 accepted 9
round 7 size 26 cands 9 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2024 . ../topcoat
```

