# Campaign repro 5059380:3252

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 13 -> 6
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(-1.0);
let v4 = Signal::new(-8.172245148113306e249);
v4.set(v3.get())
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;ce304ae2-3696-4fa2-8d25-b0faf8a0082d&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;41e48e10-2333-4411-b194-674ecf3504ef&quot;})]; return () =&gt; __external0.set(__external1.get()); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f3220176896:0;g4:f4090643264:1111909803;
- js: Vu|r0:|g3:f4090643264:1111909803;g4:f4090643264:1111909803;
- ref: Vu|r0:|g3:f3220176896:0;g4:f3220176896:0;
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 13 cands 8 accepted 1
round 1 size 12 cands 7 accepted 1
round 2 size 11 cands 6 accepted 1
round 3 size 10 cands 5 accepted 1
round 4 size 9 cands 4 accepted 1
round 5 size 8 cands 3 accepted 1
round 6 size 7 cands 2 accepted 1
round 7 size 6 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3252 . ../topcoat
```

