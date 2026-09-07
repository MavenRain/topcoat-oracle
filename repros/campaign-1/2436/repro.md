# Campaign repro 5059380:2436

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 61 -> 14
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Ok(0.1);
let v7: Result<String, f64> = Ok("a\\b");
let v3 = Signal::new(0.1);
{ { { let v10 = v6.clone().unwrap_err(); v7.clone(); v3.increment(); }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.1}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;a\\b&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;1814457c-d312-412f-bda5-05fb0448756a&quot;})]; return () =&gt; { (() =&gt; { (() =&gt; { let __local0 = __external0.clone().unwrap_err(); __external1.clone(); __external2.increment();  })();  })();  }; })()
```

## Witness

- rust: Punwrap_err:51:called `Result::unwrap_err()` on an `Ok` value: 0.1|r0:|g3:f1069128089:2576980378;
- js: Pother:50:called `Result.unwrap_err()` on an `Ok` value: 0.1|r0:|g3:f1069128089:2576980378;
- ref: Punwrap_err:51:called `Result::unwrap_err()` on an `Ok` value: 0.1|r0:|g3:f1069128089:2576980378;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 61 cands 9 accepted 1
round 1 size 40 cands 8 accepted 1
round 2 size 19 cands 7 accepted 2
round 3 size 18 cands 6 accepted 2
round 4 size 17 cands 5 accepted 2
round 5 size 16 cands 4 accepted 2
round 6 size 15 cands 3 accepted 2
round 7 size 14 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2436 . ../topcoat
```

