# Campaign repro 5059380:2149

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:class:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 69 -> 66
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v2: String = "a\"b";
let v6: Result<f64, String> = Ok(1e-5);
let v8: Option<f64> = Some(100.0);
let v3 = Signal::new(0.1);
let v4 = Signal::new(-0.0);
{ { if v6.clone().expect_err("b").is_empty() { } else if (!v8.clone().is_none()) { }; if v1 { if (if false.then_some(false).expect("hello world") { if false { false } else { false } } else { let v10 = v2.clone(); false }) { if false.then_some(true).expect("a") { { }; { } } else { v3.increment() } } else { v4.decrement() } }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4, __external5] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:0.00001}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:100.0}), cx.hydrate(false), cx.hydrate(&quot;a\&quot;b&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;79863e84-7b03-4d6b-b38e-c649eb970b4a&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;f85a8560-1dd7-4c50-8d37-24451f47471e&quot;})]; return () =&gt; { (() =&gt; { (() =&gt; { if (__external0.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;b&quot;})).is_empty().dehydrate()) {  } else { if ((__external1.clone().is_none().not()).dehydrate()) {  } } })(); (() =&gt; { if (__external2.dehydrate()) { return (() =&gt; { if (((() =&gt; { if (cx.hydrate(false).then_some(cx.hydrate(false)).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;hello world&quot;})).dehydrate()) { return (() =&gt; { if (cx.hydrate(false).dehydrate()) { return cx.hydrate(false); } else { return cx.hydrate(false); } })(); } else { let __local0 = __external3.clone(); return cx.hydrate(false); } })()).dehydrate()) { return (() =&gt; { if (cx.hydrate(false).then_some(cx.hydrate(true)).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;a&quot;})).dehydrate()) { (() =&gt; {  })(); return (() =&gt; {  })(); } else { return __external4.increment(); } })(); } else { return __external5.decrement(); } })(); } })();  })();  }; })()
```

## Witness

- rust: Pother:7:b: 1e-5|r0:|g3:f1069128089:2576980378;g4:f2147483648:0;
- js: Pother:10:b: 0.00001|r0:|g3:f1069128089:2576980378;g4:f2147483648:0;
- ref: Pexpect_err:7:b: 1e-5|r0:|g3:f1069128089:2576980378;g4:f2147483648:0;
- verdict: diverge:class:two_way

## Walk

```text
round 0 size 69 cands 5 accepted 2
round 1 size 68 cands 4 accepted 2
round 2 size 67 cands 3 accepted 2
round 3 size 66 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2149 . ../topcoat
```

