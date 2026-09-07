# Campaign repro 5059380:954

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 17 -> 11
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Ok(-1.1582496113645555e275);
let v3 = Signal::new("tab\t");
v3.set(if false { v3.get() } else { v6.clone().unwrap_err() })
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;5d074903-0841-482c-a752-68daf501ca6f&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:-1.1582496113645555e+275})]; return () =&gt; __external0.set((() =&gt; { if (cx.hydrate(false).dehydrate()) { return __external0.get(); } else { return __external1.clone().unwrap_err(); } })()); })()
```

## Witness

- rust: Punwrap_err:71:called `Result::unwrap_err()` on an `Ok` value: -1.1582496113645555e275|r0:|g3:s4:tab	
- js: Pother:324:called `Result.unwrap_err()` on an `Ok` value: -115824961136455550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000|r0:|g3:s4:tab	
- ref: Punwrap_err:71:called `Result::unwrap_err()` on an `Ok` value: -1.1582496113645555e275|r0:|g3:s4:tab	
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 17 cands 7 accepted 1
round 1 size 16 cands 6 accepted 1
round 2 size 15 cands 5 accepted 1
round 3 size 14 cands 4 accepted 1
round 4 size 13 cands 3 accepted 1
round 5 size 12 cands 2 accepted 1
round 6 size 11 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 954 . ../topcoat
```

