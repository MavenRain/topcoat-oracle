# Campaign repro 5059380:2490

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 52 -> 28
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v2: String = "a";
let v7: Result<String, f64> = Ok("😀");
let v8: Option<f64> = Some(0.1);
let v3 = Signal::new("é");
if v7.clone().is_err().then_some(v1).unwrap() { } else { { v8.clone().is_none(); { }; { if true { v3.set(v2.clone()) } else { }; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;😀&quot;}), cx.hydrate(false), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:0.1}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;36c65184-61b9-4b1a-936a-54eb5a1e1c8e&quot;}), cx.hydrate(&quot;a&quot;)]; return () =&gt; (() =&gt; { if (__external0.clone().is_err().then_some(__external1).unwrap().dehydrate()) {  } else { (() =&gt; { __external2.clone().is_none(); (() =&gt; {  })(); (() =&gt; { (() =&gt; { if (cx.hydrate(true).dehydrate()) { return __external3.set(__external4.clone()); } else {  } })();  })();  })();  } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s2:é
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s2:é
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s2:é
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 52 cands 14 accepted 5
round 1 size 47 cands 11 accepted 5
round 2 size 44 cands 10 accepted 5
round 3 size 31 cands 9 accepted 6
round 4 size 30 cands 8 accepted 6
round 5 size 29 cands 7 accepted 6
round 6 size 28 cands 6 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2490 . ../topcoat
```

