# Campaign repro 5059380:1303

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 35 -> 27
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v8: Option<f64> = Some(1.2345678901234568e17);
let v3 = Signal::new(2.0);
{ let v11 = (if false { false.then_some({ }) } else { false.then_some({ }) }).unwrap(); { let v12 = v3.increment(); v3.get(); loop { { }; v8.clone(); v3.increment(); break; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;75135361-2ab4-4feb-aa0c-598640ba9e86&quot;}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:1.2345678901234568e+17})]; return () =&gt; { let __local0 = ((() =&gt; { if (cx.hydrate(false).dehydrate()) { return cx.hydrate(false).then_some((() =&gt; {  })()); } else { return cx.hydrate(false).then_some((() =&gt; {  })()); } })()).unwrap(); (() =&gt; { let __local1 = __external0.increment(); __external0.get(); while (true) { (() =&gt; {  })(); __external1.clone(); __external0.increment(); break;  };  })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1073741824:0;
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:f1073741824:0;
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1073741824:0;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 35 cands 10 accepted 1
round 1 size 33 cands 9 accepted 3
round 2 size 32 cands 8 accepted 3
round 3 size 31 cands 7 accepted 3
round 4 size 30 cands 6 accepted 3
round 5 size 29 cands 5 accepted 3
round 6 size 28 cands 4 accepted 3
round 7 size 27 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1303 . ../topcoat
```

