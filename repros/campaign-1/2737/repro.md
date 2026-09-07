# Campaign repro 5059380:2737

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 28 -> 8
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Ok("a\"b");
let v3 = Signal::new(f64::NAN);
{ v3.set(v7.clone().unwrap_err()); }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;387b59a8-645c-44ec-89b8-3714841cf99f&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;a\&quot;b&quot;})]; return () =&gt; { __external0.set(__external1.clone().unwrap_err());  }; })()
```

## Witness

- rust: Punwrap_err:54:called `Result::unwrap_err()` on an `Ok` value: "a\"b"|r0:|g3:f2146959360:1;
- js: Pother:50:called `Result.unwrap_err()` on an `Ok` value: a"b|r0:|g3:f2146959360:1;
- ref: Punwrap_err:54:called `Result::unwrap_err()` on an `Ok` value: "a\"b"|r0:|g3:f2146959360:1;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 28 cands 9 accepted 1
round 1 size 25 cands 8 accepted 1
round 2 size 14 cands 8 accepted 2
round 3 size 13 cands 7 accepted 2
round 4 size 12 cands 6 accepted 2
round 5 size 11 cands 5 accepted 2
round 6 size 10 cands 4 accepted 2
round 7 size 9 cands 3 accepted 2
round 8 size 8 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2737 . ../topcoat
```

