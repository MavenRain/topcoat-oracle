# Campaign repro 5059380:3099

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 54 -> 47
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v0: f64 = 3.0;
let v1: bool = true;
let v6: Result<f64, String> = Err("a\"b");
let v3 = Signal::new(5e-324);
let v4 = Signal::new(true);
{ if v4.get() { if v6.clone().is_ok() { if v4.get() { v3.get() } else { v3.get() } } else if false { if v4.get() { v0 } else { (100.0) - (3.0) } } else { v3.get() } } else { v0 }; v4.set(if (if v1 { v4.get() } else { v4.get() }) { true } else { true }); }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;64cbc1a0-38fe-4c16-8470-35a3192f2eb1&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:&quot;a\&quot;b&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;02ead490-de17-45e7-9827-ff0021100823&quot;}), cx.hydrate(3.0), cx.hydrate(true)]; return () =&gt; { (() =&gt; { if (__external0.get().dehydrate()) { return (() =&gt; { if (__external1.clone().is_ok().dehydrate()) { return (() =&gt; { if (__external0.get().dehydrate()) { return __external2.get(); } else { return __external2.get(); } })(); } else { if (cx.hydrate(false).dehydrate()) { return (() =&gt; { if (__external0.get().dehydrate()) { return __external3; } else { return (cx.hydrate(100.0)).sub((cx.hydrate(3.0))); } })(); } else { return __external2.get(); } } })(); } else { return __external3; } })(); __external0.set((() =&gt; { if (((() =&gt; { if (__external4.dehydrate()) { return __external0.get(); } else { return __external0.get(); } })()).dehydrate()) { return cx.hydrate(true); } else { return cx.hydrate(true); } })());  }; })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:f0:1;g4:b1
- js: Vu|r0:|g3:b1g4:b1
- ref: Vu|r0:|g3:f0:1;g4:b1
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 54 cands 7 accepted 1
round 1 size 51 cands 7 accepted 3
round 2 size 50 cands 6 accepted 3
round 3 size 49 cands 5 accepted 3
round 4 size 48 cands 4 accepted 3
round 5 size 47 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3099 . ../topcoat
```

