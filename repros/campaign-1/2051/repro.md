# Campaign repro 5059380:2051

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:class:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 40 -> 35
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = " pad ";
let v6: Result<f64, String> = Ok(f64::NAN);
let v3 = Signal::new(1e300);
let v4 = Signal::new("a\\b");
{ let v10 = v6.clone().expect_err("abc"); let v11 = v3.get(); if false.then_some(false).expect("café") { } else if false { } else { v4.push_str(v2.clone()) }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;d0d236a6-ebb3-41a8-a96b-4ede59e83b11&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;0d34e15e-b719-417e-a83e-b3ebe224bec1&quot;}), cx.hydrate(&quot; pad &quot;)]; return () =&gt; { let __local0 = __external0.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;abc&quot;})); let __local1 = __external1.get(); (() =&gt; { if (cx.hydrate(false).then_some(cx.hydrate(false)).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;café&quot;})).dehydrate()) {  } else { if (cx.hydrate(false).dehydrate()) {  } else { return __external2.push_str(__external3.clone()); } } })();  }; })()
```

## Witness

- rust: Pother:8:abc: NaN|r0:|g3:f2117592124:2281731484;g4:s3:a\b
- js: Pother:14:abc: undefined|r0:|g3:f2117592124:2281731484;g4:s3:a\b
- ref: Pexpect_err:8:abc: NaN|r0:|g3:f2117592124:2281731484;g4:s3:a\b
- verdict: diverge:class:two_way

## Walk

```text
round 0 size 40 cands 9 accepted 4
round 1 size 39 cands 8 accepted 4
round 2 size 38 cands 7 accepted 4
round 3 size 37 cands 6 accepted 4
round 4 size 36 cands 5 accepted 4
round 5 size 35 cands 4 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2051 . ../topcoat
```

