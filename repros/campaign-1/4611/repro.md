# Campaign repro 5059380:4611

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 31 -> 26
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "€";
let v6: Result<f64, String> = Err(" pad ");
let v3 = Signal::new(f64::INFINITY);
let v4 = Signal::new(0.1);
v4.set(({ let v10 = { v6.clone().expect_err("  both  "); v3.get(); }; v2.clone() }).len())
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;bed32fea-3cc8-4033-83f8-826cf06943b9&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:&quot; pad &quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;070f5485-be77-45d9-afef-ea582a54ec88&quot;}), cx.hydrate(&quot;€&quot;)]; return () =&gt; __external0.set(((() =&gt; { let __local0 = (() =&gt; { __external1.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;  both  &quot;})); __external2.get();  })(); return __external3.clone(); })()).len()); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f2146435072:0;g4:f1069128089:2576980378;
- js: Vu|r0:|g3:f1074266112:0;g4:f1069128089:2576980378;
- ref: Vu|r0:|g3:f2146435072:0;g4:f1074266112:0;
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 31 cands 6 accepted 1
round 1 size 30 cands 5 accepted 1
round 2 size 29 cands 4 accepted 1
round 3 size 28 cands 3 accepted 1
round 4 size 27 cands 2 accepted 1
round 5 size 26 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4611 . ../topcoat
```

