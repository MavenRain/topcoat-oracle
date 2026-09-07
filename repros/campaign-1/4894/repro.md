# Campaign repro 5059380:4894

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 13 -> 7
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Ok(0.0);
let v3 = Signal::new("😀");
v3.set(v6.clone().unwrap_err())
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;d8bad32f-efea-4c01-b9a6-0c6603e876cf&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.0})]; return () =&gt; __external0.set(__external1.clone().unwrap_err()); })()
```

## Witness

- rust: Punwrap_err:51:called `Result::unwrap_err()` on an `Ok` value: 0.0|r0:|g3:s4:😀
- js: Pother:48:called `Result.unwrap_err()` on an `Ok` value: 0|r0:|g3:s4:😀
- ref: Punwrap_err:51:called `Result::unwrap_err()` on an `Ok` value: 0.0|r0:|g3:s4:😀
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 13 cands 7 accepted 1
round 1 size 12 cands 6 accepted 1
round 2 size 11 cands 5 accepted 1
round 3 size 10 cands 4 accepted 1
round 4 size 9 cands 3 accepted 1
round 5 size 8 cands 2 accepted 1
round 6 size 7 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4894 . ../topcoat
```

