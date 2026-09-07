# Campaign repro 5059380:1189

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 67 -> 63
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v0: f64 = 2.0;
let v1: bool = true;
let v2: String = "";
let v6: Result<f64, String> = Ok(100.0);
let v7: Result<String, f64> = Ok(" pad ");
let v9: Option<String> = Some("tab\t");
let v3 = Signal::new(1e300);
{ v6.clone().unwrap_err().to_owned(); { if v2.clone().is_empty() { v2.clone().to_owned() } else { v7.clone().unwrap() }; { -(v3.get() * v7.clone().expect_err(" lead")); false.then_some(v9.clone()).expect("trail "); v2.clone() }; v3.set(if v1 { v0 } else if v1 { -(-1.0) } else { v3.get() }); }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4, __external5, __external6] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:100.0}), cx.hydrate(&quot;&quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot; pad &quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;8cae083f-2c8d-4645-97ed-4ea12e4378d6&quot;}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:&quot;tab\t&quot;}), cx.hydrate(true), cx.hydrate(2.0)]; return () =&gt; { __external0.clone().unwrap_err().to_owned(); (() =&gt; { (() =&gt; { if (__external1.clone().is_empty().dehydrate()) { return __external1.clone().to_owned(); } else { return __external2.clone().unwrap(); } })(); (() =&gt; { (__external3.get().mul(__external2.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot; lead&quot;})))).neg(); cx.hydrate(false).then_some(__external4.clone()).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;trail &quot;})); return __external1.clone(); })(); __external3.set((() =&gt; { if (__external5.dehydrate()) { return __external6; } else { if (__external5.dehydrate()) { return (cx.hydrate(1.0).neg()).neg(); } else { return __external3.get(); } } })());  })();  }; })()
```

## Witness

- rust: Punwrap_err:53:called `Result::unwrap_err()` on an `Ok` value: 100.0|r0:|g3:f2117592124:2281731484;
- js: Pother:50:called `Result.unwrap_err()` on an `Ok` value: 100|r0:|g3:f2117592124:2281731484;
- ref: Punwrap_err:53:called `Result::unwrap_err()` on an `Ok` value: 100.0|r0:|g3:f2117592124:2281731484;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 67 cands 5 accepted 2
round 1 size 64 cands 4 accepted 3
round 2 size 63 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1189 . ../topcoat
```

