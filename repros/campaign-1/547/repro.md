# Campaign repro 5059380:547

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:outcome:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 41 -> 31
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v3 = Signal::new(true);
{ (if ((-1.0) != (5e-324)) { true.then_some({ }) } else { false.then_some({ }) }).expect("hello world"); v3.set(false); }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0] = [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;79253e3c-7b3a-4a22-9631-657b0697ee79&quot;})]; return () =&gt; { ((() =&gt; { if (((cx.hydrate(1.0).neg()).ne((cx.hydrate(5e-324)))).dehydrate()) { return cx.hydrate(true).then_some((() =&gt; {  })()); } else { return cx.hydrate(false).then_some((() =&gt; {  })()); } })()).expect(cx.hydrate({&quot;t&quot;:&quot;str&quot;,&quot;v&quot;:&quot;hello world&quot;})); __external0.set(cx.hydrate(false));  }; })()
```

## Witness

- rust: Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g3:b1
- js: Pexpect:11:hello world|r0:|g3:b1
- ref: Vu|r0:|g3:b0
- verdict: diverge:outcome:two_way

## Walk

```text
round 0 size 41 cands 11 accepted 2
round 1 size 38 cands 10 accepted 3
round 2 size 37 cands 9 accepted 3
round 3 size 36 cands 8 accepted 3
round 4 size 35 cands 7 accepted 3
round 5 size 34 cands 6 accepted 3
round 6 size 33 cands 5 accepted 3
round 7 size 32 cands 4 accepted 3
round 8 size 31 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 547 . ../topcoat
```

