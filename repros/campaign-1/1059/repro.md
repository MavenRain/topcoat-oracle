# Campaign repro 5059380:1059

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:two_way
- original mode: signal_writing
- final mode: signal_writing
- size: 21 -> 12
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v9: Option<String> = None::<String>;
let v3 = Signal::new(true);
{ let v11 = v9.clone().unwrap(); { v3.set(true); }; }
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;fb442ce2-f73e-4c0a-8f74-56f445720d88&quot;})]; return () =&gt; { let __local0 = __external0.clone().unwrap(); (() =&gt; { __external1.set(cx.hydrate(true));  })();  }; })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:b1
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:b1
- verdict: diverge:message:two_way

## Walk

```text
round 0 size 21 cands 9 accepted 1
round 1 size 18 cands 9 accepted 3
round 2 size 17 cands 8 accepted 3
round 3 size 16 cands 7 accepted 3
round 4 size 15 cands 6 accepted 3
round 5 size 14 cands 5 accepted 3
round 6 size 13 cands 4 accepted 3
round 7 size 12 cands 3 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 1059 . ../topcoat
```

