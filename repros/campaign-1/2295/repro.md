# Campaign repro 5059380:2295

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 28 -> 23
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "hello";
let v7: Result<String, f64> = Ok("a");
let v3 = Signal::new("a\\b");
{ { v2.clone().to_owned(); v7.clone().expect_err("0"); loop { let v10 = -0.0; v3.push_str(v2.clone()); break; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate(&quot;hello&quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;a&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;72a81bb1-7c73-4c19-8dbb-2c58dcbc4a6a&quot;})]; return () =&gt; { (() =&gt; { __external0.clone().to_owned(); __external1.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;0&quot;})); while (true) { let __local0 = cx.hydrate(0.0).neg(); __external2.push_str(__external0.clone()); break;  };  })();  }; })()
```

## Witness

- rust: Pexpect_err:6:0: "a"|r0:|g3:s3:a\b
- js: Pexpect_err:4:0: a|r0:|g3:s3:a\b
- ref: Pexpect_err:6:0: "a"|r0:|g3:s3:a\b
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 28 cands 7 accepted 2
round 1 size 27 cands 6 accepted 2
round 2 size 26 cands 5 accepted 2
round 3 size 25 cands 4 accepted 2
round 4 size 24 cands 3 accepted 2
round 5 size 23 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2295 . ../topcoat
```

