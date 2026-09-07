# Campaign repro 5059380:4769

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 17 -> 12
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Err(" pad ");
let v7: Result<String, f64> = Err(0.1);
let v3 = Signal::new(false);
v3.set(v6.clone().unwrap() > v7.clone().unwrap_err())
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;28d922f6-ed6e-4632-9ee0-2b38e78cf3d1&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:&quot; pad &quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:0.1})]; return () =&gt; __external0.set(__external1.clone().unwrap().gt(__external2.clone().unwrap_err())); })()
```

## Witness

- rust: Punwrap:52:called `Result::unwrap()` on an `Err` value: " pad "|r0:|g3:b0
- js: Pother:49:called `Result.unwrap()` on an `Err` value:  pad |r0:|g3:b0
- ref: Punwrap:52:called `Result::unwrap()` on an `Err` value: " pad "|r0:|g3:b0
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 17 cands 6 accepted 1
round 1 size 16 cands 5 accepted 1
round 2 size 15 cands 4 accepted 1
round 3 size 14 cands 3 accepted 1
round 4 size 13 cands 2 accepted 1
round 5 size 12 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4769 . ../topcoat
```

