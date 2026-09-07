# Campaign repro 5059380:1249

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 50 -> 45
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = " pad ";
let v7: Result<String, f64> = Err(1.2345678901234568e17);
let v3 = Signal::new("a");
{ { let v10 = if (!(v2.clone() > v2.clone())) { !v2.clone().is_empty() } else { v2.clone() == (if true { v2.clone() } else { v2.clone() }) }; { v7.clone(); { false.then_some(false).unwrap(); let v11 = { }; if true { } else { v3.set(v2.clone()) }; }; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate(&quot; pad &quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:1.2345678901234568e+17}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;954cc867-efba-4944-893e-8c780547facb&quot;})]; return () =&gt; { (() =&gt; { let __local0 = (() =&gt; { if (((__external0.clone().gt(__external0.clone())).not()).dehydrate()) { return __external0.clone().is_empty().not(); } else { return __external0.clone().eq(((() =&gt; { if (cx.hydrate(true).dehydrate()) { return __external0.clone(); } else { return __external0.clone(); } })())); } })(); (() =&gt; { __external1.clone(); (() =&gt; { cx.hydrate(false).then_some(cx.hydrate(false)).unwrap(); let __local1 = (() =&gt; {  })(); (() =&gt; { if (cx.hydrate(true).dehydrate()) {  } else { return __external2.set(__external0.clone()); } })();  })();  })();  })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s1:a
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s1:a
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s1:a
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 50 cands 7 accepted 2
round 1 size 49 cands 6 accepted 2
round 2 size 48 cands 5 accepted 2
round 3 size 47 cands 4 accepted 2
round 4 size 46 cands 3 accepted 2
round 5 size 45 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1249 . ../topcoat
```

