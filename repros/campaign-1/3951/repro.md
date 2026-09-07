# Campaign repro 5059380:3951

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 21 -> 15
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = " pad ";
let v3 = Signal::new(true);
v3.set(if v2.clone().is_empty() { v2.clone().is_empty() } else { false.then_some(false).unwrap() })
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;7c54185d-abdd-4a63-8caa-e121afe93251&quot;}), cx.hydrate(&quot; pad &quot;)]; return () =&gt; __external0.set((() =&gt; { if (__external1.clone().is_empty().dehydrate()) { return __external1.clone().is_empty(); } else { return cx.hydrate(false).then_some(cx.hydrate(false)).unwrap(); } })()); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b1
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 21 cands 7 accepted 1
round 1 size 20 cands 6 accepted 1
round 2 size 19 cands 5 accepted 1
round 3 size 18 cands 4 accepted 1
round 4 size 17 cands 3 accepted 1
round 5 size 16 cands 2 accepted 1
round 6 size 15 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3951 . ../topcoat
```

