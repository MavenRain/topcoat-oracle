# Campaign repro 5059380:2291

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 25 -> 20
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "";
let v7: Result<String, f64> = Err(2.0);
let v3 = Signal::new("😀");
{ let v10 = false.then_some(v7.clone()).unwrap(); { let v11 = 1.5; let v12 = { }; v3.set(v2.clone()); }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:2.0}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;c1574a5b-c0e7-4b45-830e-ff1322c3a4d6&quot;}), cx.hydrate(&quot;&quot;)]; return () =&gt; { let __local0 = cx.hydrate(false).then_some(__external0.clone()).unwrap(); (() =&gt; { let __local1 = cx.hydrate(1.5); let __local2 = (() =&gt; {  })(); __external1.set(__external2.clone());  })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s4:😀
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s4:😀
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s4:😀
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 25 cands 8 accepted 3
round 1 size 24 cands 7 accepted 3
round 2 size 23 cands 6 accepted 3
round 3 size 22 cands 5 accepted 3
round 4 size 21 cands 4 accepted 3
round 5 size 20 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2291 . ../topcoat
```

