# Campaign repro 5059380:1844

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:class:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 81 -> 42
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Ok(1000000000000000.0);
let v8: Option<f64> = None::<f64>;
let v9: Option<String> = None::<String>;
let v3 = Signal::new("");
let v4 = Signal::new(0.5);
if v9.clone().expect("quote\"and\\back").is_empty() { v4.set(v8.clone().unwrap()) } else { v3.set(v6.clone().expect_err("trail ")) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4] = [cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;845e4e2d-4b71-4949-a347-4e814285ddc6&quot;}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;06ec4726-cc75-4a57-a753-7afa16c91e0f&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:1000000000000000.0})]; return () =&gt; (() =&gt; { if (__external0.clone().expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;quote\&quot;and\\back&quot;})).is_empty().dehydrate()) { return __external1.set(__external2.clone().unwrap()); } else { return __external3.set(__external4.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;trail &quot;}))); } })(); })()
```

## Witness

- rust: Pother:14:quote"and\back|r0:|g3:s0:g4:f1071644672:0;
- js: Pother:14:quote"and\back|r0:|g3:s0:g4:f1071644672:0;
- ref: Pexpect:14:quote"and\back|r0:|g3:s0:g4:f1071644672:0;
- verdict: diverge:class:two_way

## Walk

```text
round 0 size 81 cands 23 accepted 5
round 1 size 68 cands 17 accepted 5
round 2 size 56 cands 13 accepted 6
round 3 size 46 cands 10 accepted 6
round 4 size 45 cands 9 accepted 6
round 5 size 44 cands 8 accepted 6
round 6 size 43 cands 7 accepted 6
round 7 size 42 cands 6 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1844 . ../topcoat
```

