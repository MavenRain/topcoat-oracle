# Campaign repro 5059380:4962

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:odd:js
- original mode: read_only
- final mode: read_only
- size: 23 -> 20
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v0: f64 = 1e-5;
let v1: bool = true;
let v6: Result<f64, String> = Ok(0.5);
let v9: Option<String> = None::<String>;
let v3 = Signal::new("a");
if (if ({ v1 }) { v3.get() } else { v6.clone().unwrap_err() }).is_empty() { v0 } else { v9.clone().unwrap().len() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4] = [cx.hydrate(true), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;fd1d3838-7c76-489a-8f75-4e60ffee1870&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.5}), cx.hydrate(0.00001), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null})]; return () =&gt; (() =&gt; { if (((() =&gt; { if (((() =&gt; { return __external0; })()).dehydrate()) { return __external1.get(); } else { return __external2.clone().unwrap_err(); } })()).is_empty().dehydrate()) { return __external3; } else { return __external4.clone().unwrap().len(); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s1:a
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s1:a
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s1:a
- verdict: diverge:message:odd:js

## Walk

```text
round 0 size 23 cands 8 accepted 5
round 1 size 22 cands 7 accepted 5
round 2 size 21 cands 6 accepted 5
round 3 size 20 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4962 . ../topcoat
```

