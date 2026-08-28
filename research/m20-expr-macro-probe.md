# M20: expr! macro probe adjudication

Date: 2026-08-27
topcoat pin: 51caa01d (path deps at ../../../../topcoat/crates)
Probe crate: research/probes-rs/exprmac (30 probe fns a1..h2; e4/f4 unused ids)
rustc: 1.98.0-nightly (91fe22da8 2026-06-21) via `+nightly-2026-06-22`
Command (cwd = repo root, via runner script):

```
gateledger run -- cargo +nightly-2026-06-22 check \
  --manifest-path research/probes-rs/exprmac/Cargo.toml \
  -j 2 --message-format=short
```

Exit: nonzero (29 errors), full log at ~/Documents/topcoat-oracle-m20-check.txt.

Toolchain note (not a crate repair): the topcoat crates carry
`rust-version = 1.98`; the cwd-resolved default toolchain is
1.96.0-nightly, so the first run died in the resolver ("rustc
1.96.0-nightly is not supported by the following packages ... requires
rustc 1.98") before rustc ran. `+nightly-2026-06-22` (= 1.98.0-nightly)
satisfies it. No Cargo.toml, import, or probe-body changes were needed:
dep paths resolved, `topcoat_runtime::Signal`,
`topcoat_runtime_macro::expr`, and `topcoat_runtime::Expr` all exist
(expr.rs:5 `pub struct Expr<T>`; the expansion returns
`topcoat_runtime::Expr::new(#rust, __js_view)`), so c6's annotation
stands as written.

## Verdict table

Every one of the 29 error lines maps to a probe; a probe with no error
lines is PASS.

| id | EXPECT | ACTUAL | MATCH |
|---|---|---|---|
| a1_arith | pass | pass | y |
| a2_literals | pass | pass | y |
| a3_cmp | pass | pass | y |
| a4_unary | pass | pass | y |
| b1_methods | pass | FAIL: E0597 (trim's StrSurrogate borrows macro temp `__topcoat_external0`) + 3x E0382 (each expr! moves `v2`; uses 2-4 see a moved value) | n |
| b2_literal_recv | pass | pass | y |
| c1_none_turbofish | pass | FAIL: E0433 `topcoat_runtime::Option` does not exist at pin | n |
| c2_some | pass | FAIL: E0433 same missing `Option` path | n |
| c3_option_methods | pass | pass (is_some/unwrap/expect all clean, no moves) | y |
| c4_result_methods | pass | FAIL: 3x E0382 (`v6` moved by first expr!; uses 2-4 reject) | n |
| c5_ok_unpinned | FAIL E0282-class (elided side unpinned) | FAIL, but E0433: `topcoat_runtime::Result` does not exist; dies before inference | n (fails, wrong mechanism) |
| c6_ok_pinned | unknown: does Expr\<T\> annotation pin elided side | E0433 same; annotation never reached, question moot at this pin | resolved: unanswerable, Ok/Err family is a total reject |
| d1_signal_ops | pass | FAIL: 3x E0382 on re-used `v3` (set/increment/decrement after get); v4.toggle and v5.push_str (first uses) clean | n (vocabulary itself passes; cross-expr! moves reject) |
| d2_signal_value | unknown | bare `expr!(v3)` PASS; `v3b.clone()` FAIL E0599 (no `clone` on `SignalSurrogate<f64>`) | resolved |
| d3_signal_twice | unknown (M17 double-move watch) | pass: same signal twice in ONE expr! is clean | resolved: safe |
| e1_if_else | pass | pass | y |
| e2_if_unit | pass | pass | y |
| e3_block_let | pass | pass | y |
| e5_unit_block | unknown | pass | resolved: pass |
| f1_closure_annotated | unknown | FAIL E0277: `f64 + F64Surrogate` has no impl (annotated param is real f64, literal is surrogate) | resolved: reject |
| f2_closure_bare | unknown | FAIL E0597: `__topcoat_external0` does not live long enough (captured external's surrogate borrow escapes into closure) | resolved: reject |
| f3_async_closure | unknown | FAIL E0277: same `f64 + F64Surrogate` class as f1 | resolved: reject |
| f5_closure_fn_param | FAIL (grammar/rustc reject) | FAIL: macro parse error `expected `,`` at the `Fn(f64,) -> f64` param annotation | y (rejects at parse, even earlier than predicted) |
| f6_closure_arg | pass | pass (then / then_some closure args) | y |
| g1_call_closure_literal | FAIL E0599 no `.call` | FAIL: E0658 `fn_traits` unstable + E0308 (expected `f64`, found `F64Surrogate`) + E0277 (`f64: Surrogate` unsatisfied) | y (fails; different codes) |
| g2_call_fn_var | FAIL (E0599 and/or missing Surrogated) | FAIL E0277: `Surrogated` not implemented for the closure | y |
| g3_await_called_async_closure | FAIL (same .call gap at the await site) | FAIL: E0308 + E0658 `fn_traits` | y (fails; different codes) |
| g4_fn_var_mention | FAIL (Surrogated for closures absent) | FAIL E0277: `Surrogated` not implemented for the closure | y |
| h1_int_literal | FAIL macro "unsupported literal type" | FAIL: `error: unsupported literal type` | y |
| h2_tuple | FAIL macro no-Tuple-arm | FAIL: `error: unsupported expression` (catch-all arm) | y |

## Surprises (EXPECT-mismatches, verbatim errors)

b1_methods (expected pass):

```
src/lib.rs:52:13: error[E0597]: `__topcoat_external0` does not live long enough: borrowed value does not live long enough
src/lib.rs:52:19: error[E0382]: use of moved value: `v2`: value used here after move
src/lib.rs:53:19: error[E0382]: use of moved value: `v2`: value used here after move
src/lib.rs:54:19: error[E0382]: use of moved value: `v2`: value used here after move
```

Caveat: the E0597 on `.trim()` co-occurs with the E0382 from the
prior move, so trim-in-isolation is unconfirmed; the E0382s alone
prove each expr! takes the String external by value.

c1_none_turbofish / c2_some (expected pass):

```
src/lib.rs:67:13: error[E0433]: cannot find `Option` in `topcoat_runtime`: could not find `Option` in `topcoat_runtime`
src/lib.rs:68:13: error[E0433]: cannot find `Option` in `topcoat_runtime`: could not find `Option` in `topcoat_runtime`
src/lib.rs:73:13: error[E0433]: cannot find `Option` in `topcoat_runtime`: could not find `Option` in `topcoat_runtime`
```

Root cause (adjudicated in-source, not repairable at crate level): the
grammar emits `#topcoat_runtime::Option ... ::none` / `::some`
(grammar/src/expr/expr_path.rs:40-46, expr_call.rs:26) and
`::Result::...`, but topcoat-runtime at 51caa01d exports only
`OptionSurrogate` / `ResultSurrogate` (src/surrogate/option.rs:10,
result.rs:11; `mod option`/`mod result` are unconditional, and the
crate's only features are `discover` and `router`). No `Option` or
`Result` item exists anywhere in the clone (the `topcoat` facade's
runtime module is a plain `pub use topcoat_runtime::*`). No test in the
clone exercises expr! with None/Some/Ok/Err. The whole
None/Some/Ok/Err production family is a guaranteed rustc reject at
this pin.

c4_result_methods (expected pass):

```
src/lib.rs:88:19: error[E0382]: use of moved value: `v6`: value used here after move
src/lib.rs:89:19: error[E0382]: use of moved value: `v6`: value used here after move
src/lib.rs:90:19: error[E0382]: use of moved value: `v6`: value used here after move
```

c5_ok_unpinned (expected FAIL E0282, actual E0433 - fails before
inference, so the E0282 hypothesis was never tested):

```
src/lib.rs:96:13: error[E0433]: cannot find `Result` in `topcoat_runtime`: could not find `Result` in `topcoat_runtime`
```

d1_signal_ops (expected pass; failures are all second-and-later uses
of `v3` across separate expr! calls - every first use of each method
is clean):

```
src/lib.rs:113:19: error[E0382]: use of moved value: `v3`: value used here after move
src/lib.rs:115:19: error[E0382]: use of moved value: `v3`: value used here after move
src/lib.rs:116:19: error[E0382]: use of moved value: `v3`: value used here after move
```

g1/g3 (expected E0599 `.call`; actual is the fn-call operator path -
unstable `fn_traits` plus surrogate/real type mismatch - same gap,
different codes):

```
src/lib.rs:203:13: error[E0658]: use of unstable library feature `fn_traits`
src/lib.rs:203:13: error[E0308]: mismatched types: expected `f64`, found `F64Surrogate`
src/lib.rs:203:13: error[E0277]: the trait bound `f64: Surrogate` is not satisfied: the trait `Surrogate` is not implemented for `f64`
src/lib.rs:216:13: error[E0308]: mismatched types: expected `f64`, found `F64Surrogate`
src/lib.rs:216:13: error[E0658]: use of unstable library feature `fn_traits`
```

## Implications for M20 generator scope

- .call gap (g1-g4): all four fail. Calling a closure literal or a
  free Fn binding, awaiting a called async closure, and even a
  non-call mention of a free Fn binding (no `Surrogated` for closures)
  are guaranteed rustc rejects. gen's E_call-over-closure productions,
  T_future leaves built as `(async || ...)()`, and await sites must be
  scoped out of M20 or driver-guarded. shrink.ml's
  `minimal (T_future a)` (a called async closure) targets this same
  reject family.
- Closure annotation form: NO standalone closure value survives - f1
  (annotated params+return) E0277, f2 (bare, capturing an external)
  E0597, f3 (async annotated) E0277, f5 (Fn-typed param annotation)
  macro parse reject. The only compiling closure position is as a
  method argument (f6: `v1.then(|| 1.0)`, `v1.then_some(2.0)`). M20
  closures must be restricted to method-argument position; T_fn /
  T_async_fn as expression types are out.
- Ok/Err pinning (c5 vs c6): moot. Both die at E0433 because the
  expansion names `topcoat_runtime::Option`/`Result`, which do not
  exist at 51caa01d. The per-case wrapper-shape question (does a
  `let _x: Expr<Result<..>> = expr!(..)` annotation pin the elided
  side) cannot be answered at this pin; E_none/E_some/E_ok/E_err are
  all guaranteed rejects and must be scoped out. This also undercuts
  gen.ml's turbofish_safe premise (c1's whitelisted `None::<f64>`
  itself rejects) and shrink.ml's E_none/E_some minimal values.
- Signals: d3 PASSES - the same signal mentioned twice inside one
  expr! is safe (the name resolver binds the external once), retiring
  the M17 double-move watch. d2: a bare signal value passes;
  `.clone()` on a signal rejects (E0599, `SignalSurrogate` has no
  duck-typed clone) - consistent with gen/shrink treating T_signal as
  Copy-like bare, and `.clone()` must never be emitted on Signal
  receivers.
- Unit block (e5): passes; E_block_unit [] is a safe minimal value.
- Cross-invocation moves (b1/c4/d1): every expr! takes each non-Copy
  external (String, Result, Signal) BY VALUE, so a second expr! naming
  the same binding is E0382. The M20 driver must mint fresh bindings
  per expr! (one wrapper fn or one fresh env per generated case),
  never share an env across invocations. Option externals (c3) showed
  no moves in this corpus.
- Negative controls held: h1 `unsupported literal type` (integer
  literals), h2 `unsupported expression` (tuples, catch-all arm).

## Deferred

loop/while/break/continue/return probes await the OCaml emitter. Their
dispatch arms exist at grammar/src/expr.rs:134-155 (Loop/While/Continue/
Break/Return); this probe crate does not hand-write them because they
are generated text, not hand-written source.

## Round 2 (emitter-written probes)

Date: 2026-08-28. Crate: research/probes-rs/m20r2 (gitignored), 37
probes p01..p37 (p31-p37 are round 2b, added after the first 1k
batch), emitted by `_build/default/bin/emit_m20.exe r2 <file>` via
m20_r2.sh; every AST probe goes through the real renderer
(Ops.printer_renderer). Same toolchain and command shape as round 1,
target dir reused from exprmac. Exit: 101 (7 errors, unchanged by
round 2b: p31-p37 all pass). Log: research/probes-rs/m20r2/check.log.

| id | EXPECT | ACTUAL | MATCH |
|---|---|---|---|
| p01_loop_break | pass | pass | y |
| p02_while_signal_set | pass | pass | y |
| p03_loop_continue_suffix | pass | pass | y |
| p04_nested_loop | pass | pass | y |
| p05_then_annotated | unknown (CRITICAL) | FAIL: E0277 `f64: Surrogate` unsatisfied + E0308 expected `f64`, found `F64Surrogate` (annotated return stays real, body is surrogate; f1 mechanism) | resolved: reject |
| p06_then_bare_control | pass (f6 verbatim) | pass | y |
| p07_trim_start | unknown (trim class) | FAIL E0597 `__topcoat_external0` does not live long enough | resolved: reject |
| p08_trim_end | unknown | FAIL E0597 same | resolved: reject |
| p09_trim_start_cloned | unknown | FAIL E0716 temporary value dropped while borrowed | resolved: reject (clone receiver does not rescue it) |
| p10_trim_end_cloned | unknown | FAIL E0716 same | resolved: reject |
| p11_is_empty | pass | pass | y |
| p12_starts_with | pass | pass | y |
| p13_ends_with | pass | pass | y |
| p14_is_none | pass | pass | y |
| p15_is_err | pass | pass | y |
| p16_unwrap_err | pass | pass | y |
| p17_err | pass | pass | y |
| p18_res_clone_unwrap | pass | pass | y |
| p19_opt_clone_unwrap | pass | pass | y |
| p20_str_eq | pass | pass | y |
| p21_str_lt | pass | pass | y |
| p22_bool_eq | pass | pass | y |
| p23_then_some_lit_recv | pass | pass | y |
| p24_then_some_string | pass | pass | y |
| p25_push_str_arg | pass | pass | y |
| p26_while_cond_get | pass | pass | y |
| p27_f64_specials | unknown | FAIL: `error: only single-identifier paths are supported` at the `f64::NAN` render | resolved: reject |
| p28_expect_escaped | pass | pass | y |
| p29_contains_utf8 | pass | pass | y |
| p30_set_same_signal | pass | pass | y |

Verbatim error lines (all seven; the file:line ids map to p05, p07,
p08, p09, p10, p27):

```
src/lib.rs:164:20: error: only single-identifier paths are supported
src/lib.rs:32:22: error[E0277]: the trait bound `f64: Surrogate` is not satisfied: the trait `Surrogate` is not implemented for `f64`
src/lib.rs:32:13: error[E0308]: mismatched types: expected `f64`, found `F64Surrogate`
src/lib.rs:44:13: error[E0597]: `__topcoat_external0` does not live long enough: borrowed value does not live long enough
src/lib.rs:50:13: error[E0597]: `__topcoat_external0` does not live long enough: borrowed value does not live long enough
src/lib.rs:56:13: error[E0716]: temporary value dropped while borrowed: creates a temporary value which is freed while still in use, borrow later used here
src/lib.rs:62:13: error[E0716]: temporary value dropped while borrowed: creates a temporary value which is freed while still in use, borrow later used here
```

Decision-rule outcomes, applied to the M20 config (Weights.m20 +
M20.m20_safe + gen.ml m20 switches):

- p05 reject: `then_` weight 0. M_then and E_closure are out of the
  M20 scope entirely (no other closure position remains); M_then_some
  stays (p23/p24 pass).
- p07-p10 reject: `trim` weight 0; M_trim_start / M_trim_end excluded
  exactly like round-1's M_trim, on both receiver shapes gen emits.
- p27 reject (new mechanism, the one probe outside the listed rules):
  the macro grammar takes single-identifier paths only, so the
  f64::NAN / f64::INFINITY renders can never compile. The m20 f64
  leaf pool drops nan and the infinities and drops the random-bits
  arm (a random pattern can land on NaN or an infinity).
- Flow keywords all pass (p01-p04, p26): E_loop / E_while / E_break /
  E_continue stay in scope with their default weights. Closure-body
  E_return / E_return_unit stay excluded: with then_ out no closure
  position exists, and no probe covered them.
- All other probed string/option/result methods, comparisons,
  then_some forms, push_str, and same-signal reuse pass and stay in
  scope.

## Round 3 (first 1k batch) and round 2b confirmations

The first 1k batch run (m20_gate.sh, seed 0x4d3230) compiled with 58
coded errors plus case_neg. Every error falls in one of three new
mechanism classes; none is a printer bug, all are macro-level limits
of the surrogate system at the pin:

1. E0382 (15): a BARE signal value (a signal var outside the direct
   method-receiver position: an if branch tail, a let RHS, a
   then_some arg) moves its once-bound `__topcoat_external` per use,
   and per iteration inside a loop body. Representative:
   `expr!((if true { v4 } else { v4 }).get())` and
   `let v11 = v4;` inside a block. Method receivers do not move
   (round 2 p02/p26/p30 all pass).
2. E0308 (33, all StrSurrogate/StringSurrogate): a string literal is
   `&StrSurrogate`, a String-typed value is `StringSurrogate`, and
   the two never unify. Both directions fail: `v5.set("...")`
   (literal where a value is needed) and
   `"  both  ".contains(v9.clone().expect("..."))` (value where the
   pattern arg needs a literal). Mixed if/else branches fail the same
   way. Comparisons are the exception (p20/p21: mixed operands pass).
3. E0277 `!: Surrogate` (10): a loop with no break of its own has
   type `!`, and `!` is not Surrogate. `expr!(loop { })` and
   `expr!(loop { v1; })` both reject; `loop { ...; break; }` passes
   (p37), and while loops are always `()` (p26).

Scope narrowing applied (all mechanical, then re-verified):

- Signals: receivers only. gen's m20 sig_recv draws the receiver
  var directly for get/set/toggle/increment/decrement/push_str;
  ty_signal = 0 removes signal-typed targets and lets; m20_safe bans
  E_var 3/4/5 anywhere else.
- Strings: the m20 T_string leaf draws a cloned String var instead of
  a literal; pattern args (starts_with/ends_with/contains) and expect
  messages stay literal-only; m20_safe bans bare string literals
  outside those five arg positions.
- Loops: the m20 loop production forces the break suffix; m20_safe
  requires every E_loop to hold a break that binds THAT loop.
  has_break stops the descent at any nested E_loop, E_while, or
  closure body, so an inner loop's break never counts for the outer
  one (an unlabelled break binds the innermost loop).

Round 2b probes (p31-p37) verify the narrowed scope's load-bearing
shapes before the re-run, all PASS: p31 `v2.clone().starts_with("a")`,
p32 String == String, p33 String < String, p34 `v5.set(v2.clone())`,
p35 both-String if/else branches, p36 let-bound String reused through
`.clone()`, p37 `loop { v3.set(1.0); break; }`.

Second 1k batch run after narrowing: GREEN. The only error is
case_neg's, inside its sidecar span:

```
src/lib.rs:5014:19: error: unsupported literal type
M20 GATE GREEN: 2 error line(s), all src/lib.rs errors inside case_neg span [5012,5015]
```

Final M20 scope exclusions (forms the generator must never emit;
m20_safe flags them): E_call, E_await, E_closure, E_async_closure,
E_some, E_none, E_ok, E_err, E_tuple, E_field, E_index, E_return,
E_return_unit, U_deref, M_trim, M_trim_start, M_trim_end, M_then,
M_clone outside the `var.clone()` var_use shape and M_clone on any
signal var (a signal receiver admits only get / set / toggle /
increment / decrement / push_str, so `v3.clone()` is E0599, round 1
d2), non-finite f64
literals, bare signal values (signal vars outside the direct
method-receiver position), bare string literals outside pattern and
expect-message args, loops without their own break, T_fn / T_async_fn
/ T_future / T_signal as drawn types, and genv var v10 (the fn-typed
input: a bare mention is round 1 g4's E0277, no Surrogated impl for
closures, so M20.genv omits the variable entirely).
