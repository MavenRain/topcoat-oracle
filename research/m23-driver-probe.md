# M23 driver probe: what the Rust leg observes

Pinned notes for the driver harness (`driver-rs/harness.rs`) and the
emitter (`shell/driver.ml`).  Every verdict here was produced by a live
probe crate, `research/probes-rs/m23probe` (untracked, it path-deps the
sibling topcoat clone), replayed without the sccache wrapper so the
diagnostics survive.  Log:
`/Users/oobi/Documents/topcoat-oracle-m23-probe.log`, lines 186-244;
each row cites the `KEY` line that carries it.  Toolchain
`nightly-2026-06-22`, topcoat at the pinned clone.

The probe answers six questions the driver could not answer by reading
the topcoat source: what type the macro hands back, which types render,
what a panic says, what a signal write does on the server, what a
closure call site costs, and which values do not round trip.

## 1.  The evaluated type is the real Rust type (D4)

Twelve `TYPE` lines, printed with `std::any::type_name_of_val` on the
first element of `into_evaluated_and_js()`.

| target ty | body probed | evaluated Rust type | log key |
| --- | --- | --- | --- |
| `T_f64` | `v0 + 1.5` | `f64` | `TYPE f64` |
| `T_bool` | `!v1` | `bool` | `TYPE bool` |
| `T_string` | `v2.clone()` | `alloc::string::String` | `TYPE string` |
| `T_unit` | `if v1 {}` | `()` | `TYPE unit` |
| `T_option T_f64` | `v8.clone()` | `core::option::Option<f64>` | `TYPE option_f64` |
| `T_option T_string` | `v9.clone()` | `Option<String>` | `TYPE option_string` |
| `T_result (T_f64, T_string)` | `v6.clone()` | `Result<f64, String>` | `TYPE result_f64_string` |
| `T_result (T_string, T_f64)` | `v7.clone()` | `Result<String, f64>` | `TYPE result_string_f64` |
| `T_option T_f64` via `then_some` | `v1.then_some(v0)` | `Option<f64>` | `TYPE then_some` |
| signal read | `v3.get()` | `f64` | `TYPE signal_get_f64` |
| signal read | `v5.get()` | `String` | `TYPE signal_get_string` |
| signal read | `v4.get()` | `bool` | `TYPE signal_get_bool` |

`Surrogate::into_real` wraps every non-closure top level, so nothing
surrogate-shaped reaches the observer.  VERDICT: `Observe` is written
against plain `f64`, `bool`, `String`, `Option<..>`, `Result<..>` and
`()`.  There is no `Surrogate` bound and no unwrapping step anywhere in
`harness.rs`.

## 2.  NodeViewParts membership, and what an empty render means

Confirmed by compilation plus the `NVP` lines.  The route is
`topcoat_view::internal::build_sync` + `write_block` +
`NodeViewParts::into_view_parts`, then `View::render(&cx)` with
`Cx::default()`.  `ViewBufferScope` is a `thread_local!`, so no tokio
runtime is needed and one std thread per case is safe.

| type | impl | rendered text for the probe value |
| --- | --- | --- |
| `f64` | YES | `1.5`;  `3.0` renders as `3` |
| `bool` | YES | `true` |
| `String` | YES | `s&lt;q&gt;"z"` |
| `Option<f64>` Some | YES | `1.5` |
| `Option<f64>` None | YES | the EMPTY string |
| `Option<String>` Some | YES | `s` |
| `()` | NO | `impl_tuple!` starts at `T1` (topcoat-view node.rs:233) |
| `Result<_, _>` | NO | no impl in node.rs |

So an empty `rendered_hex` is AMBIGUOUS between "the type has no impl"
and "None renders empty".  It is not a signal to disambiguate at the
byte level: `Driver.renderable` decides it statically from
`Sample.target` and picks `observed_rendered` or `observed_plain`, and
M24 must resolve it the same way.

Escaping is asymmetric and the harness records bytes verbatim.  In the
JS the head is unescaped and the tail escaped, so a closure body's `=>`
appears as `=&gt;`;  a serialised external escapes the double quote to
`&quot;` and the greater-than to `&gt;` but LEAVES the less-than alone.
In the value channel a String escapes less-than and greater-than but
NOT the double quote.  Anything that normalised either channel would
destroy the evidence M25 needs.

## 3.  Panic texts, and why prefix classification is not enough (D5)

Twelve `PANIC` lines, captured live under `catch_unwind` with a silent
hook.  Every payload was a `&str` or a `String`;  the
`<non-string payload>` fallback never fired.

| case | live message | class |
| --- | --- | --- |
| `Option::unwrap` on `None` | ``called `Option::unwrap()` on a `None` value`` | unwrap |
| `Option::expect("gone")` on `None` | `gone` | expect |
| `Result::unwrap` on `Err("bad")` | ``called `Result::unwrap()` on an `Err` value: "bad"`` | unwrap |
| `Result::expect("boom")` on `Err("bad")` | `boom: "bad"` | expect |
| `Result::unwrap_err` on `Ok("ok")` | ``called `Result::unwrap_err()` on an `Ok` value: "ok"`` | unwrap_err |
| `Result::expect_err("nope")` on `Ok("ok")` | `nope: "ok"` | expect_err |
| `Signal::set` | `expressions in which a signal is written to cannot be run server-side` | signal_write |
| `Signal::toggle` | the same text | signal_write |
| `Signal::increment` | the same text | signal_write |
| `Signal::decrement` | the same text | signal_write |
| `Signal::push_str` | the same text | signal_write |
| control, `v0 + 1.5` | `<NO PANIC>` | not a panic |

This REFUTES message-prefix classification for the `expect` family.
`Option::expect(m)` panics with exactly `m`, so it is indistinguishable
from any other user panic by text alone, and `expect_err(m)` panics
with `m: {err:?}`, which a user message containing a colon also
matches.  The classifier therefore reads the text FIRST, for the three
fixed prefixes and the signal sentence, and falls back to a STATIC hint
the emitter baked into the case function from the body AST
(`Driver.hint_of`).  The hint travels on every JSONL line, so the gate
can tell a genuine classifier gap (`other` with no hint) from the one
case the text cannot resolve (`other` on a body carrying both `expect`
and `expect_err`).

## 4.  Every signal write panics server-side

All five writers (`set`, `toggle`, `increment`, `decrement`,
`push_str`) reach `write_in_browser_only` and panic with the one fixed
sentence (topcoat-runtime
crates/topcoat-runtime/src/surrogate/signal.rs:50, 62, 74, 84, 101,
with the message at 108).  So at this pin a
`Signal_writing` sample observes a panic and never a written value, and
the signal channel of a written signal always reports the INITIAL
value.

That is a pin, not a law.  M36 must re-probe it when the browser leg
lands: if a future topcoat lets a write run server-side, the value
channel of these cases changes and the seed table's case 7 changes with
it.

## 5.  `Signal<T>` has no `Clone`, so each call site mints its own

`Signal<T>` derives `Debug` only
(topcoat-runtime crates/topcoat-runtime/src/signal.rs:35-39, a
different file from the surrogate `signal.rs` cited in section 4).  A
handle cannot be
cloned before the macro, and the macro consumes what it captures, so
two `expr!` sites in one case function cannot share a handle.  The
emitter keeps a plain-local MIRROR of the initial value and each site
does `Signal::new(vID_init.clone())`.

`SIG read_before_macro | 2.5` proves a signal can also be read outside
the macro through
`Surrogate::into_real(Surrogated::into_surrogate(&v3).get())`, and
`SIG get_inside_macro | 2.5` proves the in-macro read agrees.  Both
routes are sound for the same reason as section 4: no server-side write
ever changes the stored value.  The mirror route wins because it needs
no surrogate vocabulary in the harness.

## 6.  The closure call site needs `move` (E0597)

A bare `expr!(|| BODY)` DOES NOT COMPILE.  Three
`error[E0597]: __topcoat_external0 does not live long enough` at log
lines 139, 150 and 161: the macro binds the surrogates in an inner
block and a non-`move` closure borrows them, so the `Expr` cannot leave
that block.  `expr!(move || BODY)` compiles and runs.

The closure call site exists because a panicking body loses its JS to
the unwind:  `Surrogate::into_real` is skipped for a closure top level
(grammar expr.rs:60-62), so the Rust half is a closure value that is
never called while the JS is still captured.  The wrapper is visible in
the bytes, and it is the ONLY difference:

```
CLS bare_js    | (() => { const [__external0] = [cx.hydrate(1.5)]; return __external0.add(cx.hydrate(1.5)); })()
CLS closure_js | (() => { const [__external0] = [cx.hydrate(1.5)]; return () =&gt; __external0.add(cx.hydrate(1.5)); })()
```

so the harness checks CONTAINMENT of the direct body inside the closure
JS, never equality, and exits 4 when the body is lost.  The corpus
shape the JS leg will actually receive is `|_e| BODY`, not `move ||
BODY`;  M25 decides whether the driver switches to it.

Containment on the whole body is not enough, and the drawn batch proved
it: three of 300 cases (162, 177, 182) exited 4 on the first run of the
finished gate.  All three have a BLOCK top level, and a block is
lowered twice with two different wrappers.  In the direct form the
block sits in expression position, so it becomes an immediately invoked
arrow;  in the closure form the same block IS the arrow's body, so the
invoking wrapper is gone.  Case 162, both texts trimmed to the shared
part:

```
direct body  | (() =&gt; { __external0.clone(); ..;  })()
closure text | ..; return () =&gt; { __external0.clone(); ..;  }; })()
```

The braces and every byte between them are identical;  only
`(() =&gt; ` .. `)()` against `() =&gt; ` differs.  So the body check
accepts two agreements: the closure JS carries the whole direct body,
or it carries that body's CORE, the body with one `(() =&gt; ` .. `)()`
wrapper peeled off (`js_core`).  Exit 4 still fires when neither holds.
The 23 other batch cases that carry a signal external in the body agree
on the WHOLE body, which is the control: a fresh UUID per site does not
break containment, because the UUID sits in the const head of the site
and never in the body.

The peel is guarded.  `(() =&gt; { A; })() + (() =&gt; { Z; })()`
strips to `{ A; })() + (() =&gt; { Z; }`, whose brace depth falls back
to zero in the middle, and a closure carrying both blocks contains
exactly that text, so an unguarded peel would call two different
programs consistent.  `js_core` therefore peels only when what is left
is ONE brace-balanced run: depth above zero at every byte before the
last, and exactly zero after it.  Braces inside a JS string literal can
only make the guard refuse to peel, which costs a loud exit 4 and never
a silent pass.  Replayed over the 298 JS lines of the regenerated a2
batch, all 64 block-shaped bodies still peel and none is refused.

## 6b.  The wire form of a site with ZERO externals

A site with at least one external renders as
`(() => { const [..] = [..]; return <body>; })()`.  A site with NO
external has no const head to introduce, so it carries neither marker
and the whole render IS the body.  54 of the 298 JS lines of the
regenerated a2 batch have that shape:

```
case 6  | cx.hydrate(1.2345678901234568e+17)
case 7  | cx.hydrate(true)
case 22 | (() =&gt; {  })()
```

So `js_body` reads the whole text when NEITHER marker is present,
slices when BOTH are, and fails CLOSED on every other combination, on
non-UTF-8 bytes and on an empty body slice.  It used to answer "no
marker, so agree", which turned any wire drift into a silent pass.  One
line of the batch is already in the half-present class: case 64, whose
closure text is
`() =&gt; ((() =&gt; { return cx.hydrate(false)...; })()).unwrap()`,
carries `; })()` and no `; return `, because the inner block spells its
return without the leading semicolon.  That line is a CLOSURE render,
which the body check never slices, but it is the proof that the
half-present class is reachable.

Open item for M24 or later: the head is the FIRST `; return `, so a
String external whose own bytes contain `; return ` mis-slices.
`rfind` is wrong too, because a block body lowers to an IIFE that
carries its own `; return `.  Only a quote-aware scan fixes it, and a
drawn string has not hit it yet;  the failure mode meanwhile is a loud
exit 4, never a silent pass.

## 7.  Value round trips, and two divergences that are NOT the driver's

| input | `to_bits()` after `expr!(v0)` | JS | log key |
| --- | --- | --- | --- |
| `f64::from_bits(0x7ff8000000000001u64)` | `7ff8000000000001` | `cx.hydrate(null)` | `RT f64_nan_*` |
| `f64::from_bits(0xc0f8000000000000u64)` | `c0f8000000000000`, prints `-98304` | `cx.hydrate(-98304.0)` | `RT f64_neg_*` |
| `f64::from_bits(0x0000000000000001u64)` | `0000000000000001`, prints `5e-324` | not printed | `RT f64_subnormal_bits` |
| `String::from("a\"b\\c\nd\u{e9}\u{1f600}")` | hex `6122625c630a64c3a9f09f9880` | escaped | `RT str_*` |
| `String::from("")` | empty hex, length 0 | not printed | `RT str_empty_hex` |

Both init forms round trip bit exact and byte exact, which is why
`Driver.init_rust` emits `f64::from_bits(..)` and
`String::from("..")` rather than decimal or bare literals.

Two divergences fall out for free.  They belong to M25, and the driver
must NOT paper over either:

1. NaN serialises into the JS as `null`.  The Rust value keeps its
   payload bits, the JS value has no NaN at all, so a leg comparison on
   any NaN-producing body needs a decision rather than a byte compare.
2. An f64 whose value is integral renders as `3` in the value channel
   and as `-98304.0` in the JS.  The two channels disagree on the text
   of the same number by design, so the JS leg cannot be compared with
   the rendered channel as strings.

## 8.  A fresh UUID per run, and what the gate does about it

```
CLS closure_signal_write_js | ... [cx.hydrate({&quot;t&quot;:&quot;Signal&quot;,&quot;id&quot;:&quot;d811dd39-8f57-4195-9866-5e5663d93e21&quot;})]; ...
```

Every `Signal::new` mints a new id and serialises it into the JS, so
the JS bytes of any case with a signal external differ on EVERY run,
and so does the `Debug` text of the handle.  The harness still records
the bytes verbatim.  `m23_verdict.sh` masks `js_hex` and `debug_hex`
before comparing the seed lines and checks the JS channel by one
decoded substring per case instead;  M24 and M25 need the same
discipline before any cross-run comparison.
