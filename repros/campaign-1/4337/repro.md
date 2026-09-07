# Campaign repro 5059380:4337

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 24 -> 10
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(true);
let v4 = Signal::new(true);
{ v4.get(); loop { v3.toggle(); break; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;6550b1ce-1e5a-47b4-9a47-bcace0ebf937&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;f7eaf8e3-9f3e-421e-88f5-c3fa4c32014a&quot;})]; return () =&gt; { __external0.get(); while (true) { __external1.toggle(); break;  };  }; })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:b1g4:b1
- js: Vu|r0:|g3:b1g4:b0
- ref: Vu|r0:|g3:b0g4:b1
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 24 cands 11 accepted 2
round 1 size 17 cands 10 accepted 3
round 2 size 16 cands 9 accepted 3
round 3 size 15 cands 8 accepted 3
round 4 size 14 cands 7 accepted 3
round 5 size 13 cands 6 accepted 3
round 6 size 12 cands 5 accepted 3
round 7 size 11 cands 4 accepted 3
round 8 size 10 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4337 . ../topcoat
```

