# Campaign repro 5059380:488

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 40 -> 15
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Err(0.5);
let v3 = Signal::new(true);
let v4 = Signal::new(true);
if v7.clone().unwrap().is_empty() { if v4.get() { } else { v3.toggle(); } }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:0.5}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;de76db69-c95c-4e42-bc56-466b2a2722a2&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;74c48514-e79d-419b-8331-77f4d0c6ed55&quot;})]; return () =&gt; (() =&gt; { if (__external0.clone().unwrap().is_empty().dehydrate()) { return (() =&gt; { if (__external1.get().dehydrate()) {  } else { __external2.toggle();  } })(); } })(); })()
```

## Witness

- rust: Punwrap:48:called `Result::unwrap()` on an `Err` value: 0.5|r0:|g3:b1g4:b1
- js: Pother:47:called `Result.unwrap()` on an `Err` value: 0.5|r0:|g3:b1g4:b1
- ref: Punwrap:48:called `Result::unwrap()` on an `Err` value: 0.5|r0:|g3:b1g4:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 40 cands 25 accepted 3
round 1 size 39 cands 23 accepted 5
round 2 size 28 cands 18 accepted 7
round 3 size 25 cands 17 accepted 8
round 4 size 23 cands 16 accepted 8
round 5 size 21 cands 15 accepted 9
round 6 size 20 cands 14 accepted 9
round 7 size 19 cands 13 accepted 9
round 8 size 18 cands 12 accepted 9
round 9 size 17 cands 11 accepted 9
round 10 size 16 cands 10 accepted 9
round 11 size 15 cands 9 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 488 . ../topcoat
```

