# Campaign repro 5059380:4992

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:class:odd:ref
- original mode: read_only
- final mode: read_only
- size: 75 -> 32
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "tab\t";
let v6: Result<f64, String> = Ok(1.2345678901234568e17);
let v8: Option<f64> = None::<f64>;
let v3 = Signal::new(true);
if (if (v8.clone().expect("0") >= v2.clone().len()) { v2.clone() > v6.clone().expect_err("trail ") } else { v3.get() }) { 0.0 } else { 0.0 }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate(&quot;tab\t&quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:1.2345678901234568e+17}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;08349da9-0bfe-4e45-9f16-a724c894d0d0&quot;})]; return () =&gt; (() =&gt; { if (((() =&gt; { if ((__external0.clone().expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;0&quot;})).ge(__external1.clone().len())).dehydrate()) { return __external1.clone().gt(__external2.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;trail &quot;}))); } else { return __external3.get(); } })()).dehydrate()) { return cx.hydrate(0.0); } else { return cx.hydrate(0.0); } })(); })()
```

## Witness

- rust: Pother:1:0|r0:|g3:b1
- js: Pother:1:0|r0:|g3:b1
- ref: Pexpect:1:0|r0:|g3:b1
- verdict: diverge:class:odd:ref

## Walk

```text
round 0 size 75 cands 28 accepted 9
round 1 size 60 cands 22 accepted 9
round 2 size 36 cands 13 accepted 9
round 3 size 35 cands 12 accepted 9
round 4 size 34 cands 11 accepted 9
round 5 size 33 cands 10 accepted 9
round 6 size 32 cands 9 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4992 . ../topcoat
```

