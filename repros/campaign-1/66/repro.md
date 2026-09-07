# Campaign repro 5059380:66

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 31 -> 17
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Err("");
let v3 = Signal::new(true);
{ { v3.set(false); if true { v6.clone() } else { v6.clone() }; v6.clone().unwrap() }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;f6b7c628-9abd-4e68-b5b5-58b4e797c53f&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:&quot;&quot;})]; return () =&gt; { (() =&gt; { __external0.set(cx.hydrate(false)); (() =&gt; { if (cx.hydrate(true).dehydrate()) { return __external1.clone(); } else { return __external1.clone(); } })(); return __external1.clone().unwrap(); })();  }; })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:b1
- js: Pother:44:called `Result.unwrap()` on an `Err` value: |r0:|g3:b0
- ref: Punwrap:47:called `Result::unwrap()` on an `Err` value: ""|r0:|g3:b0
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 31 cands 8 accepted 2
round 1 size 23 cands 8 accepted 2
round 2 size 22 cands 7 accepted 2
round 3 size 21 cands 6 accepted 2
round 4 size 20 cands 5 accepted 2
round 5 size 19 cands 4 accepted 2
round 6 size 18 cands 3 accepted 2
round 7 size 17 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 66 . ../topcoat
```

