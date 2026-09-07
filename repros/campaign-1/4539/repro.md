# Campaign repro 5059380:4539

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 42 -> 20
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(-f64::INFINITY);
let v4 = Signal::new(100.0);
let v5 = Signal::new(false);
if true { v4.increment() } else if false { v3.set(v3.get()) } else { v5.set(false.then_some(false).unwrap()) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;8eef1f0e-5960-4940-a3d3-7e0f341f46bd&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;5474b5c7-9ed6-4faa-b8ed-6ee1e8819b8d&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;67da507d-d525-43ae-8500-325668f1cf28&quot;})]; return () =&gt; (() =&gt; { if (cx.hydrate(true).dehydrate()) { return __external0.increment(); } else { if (cx.hydrate(false).dehydrate()) { return __external1.set(__external1.get()); } else { return __external2.set(cx.hydrate(false).then_some(cx.hydrate(false)).unwrap()); } } })(); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f4293918720:0;g4:f1079574528:0;g5:b0
- js: Vu|r0:|g3:f4293918720:0;g4:f1079574528:0;g5:b0
- ref: Vu|r0:|g3:f4293918720:0;g4:f1079590912:0;g5:b0
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 42 cands 23 accepted 6
round 1 size 40 cands 21 accepted 7
round 2 size 32 cands 17 accepted 8
round 3 size 27 cands 17 accepted 10
round 4 size 26 cands 16 accepted 10
round 5 size 25 cands 15 accepted 10
round 6 size 24 cands 14 accepted 10
round 7 size 23 cands 13 accepted 10
round 8 size 22 cands 12 accepted 10
round 9 size 21 cands 11 accepted 10
round 10 size 20 cands 10 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4539 . ../topcoat
```

