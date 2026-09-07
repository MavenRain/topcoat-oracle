# Campaign repro 5059380:2646

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 37 -> 30
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "a\"b";
let v8: Option<f64> = None::<f64>;
let v3 = Signal::new(false);
let v4 = Signal::new("😀");
{ { let v11 = if false { let v10 = v2.clone(); true } else { v3.get() }; { v8.clone().unwrap(); { let v12 = { }; 1.5; v4.set(v2.clone()); }; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate(&quot;a\&quot;b&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;c3c6fb8b-7a2f-4fbc-8312-1a2bbf16edef&quot;}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;eed16028-95db-45f2-a2d6-c420e31cc9a0&quot;})]; return () =&gt; { (() =&gt; { let __local0 = (() =&gt; { if (cx.hydrate(false).dehydrate()) { let __local1 = __external0.clone(); return cx.hydrate(true); } else { return __external1.get(); } })(); (() =&gt; { __external2.clone().unwrap(); (() =&gt; { let __local2 = (() =&gt; {  })(); cx.hydrate(1.5); __external3.set(__external0.clone());  })();  })();  })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b0g4:s4:😀
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b0g4:s4:😀
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b0g4:s4:😀
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 37 cands 8 accepted 1
round 1 size 35 cands 7 accepted 2
round 2 size 34 cands 6 accepted 2
round 3 size 33 cands 5 accepted 2
round 4 size 32 cands 4 accepted 2
round 5 size 31 cands 3 accepted 2
round 6 size 30 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2646 . ../topcoat
```

