# Campaign repro 5059380:2103

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 15 -> 9
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Ok(" pad ");
let v3 = Signal::new(-0.0);
v3.set(v7.clone().expect_err("b"))
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;80f4b3ab-3109-4bba-a4f9-35cf4483bc30&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot; pad &quot;})]; return () =&gt; __external0.set(__external1.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;b&quot;}))); })()
```

## Witness

- rust: Pexpect_err:10:b: " pad "|r0:|g3:f2147483648:0;
- js: Pexpect_err:8:b:  pad |r0:|g3:f2147483648:0;
- ref: Pexpect_err:10:b: " pad "|r0:|g3:f2147483648:0;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 15 cands 7 accepted 1
round 1 size 14 cands 6 accepted 1
round 2 size 13 cands 5 accepted 1
round 3 size 12 cands 4 accepted 1
round 4 size 11 cands 3 accepted 1
round 5 size 10 cands 2 accepted 1
round 6 size 9 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2103 . ../topcoat
```

