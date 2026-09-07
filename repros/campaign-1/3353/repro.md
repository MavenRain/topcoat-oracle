# Campaign repro 5059380:3353

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 18 -> 12
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "hello";
let v3 = Signal::new(false);
let v4 = Signal::new("yoA4");
v4.push_str(if v3.get() { v4.get() } else { v2.clone() })
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;702e573e-fd62-430f-9d68-a2bef2e1a30b&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;e7a7092c-dd8a-45a5-a17d-2f25e1718f27&quot;}), cx.hydrate(&quot;hello&quot;)]; return () =&gt; __external0.push_str((() =&gt; { if (__external1.get().dehydrate()) { return __external0.get(); } else { return __external2.clone(); } })()); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:b0g4:s4:yoA4
- js: Vu|r0:|g3:s10:falsefalseg4:s4:yoA4
- ref: Vu|r0:|g3:b0g4:s9:yoA4hello
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 18 cands 7 accepted 1
round 1 size 17 cands 6 accepted 1
round 2 size 16 cands 5 accepted 1
round 3 size 15 cands 4 accepted 1
round 4 size 14 cands 3 accepted 1
round 5 size 13 cands 2 accepted 1
round 6 size 12 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3353 . ../topcoat
```

