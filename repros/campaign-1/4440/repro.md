# Campaign repro 5059380:4440

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
let v6: Result<f64, String> = Err(" pad ");
let v3 = Signal::new("XhWh31");
if v3.get().is_empty() { 0.0 } else { v6.clone().unwrap() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;be328e28-60ea-4b2b-a21e-c9c8d11eec4b&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:&quot; pad &quot;})]; return () =&gt; (() =&gt; { if (__external0.get().is_empty().dehydrate()) { return cx.hydrate(0.0); } else { return __external1.clone().unwrap(); } })(); })()
```

## Witness

- rust: Punwrap:52:called `Result::unwrap()` on an `Err` value: " pad "|r0:|g3:s6:XhWh31
- js: Pother:49:called `Result.unwrap()` on an `Err` value:  pad |r0:|g3:s6:XhWh31
- ref: Punwrap:52:called `Result::unwrap()` on an `Err` value: " pad "|r0:|g3:s6:XhWh31
- verdict: diverge:message:odd:js

## Walk

```text
round 0 size 17 cands 13 accepted 5
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
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4440 . ../topcoat
```

