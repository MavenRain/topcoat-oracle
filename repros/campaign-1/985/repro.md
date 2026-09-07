# Campaign repro 5059380:985

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 59 -> 53
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v9: Option<String> = Some("");
let v3 = Signal::new(true);
v3.set((if (!v9.clone().is_some()) { if true { let v10 = if true { true } else { true }; if false { false.then_some(false) } else { false.then_some(false) } } else if v3.get() { false.then_some(false.then_some(true)).unwrap() } else if true { false.then_some(false) } else { false.then_some(false) } } else { false.then_some(true) }).unwrap())
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;2f550b7e-8b4f-4fbd-9e58-06c2169f3e49&quot;}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:&quot;&quot;})]; return () =&gt; __external0.set(((() =&gt; { if ((__external1.clone().is_some().not()).dehydrate()) { return (() =&gt; { if (cx.hydrate(true).dehydrate()) { let __local0 = (() =&gt; { if (cx.hydrate(true).dehydrate()) { return cx.hydrate(true); } else { return cx.hydrate(true); } })(); return (() =&gt; { if (cx.hydrate(false).dehydrate()) { return cx.hydrate(false).then_some(cx.hydrate(false)); } else { return cx.hydrate(false).then_some(cx.hydrate(false)); } })(); } else { if (__external0.get().dehydrate()) { return cx.hydrate(false).then_some(cx.hydrate(false).then_some(cx.hydrate(true))).unwrap(); } else { if (cx.hydrate(true).dehydrate()) { return cx.hydrate(false).then_some(cx.hydrate(false)); } else { return cx.hydrate(false).then_some(cx.hydrate(false)); } } } })(); } else { return cx.hydrate(false).then_some(cx.hydrate(true)); } })()).unwrap()); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b1
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 59 cands 7 accepted 1
round 1 size 58 cands 6 accepted 1
round 2 size 57 cands 5 accepted 1
round 3 size 56 cands 4 accepted 1
round 4 size 55 cands 3 accepted 1
round 5 size 54 cands 2 accepted 1
round 6 size 53 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 985 . ../topcoat
```

