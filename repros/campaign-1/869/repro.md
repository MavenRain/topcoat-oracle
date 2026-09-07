# Campaign repro 5059380:869

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 20 -> 11
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "tab\t";
let v3 = Signal::new("iQO1");
{ false.then_some({ }).unwrap(); v3.set(v2.clone()); }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;2ce0efa4-3099-4128-987c-78fa13a28724&quot;}), cx.hydrate(&quot;tab\t&quot;)]; return () =&gt; { cx.hydrate(false).then_some((() =&gt; {  })()).unwrap(); __external0.set(__external1.clone());  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s4:iQO1
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s4:iQO1
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s4:iQO1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 20 cands 10 accepted 2
round 1 size 17 cands 9 accepted 3
round 2 size 16 cands 8 accepted 3
round 3 size 15 cands 7 accepted 3
round 4 size 14 cands 6 accepted 3
round 5 size 13 cands 5 accepted 3
round 6 size 12 cands 4 accepted 3
round 7 size 11 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 869 . ../topcoat
```

