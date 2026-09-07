# Campaign repro 5059380:1583

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:class:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 80 -> 54
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v6: Result<f64, String> = Err("line\nbreak");
let v3 = Signal::new("😀");
if false { v3.set(v6.clone().expect_err("quote\"and\\back")) } else { (if v1 { if true { false.then_some({ }) } else { false.then_some({ }) } } else if false { false.then_some({ }) } else { false.then_some({ }) }).expect("  both  ") }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;e4020767-f8ba-4b6b-9485-1976780aea4b&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:&quot;line\nbreak&quot;}), cx.hydrate(false)]; return () =&gt; (() =&gt; { if (cx.hydrate(false).dehydrate()) { return __external0.set(__external1.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;quote\&quot;and\\back&quot;}))); } else { return ((() =&gt; { if (__external2.dehydrate()) { return (() =&gt; { if (cx.hydrate(true).dehydrate()) { return cx.hydrate(false).then_some((() =&gt; {  })()); } else { return cx.hydrate(false).then_some((() =&gt; {  })()); } })(); } else { if (cx.hydrate(false).dehydrate()) { return cx.hydrate(false).then_some((() =&gt; {  })()); } else { return cx.hydrate(false).then_some((() =&gt; {  })()); } } })()).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;  both  &quot;})); } })(); })()
```

## Witness

- rust: Pother:8:  both  |r0:|g3:s4:😀
- js: Pother:8:  both  |r0:|g3:s4:😀
- ref: Pexpect:8:  both  |r0:|g3:s4:😀
- verdict: diverge:class:two_way

## Walk

```text
round 0 size 80 cands 22 accepted 3
round 1 size 59 cands 10 accepted 5
round 2 size 58 cands 9 accepted 5
round 3 size 57 cands 8 accepted 5
round 4 size 56 cands 7 accepted 5
round 5 size 55 cands 6 accepted 5
round 6 size 54 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1583 . ../topcoat
```

