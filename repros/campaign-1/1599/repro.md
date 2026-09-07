# Campaign repro 5059380:1599

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 56 -> 30
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = true;
let v2: String = "a";
let v3 = Signal::new("a");
{ while (if v1 { false.then_some(false.then_some(false)) } else { false.then_some(false.then_some(false)) }).unwrap().unwrap() { false; v3.set(v2.clone()); v3.push_str(v2.clone()); break; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate(true), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;05165ed4-6b06-49c7-860e-64ad48a8d883&quot;}), cx.hydrate(&quot;a&quot;)]; return () =&gt; { while (((() =&gt; { if (__external0.dehydrate()) { return cx.hydrate(false).then_some(cx.hydrate(false).then_some(cx.hydrate(false))); } else { return cx.hydrate(false).then_some(cx.hydrate(false).then_some(cx.hydrate(false))); } })()).unwrap().unwrap().dehydrate()) { cx.hydrate(false); __external1.set(__external2.clone()); __external1.push_str(__external2.clone()); break;  };  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s1:a
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s1:a
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s1:a
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 56 cands 9 accepted 1
round 1 size 52 cands 8 accepted 1
round 2 size 35 cands 7 accepted 2
round 3 size 34 cands 6 accepted 2
round 4 size 33 cands 5 accepted 2
round 5 size 32 cands 4 accepted 2
round 6 size 31 cands 3 accepted 2
round 7 size 30 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1599 . ../topcoat
```

