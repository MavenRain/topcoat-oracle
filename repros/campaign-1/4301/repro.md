# Campaign repro 5059380:4301

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 25 -> 17
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "a\"b";
let v7: Result<String, f64> = Ok("é");
let v3 = Signal::new("é");
{ v7.clone().expect_err(" lead"); v3.set(v2.clone()); }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;é&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;0a524387-9182-4795-922c-bb14bae7a32f&quot;}), cx.hydrate(&quot;a\&quot;b&quot;)]; return () =&gt; { __external0.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot; lead&quot;})); __external1.set(__external2.clone());  }; })()
```

## Witness

- rust: Pexpect_err:11: lead: "é"|r0:|g3:s2:é
- js: Pexpect_err:9: lead: é|r0:|g3:s2:é
- ref: Pexpect_err:11: lead: "é"|r0:|g3:s2:é
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 25 cands 9 accepted 1
round 1 size 22 cands 8 accepted 3
round 2 size 21 cands 7 accepted 3
round 3 size 20 cands 6 accepted 3
round 4 size 19 cands 5 accepted 3
round 5 size 18 cands 4 accepted 3
round 6 size 17 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4301 . ../topcoat
```

