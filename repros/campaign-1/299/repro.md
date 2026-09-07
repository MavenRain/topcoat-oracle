# Campaign repro 5059380:299

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 35 -> 28
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "a";
let v3 = Signal::new(1.0);
let v4 = Signal::new(2.0);
if false { v3.set(if (v2.clone() > v2.clone()) { 1000000000000000.0 } else { v4.get() }) } else { (if v2.clone().is_empty() { false.then_some({ }) } else { false.then_some({ }) }).unwrap() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;952cce81-f59a-43e2-9c29-2b35658dc005&quot;}), cx.hydrate(&quot;a&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;e622b66d-71dc-4353-a9aa-4d9ea4e63d0b&quot;})]; return () =&gt; (() =&gt; { if (cx.hydrate(false).dehydrate()) { return __external0.set((() =&gt; { if ((__external1.clone().gt(__external1.clone())).dehydrate()) { return cx.hydrate(1000000000000000.0); } else { return __external2.get(); } })()); } else { return ((() =&gt; { if (__external1.clone().is_empty().dehydrate()) { return cx.hydrate(false).then_some((() =&gt; {  })()); } else { return cx.hydrate(false).then_some((() =&gt; {  })()); } })()).unwrap(); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1072693248:0;g4:f1073741824:0;
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:f1072693248:0;g4:f1073741824:0;
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1072693248:0;g4:f1073741824:0;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 35 cands 12 accepted 3
round 1 size 34 cands 11 accepted 5
round 2 size 33 cands 10 accepted 5
round 3 size 32 cands 9 accepted 5
round 4 size 31 cands 8 accepted 5
round 5 size 30 cands 7 accepted 5
round 6 size 29 cands 6 accepted 5
round 7 size 28 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 299 . ../topcoat
```

