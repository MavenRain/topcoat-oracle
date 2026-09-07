# Campaign repro 5059380:1114

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 29 -> 18
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "hello";
let v3 = Signal::new("😀");
{ if false.then_some(true).unwrap() { } else if true { v3.set(v2.clone()) } else { }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;901d735d-502f-42a7-a031-bc418dd51abd&quot;}), cx.hydrate(&quot;hello&quot;)]; return () =&gt; { (() =&gt; { if (cx.hydrate(false).then_some(cx.hydrate(true)).unwrap().dehydrate()) {  } else { if (cx.hydrate(true).dehydrate()) { return __external0.set(__external1.clone()); } else {  } } })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s4:😀
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s4:😀
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s4:😀
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 29 cands 9 accepted 1
round 1 size 27 cands 8 accepted 1
round 2 size 24 cands 8 accepted 2
round 3 size 23 cands 7 accepted 2
round 4 size 22 cands 6 accepted 2
round 5 size 21 cands 5 accepted 2
round 6 size 20 cands 4 accepted 2
round 7 size 19 cands 3 accepted 2
round 8 size 18 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1114 . ../topcoat
```

