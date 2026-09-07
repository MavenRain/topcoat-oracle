# Campaign repro 5059380:3694

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 62 -> 58
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v2: String = "😀";
let v7: Result<String, f64> = Err(-2.8955392755619077e92);
let v9: Option<String> = None::<String>;
let v3 = Signal::new("hello");
v3.set(if (if ({ let v10 = v3.get(); { true != false; { }; !false } }) { v9.clone().unwrap().is_empty() } else { false }) { let v11 = if v2.clone().ends_with(" lead") { if true { false.then_some(v7.clone()).expect("") } else if false { v7.clone() } else { v7.clone() } } else { v7.clone() }; v2.clone() } else { v2.clone() })
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1, __external2, __external3] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;bbed1ea9-4274-4d50-a7af-05da72efdcdd&quot;}), cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate(&quot;😀&quot;), cx.hydrate({&quot;t&quot;:&quot;Result&quot;,&quot;err&quot;:-2.8955392755619077e+92})]; return () =&gt; __external0.set((() =&gt; { if (((() =&gt; { if (((() =&gt; { let __local0 = __external0.get(); return (() =&gt; { cx.hydrate(true).ne(cx.hydrate(false)); (() =&gt; {  })(); return cx.hydrate(false).not(); })(); })()).dehydrate()) { return __external1.clone().unwrap().is_empty(); } else { return cx.hydrate(false); } })()).dehydrate()) { let __local1 = (() =&gt; { if (__external2.clone().ends_with(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot; lead&quot;})).dehydrate()) { return (() =&gt; { if (cx.hydrate(true).dehydrate()) { return cx.hydrate(false).then_some(__external3.clone()).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;&quot;})); } else { if (cx.hydrate(false).dehydrate()) { return __external3.clone(); } else { return __external3.clone(); } } })(); } else { return __external3.clone(); } })(); return __external2.clone(); } else { return __external2.clone(); } })()); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5:hello
- js: Pexpect:42:called `Option.unwrap()` on a `None` value|r0:|g3:s5:hello
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5:hello
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 62 cands 5 accepted 1
round 1 size 61 cands 4 accepted 1
round 2 size 60 cands 3 accepted 1
round 3 size 59 cands 2 accepted 1
round 4 size 58 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 3694 . ../topcoat
```

