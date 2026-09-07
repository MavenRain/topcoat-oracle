# Campaign repro 5059380:3799

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 46 -> 43
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = true;
let v2: String = "a\\b";
let v6: Result<f64, String> = Ok(0.0);
let v7: Result<String, f64> = Ok("é");
let v3 = Signal::new(1e300);
{ let v10 = { v7.clone().unwrap_err() == (if false { -0.0 } else { 1000000000000000.0 }); if v1 { if false { 0.0 } else { 100.0 } } else { 2.0 }; !((0.1) >= (0.1)) }; { v10; v2.clone().to_owned(); v3.set(v6.clone().unwrap()); }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;é&quot;}), cx.hydrate(true), cx.hydrate(&quot;a\\b&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;83ee56e3-f5ad-423b-9552-386de32e5185&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.0})]; return () =&gt; { let __local0 = (() =&gt; { __external0.clone().unwrap_err().eq(((() =&gt; { if (cx.hydrate(false).dehydrate()) { return cx.hydrate(0.0).neg(); } else { return cx.hydrate(1000000000000000.0); } })())); (() =&gt; { if (__external1.dehydrate()) { return (() =&gt; { if (cx.hydrate(false).dehydrate()) { return cx.hydrate(0.0); } else { return cx.hydrate(100.0); } })(); } else { return cx.hydrate(2.0); } })(); return ((cx.hydrate(0.1)).ge((cx.hydrate(0.1)))).not(); })(); (() =&gt; { __local0; __external2.clone().to_owned(); __external3.set(__external4.clone().unwrap());  })();  }; })()
```

## Witness

- rust: Punwrap_err:52:called `Result::unwrap_err()` on an `Ok` value: "é"|r0:|g3:f2117592124:2281731484;
- js: Pother:49:called `Result.unwrap_err()` on an `Ok` value: é|r0:|g3:f2117592124:2281731484;
- ref: Punwrap_err:52:called `Result::unwrap_err()` on an `Ok` value: "é"|r0:|g3:f2117592124:2281731484;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 46 cands 5 accepted 2
round 1 size 45 cands 4 accepted 2
round 2 size 44 cands 3 accepted 2
round 3 size 43 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3799 . ../topcoat
```

