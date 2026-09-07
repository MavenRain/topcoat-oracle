# Campaign repro 5059380:1636

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 14 -> 8
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Err(0.0);
let v3 = Signal::new("pCWaTKM");
v3.set(v7.clone().unwrap().to_owned())
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;c4b69394-02fc-42d2-85ca-65eec2880557&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:0.0})]; return () =&gt; __external0.set(__external1.clone().unwrap().to_owned()); })()
```

## Witness

- rust: Punwrap:48:called `Result::unwrap()` on an `Err` value: 0.0|r0:|g3:s7:pCWaTKM
- js: Pother:45:called `Result.unwrap()` on an `Err` value: 0|r0:|g3:s7:pCWaTKM
- ref: Punwrap:48:called `Result::unwrap()` on an `Err` value: 0.0|r0:|g3:s7:pCWaTKM
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 14 cands 7 accepted 1
round 1 size 13 cands 6 accepted 1
round 2 size 12 cands 5 accepted 1
round 3 size 11 cands 4 accepted 1
round 4 size 10 cands 3 accepted 1
round 5 size 9 cands 2 accepted 1
round 6 size 8 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1636 . ../topcoat
```

