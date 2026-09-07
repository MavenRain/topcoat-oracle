# Campaign repro 5059380:358

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 23 -> 13
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "line\nbreak";
let v3 = Signal::new(1.6826730902516771e307);
let v4 = Signal::new("");
if false { v4.set(v2.clone()) } else { v3.set(1e16) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;e0cd2466-90af-4289-81db-c5e3d6c81bd4&quot;}), cx.hydrate(&quot;line\nbreak&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;17fc832d-0402-4e55-89db-e4964bee7cad&quot;})]; return () =&gt; (() =&gt; { if (cx.hydrate(false).dehydrate()) { return __external0.set(__external1.clone()); } else { return __external2.set(cx.hydrate(1e+16)); } })(); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f2142762569:2478051276;g4:s0:
- js: Vu|r0:|g3:f2142762569:2478051276;g4:f1128383353:937459712;
- ref: Vu|r0:|g3:f1128383353:937459712;g4:s0:
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 23 cands 14 accepted 3
round 1 size 21 cands 13 accepted 4
round 2 size 19 cands 11 accepted 5
round 3 size 18 cands 10 accepted 5
round 4 size 17 cands 9 accepted 5
round 5 size 16 cands 8 accepted 5
round 6 size 15 cands 7 accepted 5
round 7 size 14 cands 6 accepted 5
round 8 size 13 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 358 . ../topcoat
```

