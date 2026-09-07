# Campaign repro 5059380:1535

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 17 -> 11
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Err(f64::NAN);
let v3 = Signal::new(true);
if v7.clone().unwrap().is_empty() { } else { v3.set(false) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;ffbf6f8d-5a66-4d26-8961-37f0af6a8327&quot;})]; return () =&gt; (() =&gt; { if (__external0.clone().unwrap().is_empty().dehydrate()) {  } else { return __external1.set(cx.hydrate(false)); } })(); })()
```

## Witness

- rust: Punwrap:48:called `Result::unwrap()` on an `Err` value: NaN|r0:|g3:b1
- js: Pother:53:called `Result.unwrap()` on an `Err` value: undefined|r0:|g3:b1
- ref: Punwrap:48:called `Result::unwrap()` on an `Err` value: NaN|r0:|g3:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 17 cands 11 accepted 5
round 1 size 16 cands 10 accepted 5
round 2 size 15 cands 9 accepted 5
round 3 size 14 cands 8 accepted 5
round 4 size 13 cands 7 accepted 5
round 5 size 12 cands 6 accepted 5
round 6 size 11 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1535 . ../topcoat
```

