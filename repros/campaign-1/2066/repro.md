# Campaign repro 5059380:2066

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:class:odd:ref
- original mode: read_only
- final mode: read_only
- size: 49 -> 46
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v2: String = " pad ";
let v6: Result<f64, String> = Ok(0.0);
let v8: Option<f64> = None::<f64>;
let v3 = Signal::new(true);
if v1 { v8.clone().expect("trail "); v3.get() } else { (!(!v1)).then_some(v2.clone() > v6.clone().expect_err("quote\"and\\back")).unwrap() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4] = [cx.hydrate(false), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;9bc5816a-fcc4-4311-81e7-30da22e3f03c&quot;}), cx.hydrate(&quot; pad &quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.0})]; return () =&gt; (() =&gt; { if (__external0.dehydrate()) { __external1.clone().expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;trail &quot;})); return __external2.get(); } else { return ((__external0.not()).not()).then_some(__external3.clone().gt(__external4.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;quote\&quot;and\\back&quot;})))).unwrap(); } })(); })()
```

## Witness

- rust: Pother:19:quote"and\back: 0.0|r0:|g3:b1
- js: Pother:17:quote"and\back: 0|r0:|g3:b1
- ref: Pexpect_err:19:quote"and\back: 0.0|r0:|g3:b1
- verdict: diverge:class:odd:ref

## Walk

```text
round 0 size 49 cands 11 accepted 8
round 1 size 48 cands 10 accepted 8
round 2 size 47 cands 9 accepted 8
round 3 size 46 cands 8 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2066 . ../topcoat
```

