# Campaign repro 5059380:2425

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 34 -> 27
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v3 = Signal::new(1e-5);
if v1.then_some(false.then_some(false)).unwrap().expect("quote\"and\\back") { v3.decrement() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate(false), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;cdb47973-383c-404e-a3c5-bb72a56c3b41&quot;})]; return () =&gt; (() =&gt; { if (__external0.then_some(cx.hydrate(false).then_some(cx.hydrate(false))).unwrap().expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;quote\&quot;and\\back&quot;})).dehydrate()) { return __external1.decrement(); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1055193269:2296604913;
- js: Pexpect:42:called `Option.unwrap()` on a `None` value|r0:|g3:f1055193269:2296604913;
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1055193269:2296604913;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 34 cands 12 accepted 3
round 1 size 33 cands 10 accepted 4
round 2 size 32 cands 9 accepted 4
round 3 size 31 cands 8 accepted 4
round 4 size 30 cands 7 accepted 4
round 5 size 29 cands 6 accepted 4
round 6 size 28 cands 5 accepted 4
round 7 size 27 cands 4 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2425 . ../topcoat
```

