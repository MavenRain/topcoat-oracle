# Campaign repro 5059380:3089

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 52 -> 45
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "a\\b";
let v8: Option<f64> = Some(f64::NAN);
let v3 = Signal::new("a\"b");
{ (if false { v8.clone(); false.then_some({ }) } else { true.then_some({ }) }).unwrap(); { if v2.clone().is_empty() { v3.set(v2.clone()) } else { v3.set(v2.clone()) }; false.then_some(false.then_some({ })).expect("a").expect("a"); v3.set(v3.get()); }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2] = [cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate(&quot;a\\b&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;c2bd1cf3-d27d-4a5d-8065-2640cb55ddb7&quot;})]; return () =&gt; { ((() =&gt; { if (cx.hydrate(false).dehydrate()) { __external0.clone(); return cx.hydrate(false).then_some((() =&gt; {  })()); } else { return cx.hydrate(true).then_some((() =&gt; {  })()); } })()).unwrap(); (() =&gt; { (() =&gt; { if (__external1.clone().is_empty().dehydrate()) { return __external2.set(__external1.clone()); } else { return __external2.set(__external1.clone()); } })(); cx.hydrate(false).then_some(cx.hydrate(false).then_some((() =&gt; {  })())).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;a&quot;})).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;a&quot;})); __external2.set(__external2.get());  })();  }; })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:s3:a"b
- js: Pexpect:42:called `Option.unwrap()` on a `None` value|r0:|g3:s3:a"b
- ref: Pexpect:1:a|r0:|g3:s3:a\b
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 52 cands 9 accepted 1
round 1 size 50 cands 8 accepted 3
round 2 size 49 cands 7 accepted 3
round 3 size 48 cands 6 accepted 3
round 4 size 47 cands 5 accepted 3
round 5 size 46 cands 4 accepted 3
round 6 size 45 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3089 . ../topcoat
```

