# Campaign repro 5059380:3223

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 71 -> 42
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "a\"b";
let v3 = Signal::new(1000000000000000.0);
if false { let v10 = if ((100.0) != v3.get()) { v3.increment() } else if v2.clone().is_empty() { false.then_some({ }).unwrap() }; } else { (if true { false.then_some(false.then_some(false.then_some({ }))) } else { false.then_some(false.then_some(false.then_some({ }))) }).unwrap().unwrap().unwrap() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;4f4878f7-83f0-4306-ba97-ae84597ce930&quot;}), cx.hydrate(&quot;a\&quot;b&quot;)]; return () =&gt; (() =&gt; { if (cx.hydrate(false).dehydrate()) { let __local0 = (() =&gt; { if (((cx.hydrate(100.0)).ne(__external0.get())).dehydrate()) { return __external0.increment(); } else { if (__external1.clone().is_empty().dehydrate()) { return cx.hydrate(false).then_some((() =&gt; {  })()).unwrap(); } } })();  } else { return ((() =&gt; { if (cx.hydrate(true).dehydrate()) { return cx.hydrate(false).then_some(cx.hydrate(false).then_some(cx.hydrate(false).then_some((() =&gt; {  })()))); } else { return cx.hydrate(false).then_some(cx.hydrate(false).then_some(cx.hydrate(false).then_some((() =&gt; {  })()))); } })()).unwrap().unwrap().unwrap(); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1124887541:640942080;
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:f1124887541:640942080;
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1124887541:640942080;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 71 cands 11 accepted 3
round 1 size 64 cands 11 accepted 4
round 2 size 48 cands 12 accepted 6
round 3 size 47 cands 11 accepted 6
round 4 size 46 cands 10 accepted 6
round 5 size 45 cands 9 accepted 6
round 6 size 44 cands 8 accepted 6
round 7 size 43 cands 7 accepted 6
round 8 size 42 cands 6 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3223 . ../topcoat
```

