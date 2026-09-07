# Campaign repro 5059380:2599

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 56 -> 49
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Ok(0.0);
let v3 = Signal::new(-4.341631250347229e290);
let v4 = Signal::new(1e-5);
{ loop { { v6.clone().expect_err("a") }; let v13 = (-0.0) + v4.get(); loop { { let v10 = if true { } else { }; let v11 = (1.2345678901234568e17) / (0.0); }; let v12 = v3.decrement(); while (!true) { if true { } else { v3.decrement() }; break; }; break; }; break; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.0}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;cc8d152a-44a9-4495-a3d8-1cd4c2d9c1b3&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;078f0d26-ab16-4c36-ac66-5c7987f9788d&quot;})]; return () =&gt; { while (true) { (() =&gt; { return __external0.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;a&quot;})); })(); let __local0 = (cx.hydrate(0.0).neg()).add(__external1.get()); while (true) { (() =&gt; { let __local1 = (() =&gt; { if (cx.hydrate(true).dehydrate()) {  } else {  } })(); let __local2 = (cx.hydrate(1.2345678901234568e+17)).div((cx.hydrate(0.0)));  })(); let __local3 = __external2.decrement(); while ((cx.hydrate(true).not()).dehydrate()) { (() =&gt; { if (cx.hydrate(true).dehydrate()) {  } else { return __external2.decrement(); } })(); break;  }; break;  }; break;  };  }; })()
```

## Witness

- rust: Pexpect_err:6:a: 0.0|r0:|g3:f4232464005:4119935525;g4:f1055193269:2296604913;
- js: Pexpect_err:4:a: 0|r0:|g3:f4232464005:4119935525;g4:f1055193269:2296604913;
- ref: Pexpect_err:6:a: 0.0|r0:|g3:f4232464005:4119935525;g4:f1055193269:2296604913;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 56 cands 9 accepted 1
round 1 size 55 cands 8 accepted 2
round 2 size 54 cands 7 accepted 2
round 3 size 53 cands 6 accepted 2
round 4 size 52 cands 5 accepted 2
round 5 size 51 cands 4 accepted 2
round 6 size 50 cands 3 accepted 2
round 7 size 49 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2599 . ../topcoat
```

