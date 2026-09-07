# Campaign repro 5059380:1543

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 19 -> 13
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Ok("a\"b");
let v3 = Signal::new(0.5);
v3.set(v7.clone().expect_err("café"))
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;5e14ad4f-8796-47f0-9284-841e9b6647ac&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;a\&quot;b&quot;})]; return () =&gt; __external0.set(__external1.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;café&quot;}))); })()
```

## Witness

- rust: Pexpect_err:13:café: "a\"b"|r0:|g3:f1071644672:0;
- js: Pexpect_err:10:café: a"b|r0:|g3:f1071644672:0;
- ref: Pexpect_err:13:café: "a\"b"|r0:|g3:f1071644672:0;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 19 cands 7 accepted 1
round 1 size 18 cands 6 accepted 1
round 2 size 17 cands 5 accepted 1
round 3 size 16 cands 4 accepted 1
round 4 size 15 cands 3 accepted 1
round 5 size 14 cands 2 accepted 1
round 6 size 13 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1543 . ../topcoat
```

