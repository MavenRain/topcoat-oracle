# Campaign repro 5059380:2831

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:signals:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 50 -> 47
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v0: f64 = 7.862752394096765e-298;
let v2: String = "hello";
let v6: Result<f64, String> = Ok(1e16);
let v7: Result<String, f64> = Err(1.5);
let v3 = Signal::new("a\\b");
let v4 = Signal::new("hello");
{ if (v0 < v6.clone().unwrap()) { v4.get().ends_with("  both  ") } else { v7.clone().is_err() }; while (if ({ v2.clone() }).is_empty() { false } else { v6.clone().is_ok() }) { loop { v3.set(v4.get()); break; }; break; }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3, __external4, __external5] = [cx.hydrate(7.862752394096765e-298), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;ok&quot;:1e+16}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;b7de626c-c33b-4f49-896c-25e2b2800810&quot;}), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:1.5}), cx.hydrate(&quot;hello&quot;), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;030de78f-b966-4fae-9817-ba8218c53efd&quot;})]; return () =&gt; { (() =&gt; { if ((__external0.lt(__external1.clone().unwrap())).dehydrate()) { return __external2.get().ends_with(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;  both  &quot;})); } else { return __external3.clone().is_err(); } })(); while (((() =&gt; { if (((() =&gt; { return __external4.clone(); })()).is_empty().dehydrate()) { return cx.hydrate(false); } else { return __external1.clone().is_ok(); } })()).dehydrate()) { while (true) { __external5.set(__external2.get()); break;  }; break;  };  }; })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:s3:a\bg4:s5:hello
- js: Vu|r0:|g3:s3:a\bg4:s3:a\b
- ref: Vu|r0:|g3:s5:hellog4:s5:hello
- verdict: diverge:signals:two_way

## Walk

```text
round 0 size 50 cands 6 accepted 3
round 1 size 49 cands 5 accepted 3
round 2 size 48 cands 4 accepted 3
round 3 size 47 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2831 . ../topcoat
```

