# Campaign repro 5059380:124

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:odd:js
- original mode: read_only
- final mode: read_only
- size: 35 -> 18
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new("😀");
if false { v3.get().starts_with("trail ") } else { false.then_some(true).unwrap() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;7b8c3872-75bd-4212-92a0-4267bdeca95f&quot;})]; return () =&gt; (() =&gt; { if (cx.hydrate(false).dehydrate()) { return __external0.get().starts_with(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;trail &quot;})); } else { return cx.hydrate(false).then_some(cx.hydrate(true)).unwrap(); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s4:😀
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s4:😀
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s4:😀
- verdict: diverge:message:odd:js

## Walk

```text
round 0 size 35 cands 16 accepted 1
round 1 size 34 cands 14 accepted 3
round 2 size 26 cands 14 accepted 4
round 3 size 25 cands 12 accepted 5
round 4 size 24 cands 11 accepted 5
round 5 size 23 cands 10 accepted 5
round 6 size 22 cands 9 accepted 5
round 7 size 21 cands 8 accepted 5
round 8 size 20 cands 7 accepted 5
round 9 size 19 cands 6 accepted 5
round 10 size 18 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 124 . ../topcoat
```

