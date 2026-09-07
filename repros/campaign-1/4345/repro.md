# Campaign repro 5059380:4345

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 24 -> 19
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = " pad ";
let v6: Result<f64, String> = Ok(f64::NAN);
let v3 = Signal::new(true);
v3.set(({ v2.clone() }) < v6.clone().expect_err("trail "))
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;b4311992-7200-42dc-ba5d-3f08b750b21f&quot;}), cx.hydrate(&quot; pad &quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:null})]; return () =&gt; __external0.set(((() =&gt; { return __external1.clone(); })()).lt(__external2.clone().expect_err(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;trail &quot;})))); })()
```

## Witness

- rust: Pexpect_err:11:trail : NaN|r0:|g3:b1
- js: Pexpect_err:17:trail : undefined|r0:|g3:b1
- ref: Pexpect_err:11:trail : NaN|r0:|g3:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 24 cands 6 accepted 1
round 1 size 23 cands 5 accepted 1
round 2 size 22 cands 4 accepted 1
round 3 size 21 cands 3 accepted 1
round 4 size 20 cands 2 accepted 1
round 5 size 19 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 4345 . ../topcoat
```

