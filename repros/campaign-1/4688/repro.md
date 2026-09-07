# Campaign repro 5059380:4688

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 70 -> 34
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Ok(1e-5);
let v3 = Signal::new("tab\t");
{ v6.clone().expect_err("hello world"); { { v6.clone().ok(); let v10 = v3.get().to_owned(); loop { v3.set(v10.clone()); break; }; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.00001}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;aae5fc18-a17d-46dc-9465-2c07c0f3650d&quot;})]; return () =&gt; { __external0.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;hello world&quot;})); (() =&gt; { (() =&gt; { __external0.clone().ok(); let __local0 = __external1.get().to_owned(); while (true) { __external1.set(__local0.clone()); break;  };  })();  })();  }; })()
```

## Witness

- rust: Pexpect_err:17:hello world: 1e-5|r0:|g3:s4:tab	
- js: Pexpect_err:20:hello world: 0.00001|r0:|g3:s4:tab	
- ref: Pexpect_err:17:hello world: 1e-5|r0:|g3:s4:tab	
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 70 cands 19 accepted 1
round 1 size 40 cands 9 accepted 3
round 2 size 39 cands 8 accepted 3
round 3 size 38 cands 7 accepted 3
round 4 size 37 cands 6 accepted 3
round 5 size 36 cands 5 accepted 3
round 6 size 35 cands 4 accepted 3
round 7 size 34 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4688 . ../topcoat
```

