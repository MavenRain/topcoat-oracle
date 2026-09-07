# Campaign repro 5059380:3517

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 23 -> 7
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Err("a\"b");
let v3 = Signal::new(100.0);
v3.set(v6.clone().unwrap())
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;dc8f8977-cff5-40f5-bcf5-926b077b7961&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:&quot;a\&quot;b&quot;})]; return () =&gt; __external0.set(__external1.clone().unwrap()); })()
```

## Witness

- rust: Punwrap:51:called `Result::unwrap()` on an `Err` value: "a\"b"|r0:|g3:f1079574528:0;
- js: Pother:47:called `Result.unwrap()` on an `Err` value: a"b|r0:|g3:f1079574528:0;
- ref: Punwrap:51:called `Result::unwrap()` on an `Err` value: "a\"b"|r0:|g3:f1079574528:0;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 23 cands 14 accepted 1
round 1 size 21 cands 12 accepted 1
round 2 size 13 cands 7 accepted 1
round 3 size 12 cands 6 accepted 1
round 4 size 11 cands 5 accepted 1
round 5 size 10 cands 4 accepted 1
round 6 size 9 cands 3 accepted 1
round 7 size 8 cands 2 accepted 1
round 8 size 7 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3517 . ../topcoat
```

