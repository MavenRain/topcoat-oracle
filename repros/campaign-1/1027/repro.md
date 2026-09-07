# Campaign repro 5059380:1027

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 48 -> 27
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v7: Result<String, f64> = Err(1e300);
let v9: Option<String> = Some("a\"b");
let v3 = Signal::new(false);
let v4 = Signal::new(false);
{ { let v11 = 1e300; if v7.clone().unwrap().is_empty() { v9.clone().unwrap(); v4.set(!false); } else { v3.set(!v4.get()) }; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:1e+300}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:&quot;a\&quot;b&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;c8ccf27e-9bb5-4557-a309-ac1fe5963230&quot;}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;d93d0d17-85ac-4caa-98a3-4f3469ba13e7&quot;})]; return () =&gt; { (() =&gt; { let __local0 = cx.hydrate(1e+300); (() =&gt; { if (__external0.clone().unwrap().is_empty().dehydrate()) { __external1.clone().unwrap(); __external2.set(cx.hydrate(false).not());  } else { return __external3.set(__external2.get().not()); } })();  })();  }; })()
```

## Witness

- rust: Punwrap:50:called `Result::unwrap()` on an `Err` value: 1e300|r0:|g3:b0g4:b0
- js: Pother:345:called `Result.unwrap()` on an `Err` value: 1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000|r0:|g3:b0g4:b0
- ref: Punwrap:50:called `Result::unwrap()` on an `Err` value: 1e300|r0:|g3:b0g4:b0
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 48 cands 6 accepted 1
round 1 size 35 cands 7 accepted 1
round 2 size 32 cands 7 accepted 2
round 3 size 31 cands 6 accepted 2
round 4 size 30 cands 5 accepted 2
round 5 size 29 cands 4 accepted 2
round 6 size 28 cands 3 accepted 2
round 7 size 27 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1027 . ../topcoat
```

