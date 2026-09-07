# Campaign repro 5059380:3922

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 65 -> 20
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(true);
{ if v3.get() { false.then_some({ }).unwrap() } else if v3.get() { if v3.get() { } else { v3.toggle() } } else { v3.toggle() }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;0715b691-c28b-4e0a-babd-2b3992607f42&quot;})]; return () =&gt; { (() =&gt; { if (__external0.get().dehydrate()) { return cx.hydrate(false).then_some((() =&gt; {  })()).unwrap(); } else { if (__external0.get().dehydrate()) { return (() =&gt; { if (__external0.get().dehydrate()) {  } else { return __external0.toggle(); } })(); } else { return __external0.toggle(); } } })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b1
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 65 cands 8 accepted 2
round 1 size 43 cands 9 accepted 2
round 2 size 27 cands 9 accepted 2
round 3 size 26 cands 8 accepted 2
round 4 size 25 cands 7 accepted 2
round 5 size 24 cands 6 accepted 2
round 6 size 23 cands 5 accepted 2
round 7 size 22 cands 4 accepted 2
round 8 size 21 cands 3 accepted 2
round 9 size 20 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3922 . ../topcoat
```

