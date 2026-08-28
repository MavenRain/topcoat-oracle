(* M18: corpus-seeded generator weights (DESIGN.md Phase C).

   One field per pick_w production site in gen.ml. The default value
   seeds each field from the topcoat examples corpus census in
   research/m18-corpus-census.md: 24 runtime-expression fragments
   across examples/ and demos/ at pin 51caa01d.

   Seeding rule, applied mechanically: for a production the census
   counts, weight = 1 + ceil(log2(count + 1)); a corpus-absent
   production keeps the floor weight 1, so every construct stays
   reachable (the corpus-absent constructs are the least-exercised
   Rust/TS parity surface, which is the bug-yield zone). Sites the
   census cannot see keep their M17 structural values; the census doc
   lists both groups.

   Every default field is positive. pick_w skips a zero-weight entry
   correctly, but a configuration with total weight 0 would make the
   draw collapse to the head arm; keep at least one field of each
   competing group positive. *)

type t = {
  (* type draw (gen_ty) *)
  ty_f64 : int;
  ty_bool : int;
  ty_string : int;
  ty_unit : int;
  ty_option : int;
  ty_result : int;
  ty_fn : int;
  ty_async_fn : int;
  ty_future : int;
  ty_signal : int;
  (* f64 literal draw: render-vector pool vs random bit pattern *)
  f64_pool : int;
  f64_random : int;
  (* generic productions (gen_expr) *)
  leaf : int;
  var : int;
  fn_call : int;
  block : int;
  if_else : int;
  clone : int;
  opt_unwrap : int;
  opt_expect : int;
  call_closure : int;
  res_unwrap : int;
  res_unwrap_err : int;
  res_expect_err : int;
  await : int;
  (* f64-specific *)
  arith : int;
  neg : int;
  str_len : int;
  (* bool-specific *)
  not_ : int;
  eq_ne : int;
  cmp : int;
  str_pred : int;
  opt_pred : int;
  str_is_empty : int;
  res_pred : int;
  (* string-specific *)
  trim : int;
  to_owned : int;
  (* unit-specific *)
  if_unit : int;
  while_ : int;
  loop_ : int;
  block_unit : int;
  sig_write : int;
  (* option-specific *)
  some : int;
  then_some : int;
  then_ : int;
  none : int;
  res_ok : int;
  res_err : int;
  (* result-specific *)
  ok : int;
  err : int;
  (* fn / async-fn / future / signal specific *)
  closure : int;
  async_closure : int;
  call_async_closure : int;
  call_async_fn : int;
  sig_var : int;
  (* signal read and writes *)
  sig_get : int;
  set_ : int;
  toggle : int;
  inc_dec : int;
  push_str : int;
  (* closure body *)
  body_plain : int;
  body_return : int;
  body_return_unit : int;
  (* loop-body suffix *)
  suffix_none : int;
  suffix_break : int;
  suffix_continue : int;
  (* statements (gen_stmts) *)
  stmt_let : int;
  stmt_expr : int;
}

(* Corpus-seeded default. Census counts appear as comments; "M17"
   marks a structural value the census cannot see. *)
let default =
  {
    ty_f64 = 3 (* 3 *);
    ty_bool = 3 (* 3 *);
    ty_string = 4 (* 7 *);
    ty_unit = 5 (* 12 *);
    ty_option = 1 (* 0 *);
    ty_result = 1 (* 0 *);
    ty_fn = 5 (* 9 *);
    ty_async_fn = 3 (* 2 *);
    ty_future = 3 (* 2 *);
    ty_signal = 1 (* 0 *);
    f64_pool = 6 (* M17 *);
    f64_random = 1 (* M17 *);
    leaf = 4 (* 5 literals *);
    var = 4 (* 4 *);
    fn_call = 1 (* 0 *);
    block = 1 (* 0 *);
    if_else = 3 (* 2 *);
    clone = 1 (* 0 *);
    opt_unwrap = 1 (* 0 *);
    opt_expect = 1 (* 0 *);
    call_closure = 1 (* 0 *);
    res_unwrap = 1 (* 0 *);
    res_unwrap_err = 1 (* 0 *);
    res_expect_err = 1 (* 0 *);
    await = 3 (* 2 *);
    arith = 2 (* 1 *);
    neg = 1 (* 0 *);
    str_len = 1 (* 0 *);
    not_ = 2 (* 1 *);
    eq_ne = 1 (* 0 *);
    cmp = 2 (* 1 *);
    str_pred = 1 (* 0 *);
    opt_pred = 1 (* 0 *);
    str_is_empty = 3 (* 2 *);
    res_pred = 1 (* 0 *);
    trim = 1 (* 0 *);
    to_owned = 3 (* 2 *);
    if_unit = 1 (* 0 *);
    while_ = 1 (* 0 *);
    loop_ = 1 (* 0 *);
    block_unit = 3 (* 2 *);
    sig_write = 5 (* 12 writes *);
    some = 1 (* 0 *);
    then_some = 1 (* 0 *);
    then_ = 1 (* 0 *);
    none = 1 (* 0 *);
    res_ok = 1 (* 0 *);
    res_err = 1 (* 0 *);
    ok = 1 (* 0 *);
    err = 1 (* 0 *);
    closure = 5 (* 9 *);
    async_closure = 3 (* 2 *);
    call_async_closure = 1 (* 0 *);
    call_async_fn = 3 (* 2 *);
    sig_var = 6 (* 28 bare signal receivers *);
    sig_get = 6 (* 16 *);
    set_ = 4 (* 7 *);
    toggle = 2 (* 1 *);
    inc_dec = 4 (* 4 *);
    push_str = 1 (* 0 *);
    body_plain = 5 (* 8 *);
    body_return = 1 (* 0 *);
    body_return_unit = 1 (* 0 *);
    suffix_none = 2 (* M17 *);
    suffix_break = 3 (* M17 *);
    suffix_continue = 1 (* M17 *);
    stmt_let = 3 (* 2 *);
    stmt_expr = 4 (* 5 *);
  }

(* M20 printer-soundness scope (research/m20-expr-macro-probe.md,
   rounds 1 and 2). A zero weight marks a production whose printed
   form the expr! macro or rustc rejects at pin 51caa01d:
   - call/await/closure family: no Surrogated for closures, unstable
     fn_traits, annotated closures type-mismatch (round 1 f1-f5,
     g1-g4; round 2 p05 confirms the annotated then-arg closure).
   - None/Some/Ok/Err: topcoat_runtime::Option/Result do not exist.
     This zeroes the VALUE constructors only (some/none/ok/err =
     E_some/E_none/E_ok/E_err). res_ok/res_err stay at 1: they draw
     the `.ok()` / `.err()` methods on a result-typed var, which pass
     (round 2 p17).
   - trim family: E0597 macro-temp borrow (round 1 b1; round 2
     p07-p10 confirm trim_start/trim_end, bare and cloned).
   - clone: kept only inside var_use (a fresh var receiver), so the
     generic clone production is off (signal receivers have no
     surrogate clone).
   - closure bodies with return: unreachable anyway once then_ is
     out; kept at zero for a tight scope.
   gen.ml's m20 switches keep option/result draws var-backed so the
   zeroed leaves are never forced. *)
let m20 =
  {
    default with
    ty_fn = 0;
    ty_async_fn = 0;
    ty_future = 0;
    ty_signal = 0
    (* bare signal values move per use inside expr!; signals appear
       only as direct method receivers, never as drawn types *);
    fn_call = 0;
    clone = 0;
    call_closure = 0;
    await = 0;
    trim = 0 (* round 2: trim_start/trim_end also E0597 *);
    some = 0;
    none = 0;
    then_ = 0 (* round 2 p05: annotated closure arg rejects *);
    res_ok = 1;
    res_err = 1;
    ok = 0;
    err = 0;
    closure = 0;
    async_closure = 0;
    call_async_closure = 0;
    call_async_fn = 0;
    body_return = 0;
    body_return_unit = 0;
  }
