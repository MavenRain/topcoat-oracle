# Campaign repro 5059380:1659

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 99 -> 96
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "y";
let v7: Result<String, f64> = Ok("");
let v8: Option<f64> = None::<f64>;
let v9: Option<String> = Some("a");
let v3 = Signal::new(-1.0);
let v4 = Signal::new(false);
{ { let v10 = v2.clone(); if (v8.clone().unwrap() != (v8.clone().expect("trail ") / v10.clone().len())) { v9.clone().expect("b") } else { (if (if true { true } else { false }) { v10.clone() } else { v7.clone().unwrap() }).to_owned() }; while false.then_some(false).expect(" lead") { let v11 = v2.clone(); let v12 = if v4.get() { ({ false.then_some(false) }).unwrap() } else { v8.clone().is_some() }; { v10.clone(); { { v10.clone(); { } }; if true { } else { }; { 0.0; v3.set(1e300); }; }; }; break; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4, __external5] = [cx.hydrate(&quot;y&quot;), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:&quot;a&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:&quot;&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;8943fd8c-2c1f-47b6-8394-16a65d126b7d&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;df0cc5ee-eb7b-42d8-9898-ec782027118e&quot;})]; return () =&gt; { (() =&gt; { let __local0 = __external0.clone(); (() =&gt; { if ((__external1.clone().unwrap().ne((__external1.clone().expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;trail &quot;})).div(__local0.clone().len())))).dehydrate()) { return __external2.clone().expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;b&quot;})); } else { return ((() =&gt; { if (((() =&gt; { if (cx.hydrate(true).dehydrate()) { return cx.hydrate(true); } else { return cx.hydrate(false); } })()).dehydrate()) { return __local0.clone(); } else { return __external3.clone().unwrap(); } })()).to_owned(); } })(); while (cx.hydrate(false).then_some(cx.hydrate(false)).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot; lead&quot;})).dehydrate()) { let __local1 = __external0.clone(); let __local2 = (() =&gt; { if (__external4.get().dehydrate()) { return ((() =&gt; { return cx.hydrate(false).then_some(cx.hydrate(false)); })()).unwrap(); } else { return __external1.clone().is_some(); } })(); (() =&gt; { __local0.clone(); (() =&gt; { (() =&gt; { __local0.clone(); return (() =&gt; {  })(); })(); (() =&gt; { if (cx.hydrate(true).dehydrate()) {  } else {  } })(); (() =&gt; { cx.hydrate(0.0); __external5.set(cx.hydrate(1e+300));  })();  })();  })(); break;  };  })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f3220176896:0;g4:b0
- js: Pexpect:42:called `Option.unwrap()` on a `None` value|r0:|g3:f3220176896:0;g4:b0
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f3220176896:0;g4:b0
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 99 cands 5 accepted 2
round 1 size 98 cands 4 accepted 2
round 2 size 97 cands 3 accepted 2
round 3 size 96 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1659 . ../topcoat
```

