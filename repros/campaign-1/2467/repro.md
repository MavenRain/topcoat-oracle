# Campaign repro 5059380:2467

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 26 -> 14
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "a\"b";
let v3 = Signal::new("a\"b");
{ { let v11 = false.then_some({ }).unwrap(); { }; v3.set(v2.clone()); }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;4d6e8e8e-6eca-4f6b-8fb8-4167f5778c5d&quot;}), cx.hydrate(&quot;a\&quot;b&quot;)]; return () =&gt; { (() =&gt; { let __local0 = cx.hydrate(false).then_some((() =&gt; {  })()).unwrap(); (() =&gt; {  })(); __external0.set(__external1.clone());  })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s3:a"b
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s3:a"b
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s3:a"b
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 26 cands 8 accepted 1
round 1 size 20 cands 8 accepted 2
round 2 size 19 cands 7 accepted 2
round 3 size 18 cands 6 accepted 2
round 4 size 17 cands 5 accepted 2
round 5 size 16 cands 4 accepted 2
round 6 size 15 cands 3 accepted 2
round 7 size 14 cands 2 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2467 . ../topcoat
```

