//! M20 probe crate: adjudicate, with the compiler, which printed-expr
//! construct families the topcoat expr! macro accepts at 51caa01d.
//! One fn per probe; EXPECT comments record the hypothesis under test.
//! Verdicts land in research/m20-expr-macro-probe.md.
//!
//! Deferred to the OCaml emitter (loop-keyword probes are generated
//! text, not hand-written source): while/loop/break/continue bodies
//! and closure-body `return` - their dispatch arms exist
//! (grammar/src/expr.rs:134-155 has Loop/While/Continue/Break/Return),
//! so only surrogate-level typing remains to adjudicate there.
#![allow(dead_code, unused_variables)]

use topcoat_runtime::Signal;
use topcoat_runtime_macro::expr;

// --- A: f64 literals, arithmetic, comparison, unary ---

// EXPECT pass: surrogate ops mirror + - * / on f64.
fn a1_arith() {
    let v0: f64 = 1.5;
    let _ = expr!(v0 + 1.0);
    let _ = expr!((v0 - 2.0) * (v0 / 4.0));
}

// EXPECT pass: Debug-form float literals incl. exponent and -0.0.
fn a2_literals() {
    let _ = expr!(1e300 * (-0.0));
    let _ = expr!(5e-324 + 1000000000000000.0);
}

// EXPECT pass: eq/ne/cmp lower to surrogate comparisons.
fn a3_cmp() {
    let v0: f64 = 1.5;
    let _ = expr!(v0 == 2.0);
    let _ = expr!(v0 <= (v0 * 2.0));
}

// EXPECT pass: unary neg and not.
fn a4_unary() {
    let v0: f64 = 1.5;
    let v1: bool = true;
    let _ = expr!(-v0);
    let _ = expr!(!v1);
}

// --- B: strings ---

// EXPECT pass: string method vocabulary on a free String binding.
fn b1_methods() {
    let v2: String = String::new();
    let _ = expr!(v2.len());
    let _ = expr!(v2.trim());
    let _ = expr!(v2.contains("a"));
    let _ = expr!(v2.clone());
}

// EXPECT pass: str literal receiver + to_owned.
fn b2_literal_recv() {
    let _ = expr!("lit".to_owned());
    let _ = expr!("a\"b\n".len());
}

// --- C: Option / Result ---

// EXPECT pass: the one whitelisted turbofish.
fn c1_none_turbofish() {
    let _ = expr!(None::<f64>);
    let _ = expr!(None::<String>);
}

// EXPECT pass: Some pins its payload concretely.
fn c2_some() {
    let _ = expr!(Some(1.0));
}

// EXPECT pass: option methods on free Option bindings.
fn c3_option_methods() {
    let v8: Option<f64> = None;
    let _ = expr!(v8.is_some());
    let _ = expr!(v8.unwrap());
    let _ = expr!(v8.expect("m"));
}

// EXPECT pass: result methods on free Result bindings.
fn c4_result_methods() {
    let v6: Result<f64, String> = Ok(1.5);
    let _ = expr!(v6.is_ok());
    let _ = expr!(v6.ok());
    let _ = expr!(v6.unwrap());
    let _ = expr!(v6.expect_err("m"));
}

// EXPECT FAIL (E0282-class): printed Ok/Err omit the elided side; a
// bare statement position gives rustc nothing to pin it with.
fn c5_ok_unpinned() {
    let _ = expr!(Ok(1.5));
}

// EXPECT unknown: can the driver pin the elided side through the
// Expr<T> return type? Adjudicates the M20 wrapper strategy.
fn c6_ok_pinned() {
    let _x: topcoat_runtime::Expr<Result<f64, String>> = expr!(Ok(1.5));
}

// --- D: signals ---

// EXPECT pass: signal read/write vocabulary on free Signal bindings.
fn d1_signal_ops() {
    let v3 = Signal::new(0.0f64);
    let v4 = Signal::new(true);
    let v5 = Signal::new(String::new());
    let _ = expr!(v3.get());
    let _ = expr!(v3.set(1.0));
    let _ = expr!(v4.toggle());
    let _ = expr!(v3.increment());
    let _ = expr!(v3.decrement());
    let _ = expr!(v5.push_str("x"));
}

// EXPECT unknown: bare signal var as the whole expression (surrogate
// round-trip at Signal type) and duck-typed clone.
fn d2_signal_value() {
    let v3 = Signal::new(0.0f64);
    let _ = expr!(v3);
    let v3b = Signal::new(0.0f64);
    let _ = expr!(v3b.clone());
}

// EXPECT unknown (M17 watch item): same signal mentioned twice in one
// expression; if into_surrogate takes it by value twice, non-Copy
// Signal would move twice.
fn d3_signal_twice() {
    let v3 = Signal::new(0.0f64);
    let _ = expr!(v3.get() + v3.get());
}

// --- E: control flow, blocks, let ---

// EXPECT pass: value if/else with braced blocks.
fn e1_if_else() {
    let v1: bool = true;
    let _ = expr!(if v1 { 1.0 } else { 2.0 });
}

// EXPECT pass: unit if, statement body.
fn e2_if_unit() {
    let v1: bool = true;
    let v3 = Signal::new(0.0f64);
    let _ = expr!(if v1 { v3.set(1.0); });
}

// EXPECT pass: block with let statement and value tail.
fn e3_block_let() {
    let v0: f64 = 1.5;
    let _ = expr!({ let v11 = 2.0; v11 + v0 });
}

// EXPECT unknown: empty unit block (into_real at unit).
fn e5_unit_block() {
    let _ = expr!({ });
}

// --- F: closures (as values, never called) ---

// EXPECT unknown: our printed closure form annotates params AND the
// return type; real topcoat sites annotate neither.
fn f1_closure_annotated() {
    let _ = expr!(|v11: f64| -> f64 { v11 + 1.0 });
}

// EXPECT unknown: bare-minimum closure, no annotations (fallback form
// if f1 rejects).
fn f2_closure_bare() {
    let v0: f64 = 1.5;
    let _ = expr!(|| v0 + 1.0);
}

// EXPECT unknown: async closure value (our E_async_closure print).
fn f3_async_closure() {
    let _ = expr!(async |v11: f64| -> f64 { v11 + 1.0 });
}

// EXPECT FAIL (grammar: parenthesized generic args rejected on paths;
// and rustc: bare Fn(..) is not a type): Fn-typed closure param
// annotation, reachable when gen_ty draws T_fn inside a param list.
fn f5_closure_fn_param() {
    let v0: f64 = 1.5;
    let _ = expr!(|v11: Fn(f64,) -> f64| -> f64 { v0 });
}

// EXPECT pass: closure as a method ARGUMENT (bool.then) - the one
// place generated closures are consumed without an E_call.
fn f6_closure_arg() {
    let v1: bool = true;
    let _ = expr!(v1.then(|| 1.0));
    let _ = expr!(v1.then_some(2.0));
}

// --- G: calls and await (the .call-gap hypothesis) ---

// EXPECT FAIL (E0599 no method `call`): calling a closure literal.
fn g1_call_closure_literal() {
    let _ = expr!((|v11: f64| -> f64 { v11 })(1.0));
}

// EXPECT FAIL (E0599 and/or missing Surrogated impl): calling a free
// Fn-typed binding (default_genv v10).
fn g2_call_fn_var() {
    let v10 = |x: f64| x;
    let _ = expr!(v10(1.0));
}

// EXPECT FAIL (same .call gap, inside the only position gen emits
// await: an async closure body awaiting a called async closure).
fn g3_await_called_async_closure() {
    let _ = expr!(async || -> f64 { (async || -> f64 { 1.0 })().await });
}

// EXPECT FAIL (Surrogated for closures likely absent): free Fn
// binding mentioned in a non-call position.
fn g4_fn_var_mention() {
    let v10 = |x: f64| x;
    let _ = expr!(v10.clone());
}

// --- H: known macro-level rejects (negative controls) ---

// EXPECT FAIL (macro: "unsupported literal type"): integer literal.
fn h1_int_literal() {
    let _ = expr!(1 + 2);
}

// EXPECT FAIL (macro: no Tuple arm): tuple expression.
fn h2_tuple() {
    let _ = expr!((1.5, 2.5));
}
