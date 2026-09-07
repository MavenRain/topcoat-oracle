# Campaign repro 5059380:1556

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 18 -> 13
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "line\nbreak";
let v9: Option<String> = None::<String>;
let v3 = Signal::new(" pad ");
v3.set(if true { v9.clone().unwrap() } else { v2.clone() })
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;d8298436-1b3e-4f9b-8913-2e5479415609&quot;}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate(&quot;line\nbreak&quot;)]; return () =&gt; __external0.set((() =&gt; { if (cx.hydrate(true).dehydrate()) { return __external1.clone().unwrap(); } else { return __external2.clone(); } })()); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5: pad 
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s5: pad 
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5: pad 
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 18 cands 6 accepted 1
round 1 size 17 cands 5 accepted 1
round 2 size 16 cands 4 accepted 1
round 3 size 15 cands 3 accepted 1
round 4 size 14 cands 2 accepted 1
round 5 size 13 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1556 . ../topcoat
```

