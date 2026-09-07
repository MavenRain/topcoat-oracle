# Campaign repro 5059380:4254

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 71 -> 23
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "tab\t";
let v3 = Signal::new(0.5);
let v4 = Signal::new(-2.930558588739928e78);
if false.then_some(false).unwrap() { } else { v4.set(if v2.clone().contains("abc") { 1e16 } else { v3.get() }) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;c8126433-2e03-41d7-895c-eceef05a1351&quot;}), cx.hydrate(&quot;tab\t&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;c4302f44-0061-4015-a21c-c5e06e4a34a0&quot;})]; return () =&gt; (() =&gt; { if (cx.hydrate(false).then_some(cx.hydrate(false)).unwrap().dehydrate()) {  } else { return __external0.set((() =&gt; { if (__external1.clone().contains(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;abc&quot;})).dehydrate()) { return cx.hydrate(1e+16); } else { return __external2.get(); } })()); } })(); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1071644672:0;g4:f3493416717:1637812791;
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:f1071644672:0;g4:f3493416717:1637812791;
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:f1071644672:0;g4:f3493416717:1637812791;
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 71 cands 26 accepted 4
round 1 size 61 cands 19 accepted 5
round 2 size 54 cands 14 accepted 4
round 3 size 29 cands 11 accepted 5
round 4 size 28 cands 10 accepted 5
round 5 size 27 cands 9 accepted 5
round 6 size 26 cands 8 accepted 5
round 7 size 25 cands 7 accepted 5
round 8 size 24 cands 6 accepted 5
round 9 size 23 cands 5 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4254 . ../topcoat
```

