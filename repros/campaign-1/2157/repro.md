# Campaign repro 5059380:2157

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:odd:js
- original mode: read_only
- final mode: read_only
- size: 89 -> 11
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(false);
(if v3.get() { false.then_some({ }) } else { false.then_some({ }) }).unwrap()
```

## Emitted JS

- form: closure

```js
(() => { const [__external0] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;0a1dedf5-f7ac-4864-90e8-e782cabfd95b&quot;})]; return () =&gt; ((() =&gt; { if (__external0.get().dehydrate()) { return cx.hydrate(false).then_some((() =&gt; {  })()); } else { return cx.hydrate(false).then_some((() =&gt; {  })()); } })()).unwrap(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b0
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b0
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b0
- verdict: diverge:message:odd:js

## Walk

```text
round 0 size 89 cands 13 accepted 2
round 1 size 18 cands 8 accepted 1
round 2 size 17 cands 7 accepted 1
round 3 size 16 cands 6 accepted 1
round 4 size 15 cands 5 accepted 1
round 5 size 14 cands 4 accepted 1
round 6 size 13 cands 3 accepted 1
round 7 size 12 cands 2 accepted 1
round 8 size 11 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2157 . ../topcoat
```

