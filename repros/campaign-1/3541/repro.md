# Campaign repro 5059380:3541

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 35 -> 26
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = true;
let v2: String = "a\"b";
let v3 = Signal::new("hello");
if (if v1 { false.then_some(false.then_some(true)).unwrap() } else { false.then_some(false.then_some(true)).unwrap() }).unwrap() { } else { v3.set(v2.clone()) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate(true), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;52c1a229-9f7e-499f-bd66-a074754007cf&quot;}), cx.hydrate(&quot;a\&quot;b&quot;)]; return () =&gt; (() =&gt; { if (((() =&gt; { if (__external0.dehydrate()) { return cx.hydrate(false).then_some(cx.hydrate(false).then_some(cx.hydrate(true))).unwrap(); } else { return cx.hydrate(false).then_some(cx.hydrate(false).then_some(cx.hydrate(true))).unwrap(); } })()).unwrap().dehydrate()) {  } else { return __external1.set(__external2.clone()); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5:hello
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s5:hello
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5:hello
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 35 cands 11 accepted 4
round 1 size 31 cands 10 accepted 5
round 2 size 30 cands 9 accepted 5
round 3 size 29 cands 8 accepted 5
round 4 size 28 cands 7 accepted 5
round 5 size 27 cands 6 accepted 5
round 6 size 26 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3541 . ../topcoat
```

