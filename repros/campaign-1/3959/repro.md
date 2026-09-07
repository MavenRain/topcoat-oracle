# Campaign repro 5059380:3959

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:odd:js
- original mode: read_only
- final mode: read_only
- size: 17 -> 10
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Ok("a");
let v3 = Signal::new("6rHanC");
if v3.get().is_empty() { 0.0 } else { v7.clone().unwrap_err() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;680f5fc9-e111-4b41-8049-e0eb125b7f5f&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;a&quot;})]; return () =&gt; (() =&gt; { if (__external0.get().is_empty().dehydrate()) { return cx.hydrate(0.0); } else { return __external1.clone().unwrap_err(); } })(); })()
```

## Witness

- rust: Punwrap_err:51:called `Result::unwrap_err()` on an `Ok` value: "a"|r0:|g3:s6:6rHanC
- js: Pother:48:called `Result.unwrap_err()` on an `Ok` value: a|r0:|g3:s6:6rHanC
- ref: Punwrap_err:51:called `Result::unwrap_err()` on an `Ok` value: "a"|r0:|g3:s6:6rHanC
- verdict: diverge:message:odd:js

## Walk

```text
round 0 size 17 cands 12 accepted 4
round 1 size 16 cands 11 accepted 5
round 2 size 15 cands 10 accepted 5
round 3 size 14 cands 9 accepted 5
round 4 size 13 cands 8 accepted 5
round 5 size 12 cands 7 accepted 5
round 6 size 11 cands 6 accepted 5
round 7 size 10 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3959 . ../topcoat
```

