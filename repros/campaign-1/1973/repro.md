# Campaign repro 5059380:1973

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 20 -> 15
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "line\nbreak";
let v6: Result<f64, String> = Ok(2.0);
let v3 = Signal::new("hello");
if (v6.clone().unwrap_err() != v2.clone()) { v3.push_str(v2.clone().to_owned()) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:2.0}), cx.hydrate(&quot;line\nbreak&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;76b65706-cc6a-4324-880e-d2d18abea6a9&quot;})]; return () =&gt; (() =&gt; { if ((__external0.clone().unwrap_err().ne(__external1.clone())).dehydrate()) { return __external2.push_str(__external1.clone().to_owned()); } })(); })()
```

## Witness

- rust: Punwrap_err:51:called `Result::unwrap_err()` on an `Ok` value: 2.0|r0:|g3:s5:hello
- js: Pother:48:called `Result.unwrap_err()` on an `Ok` value: 2|r0:|g3:s5:hello
- ref: Punwrap_err:51:called `Result::unwrap_err()` on an `Ok` value: 2.0|r0:|g3:s5:hello
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 20 cands 9 accepted 4
round 1 size 19 cands 8 accepted 4
round 2 size 18 cands 7 accepted 4
round 3 size 17 cands 6 accepted 4
round 4 size 16 cands 5 accepted 4
round 5 size 15 cands 4 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1973 . ../topcoat
```

