# Campaign repro 5059380:1614

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 27 -> 22
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v2: String = "😀";
let v3 = Signal::new("");
{ { while (!false) { v1; if true { false } else { false }; { { }; v3.set(v2.clone()); }; continue; }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate(false), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;47f2daec-1b8a-4a2c-b77b-42dd0cbd887e&quot;}), cx.hydrate(&quot;😀&quot;)]; return () =&gt; { (() =&gt; { while ((cx.hydrate(false).not()).dehydrate()) { __external0; (() =&gt; { if (cx.hydrate(true).dehydrate()) { return cx.hydrate(false); } else { return cx.hydrate(false); } })(); (() =&gt; { (() =&gt; {  })(); __external1.set(__external2.clone());  })(); continue;  };  })();  }; })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:s0:
- js: T|r0:|
- ref: T|r0:|g3:s4:😀
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 27 cands 7 accepted 2
round 1 size 26 cands 6 accepted 2
round 2 size 25 cands 5 accepted 2
round 3 size 24 cands 4 accepted 2
round 4 size 23 cands 3 accepted 2
round 5 size 22 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1614 . ../topcoat
```

