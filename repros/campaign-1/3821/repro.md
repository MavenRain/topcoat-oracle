# Campaign repro 5059380:3821

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 28 -> 23
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "a";
let v9: Option<String> = None::<String>;
let v3 = Signal::new(false);
v3.set((if v2.clone().is_empty() { v2.clone() } else { v9.clone().unwrap() }) <= (if v3.get() { v9.clone().unwrap() } else { v2.clone() }))
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;b9ad059c-bd66-40a2-aa26-df3f400c2ccf&quot;}), cx.hydrate(&quot;a&quot;), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null})]; return () =&gt; __external0.set(((() =&gt; { if (__external1.clone().is_empty().dehydrate()) { return __external1.clone(); } else { return __external2.clone().unwrap(); } })()).le(((() =&gt; { if (__external0.get().dehydrate()) { return __external2.clone().unwrap(); } else { return __external1.clone(); } })()))); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b0
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b0
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b0
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 28 cands 6 accepted 1
round 1 size 27 cands 5 accepted 1
round 2 size 26 cands 4 accepted 1
round 3 size 25 cands 3 accepted 1
round 4 size 24 cands 2 accepted 1
round 5 size 23 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3821 . ../topcoat
```

