# Campaign repro 5059380:3369

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 46 -> 23
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "é";
let v7: Result<String, f64> = Ok("I8saPT8");
let v3 = Signal::new("hello");
{ { let v11 = v7.clone().expect_err("0"); let v12 = v3.set(v2.clone()); if true { v3.set(v2.clone()) }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;I8saPT8&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;90d2e77f-9d3b-456f-a020-f009b41e7890&quot;}), cx.hydrate(&quot;é&quot;)]; return () =&gt; { (() =&gt; { let __local0 = __external0.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;0&quot;})); let __local1 = __external1.set(__external2.clone()); (() =&gt; { if (cx.hydrate(true).dehydrate()) { return __external1.set(__external2.clone()); } })();  })();  }; })()
```

## Witness

- rust: Pexpect_err:12:0: "I8saPT8"|r0:|g3:s5:hello
- js: Pexpect_err:10:0: I8saPT8|r0:|g3:s5:hello
- ref: Pexpect_err:12:0: "I8saPT8"|r0:|g3:s5:hello
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 46 cands 9 accepted 1
round 1 size 30 cands 8 accepted 1
round 2 size 28 cands 7 accepted 2
round 3 size 27 cands 6 accepted 2
round 4 size 26 cands 5 accepted 2
round 5 size 25 cands 4 accepted 2
round 6 size 24 cands 3 accepted 2
round 7 size 23 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3369 . ../topcoat
```

