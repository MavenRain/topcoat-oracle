# Campaign repro 5059380:3716

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 16 -> 8
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(-1.203539345399989e-41);
let v4 = Signal::new(false);
if v4.get() { } else { v3.decrement() }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;ebdb509f-4139-43c0-bf1e-530451358369&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;9f6657ed-d2fa-4091-952a-a2ede80e33fd&quot;})]; return () =&gt; (() =&gt; { if (__external0.get().dehydrate()) {  } else { return __external1.decrement(); } })(); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f3077621343:869446999;g4:b0
- js: Vu|r0:|g3:f3077621343:869446999;g4:b0
- ref: Vu|r0:|g3:f3220176896:0;g4:b0
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 16 cands 14 accepted 4
round 1 size 15 cands 12 accepted 5
round 2 size 14 cands 11 accepted 5
round 3 size 13 cands 10 accepted 5
round 4 size 12 cands 9 accepted 5
round 5 size 11 cands 8 accepted 5
round 6 size 10 cands 7 accepted 5
round 7 size 9 cands 6 accepted 5
round 8 size 8 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3716 . ../topcoat
```

