# Campaign repro 5059380:2716

- topcoat: 51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a
- topcoat-oracle: 75ed4c50a686aca1e26427c582d5e0813cdc782c
- plant: none
- verdict: diverge:message:odd:js
- original mode: read_only
- final mode: read_only
- size: 14 -> 8
- stop: fixpoint

This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.
Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.

## Program

```rust
let v9: Option<String> = None::<String>;
let v3 = Signal::new("hello");
v9.clone().unwrap() >= v3.get()
```

## Emitted JS

- form: closure

```js
(() => { const [__external0, __external1] = [cx.hydrate({&quot;t&quot;:&quot;Option&quot;,&quot;v&quot;:null}), cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;096f4564-22cd-4639-b557-24c2fe2776c9&quot;})]; return () =&gt; __external0.clone().unwrap().ge(__external1.get()); })()
```

## Witness

- rust: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5:hello
- js: Pother:42:called `Option.unwrap()` on a `None` value|r0:|g3:s5:hello
- ref: Punwrap:43:called `Option::unwrap()` on a `None` value|r0:|g3:s5:hello
- verdict: diverge:message:odd:js

## Walk

```text
round 0 size 14 cands 7 accepted 1
round 1 size 13 cands 6 accepted 1
round 2 size 12 cands 5 accepted 1
round 3 size 11 cands 4 accepted 1
round 4 size 10 cands 3 accepted 1
round 5 size 9 cands 2 accepted 1
round 6 size 8 cands 1 accepted none
```

## Reproduce

From the oracle repository root, with the campaign archive unpacked at '_emit/m34/check/archive':

```sh
dune exec bin/m35.exe -- emit '_emit/m34/check/archive' 2716 . ../topcoat
```

