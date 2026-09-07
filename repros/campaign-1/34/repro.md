# Campaign repro 5059380:34

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:class:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 46 -> 40
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "tab\t";
let v6: Result<f64, String> = Ok(0.5);
let v3 = Signal::new("");
{ v2.clone().contains("trail ").then_some(false.then_some(v6.clone()).expect("0")).expect("café"); v3.set(v6.clone().expect_err(" lead")); }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate(&quot;tab\t&quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.5}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;83fab8b6-1646-4a3e-866c-92bab7264c53&quot;})]; return () =&gt; { __external0.clone().contains(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;trail &quot;})).then_some(cx.hydrate(false).then_some(__external1.clone()).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;0&quot;}))).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;café&quot;})); __external2.set(__external1.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot; lead&quot;})));  }; })()
```

## Witness

- rust: Pother:1:0|r0:|g3:s0:
- js: Pother:1:0|r0:|g3:s0:
- ref: Pexpect:1:0|r0:|g3:s0:
- verdict: diverge:class:two_way

## Walk

```text
round 0 size 46 cands 8 accepted 1
round 1 size 45 cands 8 accepted 3
round 2 size 44 cands 7 accepted 3
round 3 size 43 cands 6 accepted 3
round 4 size 42 cands 5 accepted 3
round 5 size 41 cands 4 accepted 3
round 6 size 40 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 34 . ../topcoat
```

