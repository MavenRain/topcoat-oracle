# Campaign repro 5059380:2561

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 21 -> 16
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "line\nbreak";
let v7: Result<String, f64> = Err(1.0);
let v3 = Signal::new(true);
let v4 = Signal::new(" pad ");
{ v4.set(v7.clone().unwrap()); v3.set(v2.clone().to_owned().is_empty()); }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;7b9ccf2c-117a-4119-b0b6-7c3fb544f0aa&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:1.0}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;f9d7c71f-c56e-478c-873a-bf72827ee657&quot;}), cx.hydrate(&quot;line\nbreak&quot;)]; return () =&gt; { __external0.set(__external1.clone().unwrap()); __external2.set(__external3.clone().to_owned().is_empty());  }; })()
```

## Witness

- rust: Punwrap:48:called `Result::unwrap()` on an `Err` value: 1.0|r0:|g3:b1g4:s5: pad 
- js: Pother:45:called `Result.unwrap()` on an `Err` value: 1|r0:|g3:b1g4:s5: pad 
- ref: Punwrap:48:called `Result::unwrap()` on an `Err` value: 1.0|r0:|g3:b1g4:s5: pad 
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 21 cands 8 accepted 3
round 1 size 20 cands 7 accepted 3
round 2 size 19 cands 6 accepted 3
round 3 size 18 cands 5 accepted 3
round 4 size 17 cands 4 accepted 3
round 5 size 16 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2561 . ../topcoat
```

