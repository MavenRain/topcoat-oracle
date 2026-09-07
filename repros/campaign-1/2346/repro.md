# Campaign repro 5059380:2346

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 53 -> 43
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v2: String = "tab\t";
let v6: Result<f64, String> = Ok(1e300);
let v3 = Signal::new(-2.588322640640313e138);
if v6.clone().unwrap_err().is_empty() { if (if (v2.clone() >= v2.clone()) { true } else { v1 }) { if (if false { true } else { false }) { let v10 = v2.clone(); true; v3.decrement(); } } else if ({ false }) { if true { } else { } } else { }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:1e+300}), cx.hydrate(&quot;tab\t&quot;), cx.hydrate(false), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;11579c6c-ad37-4c16-952b-9896cb1d7e19&quot;})]; return () =&gt; (() =&gt; { if (__external0.clone().unwrap_err().is_empty().dehydrate()) { (() =&gt; { if (((() =&gt; { if ((__external1.clone().ge(__external1.clone())).dehydrate()) { return cx.hydrate(true); } else { return __external2; } })()).dehydrate()) { return (() =&gt; { if (((() =&gt; { if (cx.hydrate(false).dehydrate()) { return cx.hydrate(true); } else { return cx.hydrate(false); } })()).dehydrate()) { let __local0 = __external1.clone(); cx.hydrate(true); __external3.decrement();  } })(); } else { if (((() =&gt; { return cx.hydrate(false); })()).dehydrate()) { return (() =&gt; { if (cx.hydrate(true).dehydrate()) {  } else {  } })(); } else {  } } })();  } })(); })()
```

## Witness

- rust: Punwrap_err:53:called `Result::unwrap_err()` on an `Ok` value: 1e300|r0:|g3:f3702247971:778096713;
- js: Pother:348:called `Result.unwrap_err()` on an `Ok` value: 1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000|r0:|g3:f3702247971:778096713;
- ref: Punwrap_err:53:called `Result::unwrap_err()` on an `Ok` value: 1e300|r0:|g3:f3702247971:778096713;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 53 cands 10 accepted 4
round 1 size 47 cands 9 accepted 5
round 2 size 46 cands 8 accepted 5
round 3 size 45 cands 7 accepted 5
round 4 size 44 cands 6 accepted 5
round 5 size 43 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2346 . ../topcoat
```

