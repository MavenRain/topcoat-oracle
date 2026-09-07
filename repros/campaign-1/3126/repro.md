# Campaign repro 5059380:3126

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 42 -> 37
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v6: Result<f64, String> = Ok(1e16);
let v7: Result<String, f64> = Ok("");
let v3 = Signal::new(false);
{ { { v7.clone().ok(); let v10 = if true { }; }; v6.clone().expect_err("hello world").to_owned(); { if false { v3.set(true) }; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:1e+16}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;b4412b04-d829-4316-97a8-fc10c7f5874c&quot;})]; return () =&gt; { (() =&gt; { (() =&gt; { __external0.clone().ok(); let __local0 = (() =&gt; { if (cx.hydrate(true).dehydrate()) {  } })();  })(); __external1.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;hello world&quot;})).to_owned(); (() =&gt; { (() =&gt; { if (cx.hydrate(false).dehydrate()) { return __external2.set(cx.hydrate(true)); } })();  })();  })();  }; })()
```

## Witness

- rust: Pexpect_err:17:hello world: 1e16|r0:|g3:b0
- js: Pexpect_err:30:hello world: 10000000000000000|r0:|g3:b0
- ref: Pexpect_err:17:hello world: 1e16|r0:|g3:b0
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 42 cands 7 accepted 2
round 1 size 41 cands 6 accepted 2
round 2 size 40 cands 5 accepted 2
round 3 size 39 cands 4 accepted 2
round 4 size 38 cands 3 accepted 2
round 5 size 37 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3126 . ../topcoat
```

