# Campaign repro 5059380:3415

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 21 -> 16
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "tab\t";
let v8: Option<f64> = Some(0.5);
let v3 = Signal::new("a\"b");
let v4 = Signal::new(" pad ");
v4.push_str({ let v10 = v8.clone(); v3.set(v2.clone()); v4.get() })
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;6c88613f-78d9-4a79-a7f0-07d96f068531&quot;}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:0.5}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;55be8fea-10f8-47a9-8bab-e935f4441331&quot;}), cx.hydrate(&quot;tab\t&quot;)]; return () =&gt; __external0.push_str((() =&gt; { let __local0 = __external1.clone(); __external2.set(__external3.clone()); return __external0.get(); })()); })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:s3:a"bg4:s5: pad 
- js: Vu|r0:|g3:s6:a"ba"bg4:s4:tab	
- ref: Vu|r0:|g3:s4:tab	g4:s10: pad  pad 
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 21 cands 6 accepted 1
round 1 size 20 cands 5 accepted 1
round 2 size 19 cands 4 accepted 1
round 3 size 18 cands 3 accepted 1
round 4 size 17 cands 2 accepted 1
round 5 size 16 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3415 . ../topcoat
```

