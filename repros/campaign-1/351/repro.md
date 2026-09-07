# Campaign repro 5059380:351

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 20 -> 15
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v1: bool = false;
let v2: String = "line\nbreak";
let v3 = Signal::new(true);
v3.set(v2.clone().contains("abc").then_some(v1).unwrap())
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;720297ef-d582-4881-b8b6-6c5bea80cc66&quot;}), cx.hydrate(&quot;line\nbreak&quot;), cx.hydrate(false)]; return () =&gt; __external0.set(__external1.clone().contains(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;abc&quot;})).then_some(__external2).unwrap()); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b1
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 20 cands 6 accepted 1
round 1 size 19 cands 5 accepted 1
round 2 size 18 cands 4 accepted 1
round 3 size 17 cands 3 accepted 1
round 4 size 16 cands 2 accepted 1
round 5 size 15 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 351 . ../topcoat
```

