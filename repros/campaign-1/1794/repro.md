# Campaign repro 5059380:1794

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 34 -> 24
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "";
let v6: Result<f64, String> = Ok(1.5);
let v7: Result<String, f64> = Err(-f64::INFINITY);
let v3 = Signal::new(true);
if v7.clone().unwrap().is_empty() { } else { { let v10 = v2.clone().to_owned(); { v6.clone(); let v11 = { }; v3.set(false); }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:null}), cx.hydrate(&quot;&quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:1.5}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;e0aa5b5c-88cd-4976-952a-646e5aca7c01&quot;})]; return () =&gt; (() =&gt; { if (__external0.clone().unwrap().is_empty().dehydrate()) {  } else { (() =&gt; { let __local0 = __external1.clone().to_owned(); (() =&gt; { __external2.clone(); let __local1 = (() =&gt; {  })(); __external3.set(cx.hydrate(false));  })();  })();  } })(); })()
```

## Witness

- rust: Punwrap:49:called `Result::unwrap()` on an `Err` value: -inf|r0:|g3:b1
- js: Pother:53:called `Result.unwrap()` on an `Err` value: undefined|r0:|g3:b1
- ref: Punwrap:49:called `Result::unwrap()` on an `Err` value: -inf|r0:|g3:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 34 cands 12 accepted 4
round 1 size 31 cands 11 accepted 5
round 2 size 29 cands 10 accepted 5
round 3 size 28 cands 10 accepted 6
round 4 size 27 cands 9 accepted 6
round 5 size 26 cands 8 accepted 6
round 6 size 25 cands 7 accepted 6
round 7 size 24 cands 6 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1794 . ../topcoat
```

