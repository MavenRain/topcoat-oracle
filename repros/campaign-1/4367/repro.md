# Campaign repro 5059380:4367

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 15 -> 8
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(false);
let v4 = Signal::new(true);
if v4.get() { } else { v3.toggle() }
```

## Emitted JS

- form: direct

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;724c7ce3-c7e7-40bf-83d0-53f65718868e&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;a410a3a7-63df-4680-9e5f-5ca3b0379163&quot;})]; return (() =&gt; { if (__external0.get().dehydrate()) {  } else { return __external1.toggle(); } })(); })()
```

## Witness

- rust: Vu|r0:|g3:b0g4:b1
- js: Vu|r0:|g3:b0g4:b0
- ref: Vu|r0:|g3:b0g4:b1
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 15 cands 12 accepted 5
round 1 size 14 cands 11 accepted 5
round 2 size 13 cands 10 accepted 5
round 3 size 12 cands 9 accepted 5
round 4 size 11 cands 8 accepted 5
round 5 size 10 cands 7 accepted 5
round 6 size 9 cands 6 accepted 5
round 7 size 8 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4367 . ../topcoat
```

