# Campaign repro 5059380:310

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 34 -> 25
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Err(0.1);
let v9: Option<String> = Some(" pad ");
let v3 = Signal::new(false);
if v9.clone().is_some() { ({ v7.clone().unwrap(); false.then_some({ }) }).expect(" lead") } else { v3.set(v3.get()) }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:&quot; pad &quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:0.1}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;c22200d2-403a-485b-a41b-ec2073a2d6b5&quot;})]; return () =&gt; (() =&gt; { if (__external0.clone().is_some().dehydrate()) { return ((() =&gt; { __external1.clone().unwrap(); return cx.hydrate(false).then_some((() =&gt; {  })()); })()).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot; lead&quot;})); } else { return __external2.set(__external2.get()); } })(); })()
```

## Witness

- rust: Punwrap:48:called `Result::unwrap()` on an `Err` value: 0.1|r0:|g3:b0
- js: Pexpect:47:called `Result.unwrap()` on an `Err` value: 0.1|r0:|g3:b0
- ref: Punwrap:48:called `Result::unwrap()` on an `Err` value: 0.1|r0:|g3:b0
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 34 cands 14 accepted 4
round 1 size 30 cands 11 accepted 6
round 2 size 29 cands 10 accepted 6
round 3 size 28 cands 9 accepted 6
round 4 size 27 cands 8 accepted 6
round 5 size 26 cands 7 accepted 6
round 6 size 25 cands 6 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 310 . ../topcoat
```

