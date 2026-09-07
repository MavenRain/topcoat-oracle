# Campaign repro 5059380:654

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
let v6: Result<f64, String> = Ok(-f64::INFINITY);
let v3 = Signal::new("a");
v3.set(v6.clone().expect_err(" lead"))
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;8f3e767e-5b56-457f-8225-19a724965b60&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:null})]; return () =&gt; __external0.set(__external1.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot; lead&quot;}))); })()
```

## Witness

- rust: Pexpect_err:11: lead: -inf|r0:|g3:s1:a
- js: Pexpect_err:16: lead: undefined|r0:|g3:s1:a
- ref: Pexpect_err:11: lead: -inf|r0:|g3:s1:a
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
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 654 . ../topcoat
```

