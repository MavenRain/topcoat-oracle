# Campaign repro 5059380:3305

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 32 -> 26
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = " pad ";
let v8: Option<f64> = Some(-f64::INFINITY);
let v9: Option<String> = Some("a\"b");
let v3 = Signal::new("a\\b");
{ let v11 = (if v8.clone().is_some() { false.then_some(v9.clone()) } else { false.then_some(v9.clone()) }).unwrap(); loop { v3.push_str(v2.clone()); break; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:&quot;a\&quot;b&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;ca3f0c7f-d177-4f72-baa8-c4dbb8cfca22&quot;}), cx.hydrate(&quot; pad &quot;)]; return () =&gt; { let __local0 = ((() =&gt; { if (__external0.clone().is_some().dehydrate()) { return cx.hydrate(false).then_some(__external1.clone()); } else { return cx.hydrate(false).then_some(__external1.clone()); } })()).unwrap(); while (true) { __external2.push_str(__external3.clone()); break;  };  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s3:a\b
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s3:a\b
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s3:a\b
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 32 cands 7 accepted 1
round 1 size 30 cands 7 accepted 3
round 2 size 29 cands 6 accepted 3
round 3 size 28 cands 5 accepted 3
round 4 size 27 cands 4 accepted 3
round 5 size 26 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3305 . ../topcoat
```

