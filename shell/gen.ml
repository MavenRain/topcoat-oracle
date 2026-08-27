(* M17: sized, type-directed QCheck generator (DESIGN.md Phase C).
   Order: draw a target type first, then draw an expression at that
   type. The gate (test/test_gen.ml) checks 1000 samples: wf accepts
   each sample and infers exactly the target type.

   M18: every pick_w weight comes from a Weights.t record threaded
   through the context (corpus-seeded default in shell/weights.ml,
   census in research/m18-corpus-census.md). The M18 gate tallies
   10k samples: every reachable constructor appears at least once
   and the excluded set stays at zero.

   Weight-0 constructs, and why each stays out:
   - E_tuple / T_tuple / E_field: expr! has no syn::Expr::Tuple arm
     (research/study-topcoat.md). Leaf arms keep a total backstop.
   - E_index (W_index_unsupported) and U_deref (W_deref_unsupported):
     wf rejects both.
   - Bare E_let outside a block: it binds nothing and types unit.
   - E_break / E_continue: only as a trailing loop-body statement.
     E_return / E_return_unit: only as a closure-body tail. Both
     placements keep the never shape out of value positions, which
     wf's value_ty rejects.

   Compile-soundness levers ahead of the M20 rustc gate:
   - None::<T> is the one turbofish expr! accepts, so E_none only
     carries a type the printer can name there (turbofish_safe).
   - A bare Ok/Err literal leaves its other side un-inferred under a
     method call, so result-typed method receivers come from
     environment variables only. The default environment carries two
     Result inputs and two Option inputs for that purpose; the driver
     binds them with full annotations outside expr!.
   - Rust moves non-Copy values and wf has no affine tracking, so a
     variable use at a String / Option / Result type goes through
     .clone() (var_use). Clone aliasing is itself a target risk class.
   - Future and AsyncFn types stay out of let and parameter positions
     (param_safe): futures have no Clone and a moved future cannot be
     awaited twice.
   M20 watch items: signal handles are assumed Copy (bare variable
   use); closure captures that escape their block; loop bodies that
   never break (interpreter fuel and the driver timeout own
   non-termination). *)

open Prelude
open Ast

module G = QCheck.Gen

let ( >>= ) = G.( >>= )

(* Generation environment. A signal entry carries its ELEMENT type;
   wf_env wraps it as T_signal for the checker. *)
type genv = {
  inputs : (int * ty) list;
  signals : (int * ty) list;
}

(* v0..v2 scalar inputs, v3..v5 signals, v6..v9 Result and Option
   inputs (annotated by the driver, so they pin inference under
   method calls), v10 a plain function input. *)
let default_genv =
  {
    inputs =
      [
        (0, T_f64);
        (1, T_bool);
        (2, T_string);
        (6, T_result (T_f64, T_string));
        (7, T_result (T_string, T_f64));
        (8, T_option T_f64);
        (9, T_option T_string);
        (10, T_fn ([ T_f64 ], T_f64));
      ];
    signals = [ (3, T_f64); (4, T_bool); (5, T_string) ];
  }

let wf_env g =
  append (map (fun kv -> (fst kv, T_signal (snd kv))) g.signals) g.inputs

let first_fresh g =
  1 + fold (fun m kv -> if fst kv > m then fst kv else m) 0 (wf_env g)

(* Generator context. env mirrors wf's ctx.env. in_async gates the
   E_await production. sig_elems feeds nested signal type draws.
   w carries the production weights (M18). *)
type gctx = {
  env : (int * ty) list;
  in_async : bool;
  sig_elems : ty list;
  w : Weights.t;
}

let keep p xs = rev (fold (fun acc x -> if p x then x :: acc else acc) [] xs)

(* Uniform draw from a nonempty list given as head plus tail. *)
let pick_elt first rest =
  G.int_bound (len rest) >>= fun i ->
  G.return
    (Option.fold ~none:first ~some:(fun x -> x) (nth_opt (first :: rest) i))

(* Weighted draw over thunked generators, nonempty by the head/tail
   split. The exhausted arm replays the head; it is unreachable while
   every weight is positive. *)
let pick_w first rest =
  let all = first :: rest in
  let total = fold (fun n c -> n + fst c) 0 all in
  G.int_bound (max 0 (total - 1)) >>= fun r ->
  let rec go cs budget =
    match cs with
    | [] -> (snd first) ()
    | c :: cs' ->
        if budget < fst c then (snd c) () else go cs' (budget - fst c)
  in
  go all r

(* Shape probes: one exhaustive match each, so call sites can stay on
   Option.fold. *)
let result_sides t =
  match t with
  | T_result (a, e) -> Some (a, e)
  | T_f64 | T_bool | T_string | T_unit | T_option _ | T_tuple _ | T_fn _
  | T_async_fn _ | T_future _ | T_signal _ -> None

let fn_shape t =
  match t with
  | T_fn (ps, r) -> Some (ps, r)
  | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
  | T_tuple _ | T_async_fn _ | T_future _ | T_signal _ -> None

let async_fn_shape t =
  match t with
  | T_async_fn (ps, r) -> Some (ps, r)
  | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
  | T_tuple _ | T_fn _ | T_future _ | T_signal _ -> None

(* Copy-like uses stay bare; every other variable use clones, so no
   generated expression moves an environment value twice. *)
let var_use kv =
  match snd kv with
  | T_f64 | T_bool | T_unit | T_signal _ | T_fn _ | T_async_fn _ ->
      E_var (fst kv)
  | T_string | T_option _ | T_result _ | T_tuple _ | T_future _ ->
      E_method (E_var (fst kv), M_clone, [])

(* Types the printer can name inside None::<T>. Fn and Future types
   have no nameable surface form there. *)
let rec turbofish_safe t =
  match t with
  | T_f64 | T_bool | T_string | T_unit -> true
  | T_option a -> turbofish_safe a
  | T_result (a, e) -> turbofish_safe a && turbofish_safe e
  | T_signal a -> turbofish_safe a
  | T_tuple ts -> fold (fun ok x -> ok && turbofish_safe x) true ts
  | T_fn (_, _) | T_async_fn (_, _) | T_future _ -> false

(* Let and closure-parameter positions demote the move-hostile
   types. *)
let rec param_safe t =
  match t with
  | T_f64 | T_bool | T_string | T_unit -> t
  | T_option a -> T_option (param_safe a)
  | T_result (a, e) -> T_result (param_safe a, param_safe e)
  | T_tuple ts -> T_tuple (map param_safe ts)
  | T_fn (ps, r) -> T_fn (map param_safe ps, param_safe r)
  | T_async_fn (ps, r) -> T_fn (map param_safe ps, param_safe r)
  | T_future _ -> T_f64
  | T_signal a -> T_signal a

(* Environment variables of a wanted type or shape. *)
let vars_at env t = keep (fun kv -> ty_eq (snd kv) t) env

let result_vars pred env =
  keep
    (fun kv ->
      Option.fold ~none:false
        ~some:(fun s -> pred (fst s) (snd s))
        (result_sides (snd kv)))
    env

let fn_sites ret env =
  rev
    (fold
       (fun acc kv ->
         Option.fold ~none:acc
           ~some:(fun s ->
             if ty_eq (snd s) ret then (fst kv, fst s) :: acc else acc)
           (fn_shape (snd kv)))
       [] env)

let async_fn_sites ret env =
  rev
    (fold
       (fun acc kv ->
         Option.fold ~none:acc
           ~some:(fun s ->
             if ty_eq (snd s) ret then (fst kv, fst s) :: acc else acc)
           (async_fn_shape (snd kv)))
       [] env)

(* Literal pools. The f64 pool covers the render-sensitive vectors
   from research/m13-rust-render-probe.md plus the IEEE specials. *)
let f64_pool =
  map Floatops.of_float
    [
      0.0; -0.0; 1.0; -1.0; 0.5; 0.1; 1.5; 2.0; 3.0; 100.0; 1e15; 1e16;
      1e300; 5e-324; 1e-5; 123456789012345680.0; infinity; neg_infinity;
      nan;
    ]

(* A 32-bit half from two 16-bit draws; G.int_bound stays well inside
   every Random backend's range. *)
let half32 =
  G.int_bound 65535 >>= fun a ->
  G.int_bound 65535 >>= fun b -> G.return ((a * 65536) + b)

let gen_f64_bits (w : Weights.t) =
  pick_w
    ( w.f64_pool,
      fun () ->
        match f64_pool with
        | [] -> G.return (0, 0)
        | p :: ps -> pick_elt p ps )
    [
      ( w.f64_random,
        fun () ->
          half32 >>= fun hi ->
          half32 >>= fun lo -> G.return (hi, lo) );
    ]

(* Byte strings, with UTF-8 multibyte and escape-sensitive entries
   for the bytes-vs-UTF-16 and render risk classes. *)
let str_pool =
  [
    ""; "a"; "b"; "abc"; "hello world"; " lead"; "trail "; "  both  ";
    "0"; "3.14"; "caf\xc3\xa9"; "quote\"and\\back";
  ]

let gen_str =
  match str_pool with
  | [] -> G.return ""
  | s :: ss -> pick_elt s ss

(* Fresh parameter ids for a closure. Pure. *)
let rec alloc_params ps nid =
  match ps with
  | [] -> ([], nid)
  | p :: rest ->
      let more = alloc_params rest (nid + 1) in
      ((nid, p) :: fst more, snd more)

(* Sized type draw. Signal element choices come from sig_elems, so an
   expression at any drawn signal type can always find a variable. *)
let rec gen_ty (w : Weights.t) elems fuel =
  let sub = fuel - 1 in
  let deeper =
    if fuel <= 0 then []
    else
      [
        ( w.ty_option,
          fun () -> gen_ty w elems sub >>= fun a -> G.return (T_option a) );
        ( w.ty_result,
          fun () ->
            gen_ty w elems sub >>= fun a ->
            gen_ty w elems sub >>= fun e -> G.return (T_result (a, e)) );
        ( w.ty_fn,
          fun () ->
            gen_tys w elems sub >>= fun ps ->
            gen_ty w elems sub >>= fun r -> G.return (T_fn (ps, r)) );
        ( w.ty_async_fn,
          fun () ->
            gen_tys w elems sub >>= fun ps ->
            gen_ty w elems sub >>= fun r -> G.return (T_async_fn (ps, r)) );
        ( w.ty_future,
          fun () -> gen_ty w elems sub >>= fun a -> G.return (T_future a) );
      ]
  in
  let sigs =
    match elems with
    | [] -> []
    | e0 :: es ->
        [
          ( w.ty_signal,
            fun () -> pick_elt e0 es >>= fun a -> G.return (T_signal a) );
        ]
  in
  (* T_unit draws fuel-free with the other leaf types: fuel-gating it
     would exclude unit from every tyfuel=0 sample, a third of the
     draw, and undershoot its census weight (M18 review finding). *)
  pick_w
    (w.ty_f64, fun () -> G.return T_f64)
    (append
       [
         (w.ty_bool, fun () -> G.return T_bool);
         (w.ty_string, fun () -> G.return T_string);
         (w.ty_unit, fun () -> G.return T_unit);
       ]
       (append deeper sigs))

and gen_tys w elems fuel = G.int_bound 2 >>= fun n -> gen_ty_list w elems fuel n

and gen_ty_list w elems fuel n =
  if n <= 0 then G.return []
  else
    gen_ty w elems fuel >>= fun t ->
    gen_ty_list w elems fuel (n - 1) >>= fun ts -> G.return (t :: ts)

(* Leaf expressions: one per type, no fuel. Total over ty. The signal
   tripwire arm returns a wrong-type expression on purpose: it is
   unreachable while gen_ty draws signal elements from the
   environment, and the gate flags it as a mismatch if a change ever
   makes it reachable. *)
let rec leaf ctx nid t =
  match t with
  | T_f64 ->
      gen_f64_bits ctx.w >>= fun p ->
      G.return (E_lit (L_f64_bits (fst p, snd p)), nid)
  | T_bool -> G.bool >>= fun b -> G.return (E_lit (L_bool b), nid)
  | T_string -> gen_str >>= fun s -> G.return (E_lit (L_str s), nid)
  | T_unit -> G.return (E_block_unit [], nid)
  | T_option a ->
      if turbofish_safe a then G.return (E_none a, nid)
      else leaf ctx nid a >>= fun p -> G.return (E_some (fst p), snd p)
  | T_result (a, e) ->
      leaf ctx nid a >>= fun p -> G.return (E_ok (fst p, e), snd p)
  | T_tuple ts ->
      (* Unconstructible under expr!; total backstop for caller-given
         types only. *)
      leaf_list ctx nid ts >>= fun p -> G.return (E_tuple (fst p), snd p)
  | T_fn (ps, r) ->
      let prm = alloc_params ps nid in
      leaf ctx (snd prm) r >>= fun p ->
      G.return (E_closure (fst prm, r, fst p), snd p)
  | T_async_fn (ps, r) ->
      let prm = alloc_params ps nid in
      leaf ctx (snd prm) r >>= fun p ->
      G.return (E_async_closure (fst prm, r, fst p), snd p)
  | T_future a ->
      leaf ctx nid a >>= fun p ->
      G.return (E_call (E_async_closure ([], a, fst p), []), snd p)
  | T_signal a ->
      (match vars_at ctx.env (T_signal a) with
       | [] -> G.return (E_none a, nid) (* tripwire *)
       | c :: cs ->
           pick_elt c cs >>= fun kv -> G.return (E_var (fst kv), nid))

and leaf_list ctx nid ts =
  match ts with
  | [] -> G.return ([], nid)
  | t :: rest ->
      leaf ctx nid t >>= fun p ->
      leaf_list ctx (snd p) rest >>= fun q ->
      G.return (fst p :: fst q, snd q)

(* Expression draw at a target type. fuel bounds the tree depth; at
   zero every type has a leaf. Every production returns exactly the
   target type; the gate re-checks that through wf. *)
let rec gen_expr ctx fuel nid t =
  if fuel <= 0 then leaf ctx nid t
  else
    let w = ctx.w in
    let sub = fuel - 1 in
    let var_prods =
      match vars_at ctx.env t with
      | [] -> []
      | c :: cs ->
          [
            ( w.var,
              fun () ->
                pick_elt c cs >>= fun kv -> G.return (var_use kv, nid) );
          ]
    in
    let fn_calls =
      match fn_sites t ctx.env with
      | [] -> []
      | c :: cs ->
          [
            ( w.fn_call,
              fun () ->
                pick_elt c cs >>= fun site ->
                gen_args ctx sub nid (snd site) >>= fun p ->
                G.return (E_call (E_var (fst site), fst p), snd p) );
          ]
    in
    let generic =
      [
        ( w.block,
          fun () ->
            gen_stmts ctx sub nid >>= fun (stmts, ctx1, n1) ->
            gen_expr ctx1 sub n1 t >>= fun p ->
            G.return (E_block (stmts, fst p), snd p) );
        ( w.if_else,
          fun () ->
            gen_expr ctx sub nid T_bool >>= fun pc ->
            gen_expr ctx sub (snd pc) t >>= fun pa ->
            gen_expr ctx sub (snd pa) t >>= fun pb ->
            G.return (E_if_else (fst pc, fst pa, fst pb), snd pb) );
        ( w.clone,
          fun () ->
            gen_expr ctx sub nid t >>= fun p ->
            G.return (E_method (fst p, M_clone, []), snd p) );
        ( w.opt_unwrap,
          fun () ->
            gen_expr ctx sub nid (T_option t) >>= fun p ->
            G.return (E_method (fst p, M_unwrap, []), snd p) );
        ( w.opt_expect,
          fun () ->
            gen_expr ctx sub nid (T_option t) >>= fun p ->
            gen_str >>= fun msg ->
            G.return (E_method (fst p, M_expect, [ E_lit (L_str msg) ]), snd p) );
        ( w.call_closure,
          fun () ->
            gen_tys w ctx.sig_elems 1 >>= fun ps0 ->
            let ps = map param_safe ps0 in
            gen_expr ctx sub nid (T_fn (ps, t)) >>= fun pf ->
            gen_args ctx sub (snd pf) ps >>= fun pa ->
            G.return (E_call (fst pf, fst pa), snd pa) );
      ]
    in
    let res_unwrap =
      match result_vars (fun a _e -> ty_eq a t) ctx.env with
      | [] -> []
      | c :: cs ->
          [
            ( w.res_unwrap,
              fun () ->
                pick_elt c cs >>= fun kv ->
                G.return (E_method (var_use kv, M_unwrap, []), nid) );
          ]
    in
    let res_unwrap_err =
      match result_vars (fun _a e -> ty_eq e t) ctx.env with
      | [] -> []
      | c :: cs ->
          [
            ( w.res_unwrap_err,
              fun () ->
                pick_elt c cs >>= fun kv ->
                G.return (E_method (var_use kv, M_unwrap_err, []), nid) );
          ]
    in
    let res_expect_err =
      match result_vars (fun _a e -> ty_eq e t) ctx.env with
      | [] -> []
      | c :: cs ->
          [
            ( w.res_expect_err,
              fun () ->
                pick_elt c cs >>= fun kv ->
                gen_str >>= fun msg ->
                G.return
                  ( E_method (var_use kv, M_expect_err, [ E_lit (L_str msg) ]),
                    nid ) );
          ]
    in
    let awaits =
      if ctx.in_async then
        [
          ( w.await,
            fun () ->
              gen_expr ctx sub nid (T_future t) >>= fun p ->
              G.return (E_await (fst p), snd p) );
        ]
      else []
    in
    pick_w
      (w.leaf, fun () -> leaf ctx nid t)
      (append var_prods
         (append fn_calls
            (append generic
               (append res_unwrap
                  (append res_unwrap_err
                     (append res_expect_err
                        (append awaits (specific_prods ctx sub nid t))))))))

(* Type-directed productions beyond the generic set. Each returns
   exactly the target type. *)
and specific_prods ctx sub nid t =
  let w = ctx.w in
  match t with
  | T_f64 ->
      append
        [
          ( w.arith,
            fun () ->
              pick_elt B_add [ B_sub; B_mul; B_div ] >>= fun op ->
              gen_expr ctx sub nid T_f64 >>= fun pa ->
              gen_expr ctx sub (snd pa) T_f64 >>= fun pb ->
              G.return (E_binary (op, fst pa, fst pb), snd pb) );
          ( w.neg,
            fun () ->
              gen_expr ctx sub nid T_f64 >>= fun p ->
              G.return (E_unary (U_neg, fst p), snd p) );
          ( w.str_len,
            fun () ->
              gen_expr ctx sub nid T_string >>= fun p ->
              G.return (E_method (fst p, M_len, []), snd p) );
        ]
        (sig_get ctx sub nid T_f64)
  | T_bool ->
      let res_preds =
        match result_vars (fun _a _e -> true) ctx.env with
        | [] -> []
        | c :: cs ->
            [
              ( w.res_pred,
                fun () ->
                  pick_elt M_is_ok [ M_is_err ] >>= fun m ->
                  pick_elt c cs >>= fun kv ->
                  G.return (E_method (var_use kv, m, []), nid) );
            ]
      in
      append
        [
          ( w.not_,
            fun () ->
              gen_expr ctx sub nid T_bool >>= fun p ->
              G.return (E_unary (U_not, fst p), snd p) );
          ( w.eq_ne,
            fun () ->
              pick_elt B_eq [ B_ne ] >>= fun op ->
              pick_elt T_f64 [ T_bool; T_string ] >>= fun ot ->
              gen_expr ctx sub nid ot >>= fun pa ->
              gen_expr ctx sub (snd pa) ot >>= fun pb ->
              G.return (E_binary (op, fst pa, fst pb), snd pb) );
          ( w.cmp,
            fun () ->
              pick_elt B_lt [ B_le; B_gt; B_ge ] >>= fun op ->
              pick_elt T_f64 [ T_string ] >>= fun ot ->
              gen_expr ctx sub nid ot >>= fun pa ->
              gen_expr ctx sub (snd pa) ot >>= fun pb ->
              G.return (E_binary (op, fst pa, fst pb), snd pb) );
          ( w.str_pred,
            fun () ->
              pick_elt M_starts_with [ M_ends_with; M_contains ] >>= fun m ->
              gen_expr ctx sub nid T_string >>= fun ps ->
              gen_expr ctx sub (snd ps) T_string >>= fun pa ->
              G.return (E_method (fst ps, m, [ fst pa ]), snd pa) );
          ( w.opt_pred,
            fun () ->
              pick_elt M_is_some [ M_is_none ] >>= fun m ->
              gen_ty w ctx.sig_elems 1 >>= fun pt ->
              gen_expr ctx sub nid (T_option pt) >>= fun p ->
              G.return (E_method (fst p, m, []), snd p) );
          ( w.str_is_empty,
            fun () ->
              gen_expr ctx sub nid T_string >>= fun p ->
              G.return (E_method (fst p, M_is_empty, []), snd p) );
        ]
        (append res_preds (sig_get ctx sub nid T_bool))
  | T_string ->
      append
        [
          ( w.trim,
            fun () ->
              pick_elt M_trim [ M_trim_start; M_trim_end ] >>= fun m ->
              gen_expr ctx sub nid T_string >>= fun p ->
              G.return (E_method (fst p, m, []), snd p) );
          ( w.to_owned,
            fun () ->
              gen_expr ctx sub nid T_string >>= fun p ->
              G.return (E_method (fst p, M_to_owned, []), snd p) );
        ]
        (sig_get ctx sub nid T_string)
  | T_unit ->
      append
        [
          ( w.if_unit,
            fun () ->
              gen_expr ctx sub nid T_bool >>= fun pc ->
              gen_expr ctx sub (snd pc) T_unit >>= fun pt ->
              G.return (E_if (fst pc, fst pt), snd pt) );
          ( w.while_,
            fun () ->
              gen_expr ctx sub nid T_bool >>= fun pc ->
              gen_loop_body ctx sub (snd pc) >>= fun pb ->
              G.return (E_while (fst pc, fst pb), snd pb) );
          ( w.loop_,
            fun () ->
              gen_loop_body ctx sub nid >>= fun pb ->
              G.return (E_loop (fst pb), snd pb) );
          ( w.block_unit,
            fun () ->
              gen_stmts ctx sub nid >>= fun (stmts, _ctx1, n1) ->
              G.return (E_block_unit stmts, n1) );
        ]
        (sig_writes ctx sub nid)
  | T_option a ->
      let none_prod =
        if turbofish_safe a then
          [ (w.none, fun () -> G.return (E_none a, nid)) ]
        else []
      in
      let okp =
        match result_vars (fun x _e -> ty_eq x a) ctx.env with
        | [] -> []
        | c :: cs ->
            [
              ( w.res_ok,
                fun () ->
                  pick_elt c cs >>= fun kv ->
                  G.return (E_method (var_use kv, M_ok, []), nid) );
            ]
      in
      let errp =
        match result_vars (fun _x e -> ty_eq e a) ctx.env with
        | [] -> []
        | c :: cs ->
            [
              ( w.res_err,
                fun () ->
                  pick_elt c cs >>= fun kv ->
                  G.return (E_method (var_use kv, M_err, []), nid) );
            ]
      in
      append
        [
          ( w.some,
            fun () ->
              gen_expr ctx sub nid a >>= fun p ->
              G.return (E_some (fst p), snd p) );
          ( w.then_some,
            fun () ->
              gen_expr ctx sub nid T_bool >>= fun pc ->
              gen_expr ctx sub (snd pc) a >>= fun pv ->
              G.return (E_method (fst pc, M_then_some, [ fst pv ]), snd pv) );
          ( w.then_,
            fun () ->
              gen_expr ctx sub nid T_bool >>= fun pc ->
              gen_expr ctx sub (snd pc) (T_fn ([], a)) >>= fun pf ->
              G.return (E_method (fst pc, M_then, [ fst pf ]), snd pf) );
        ]
        (append none_prod (append okp errp))
  | T_result (a, e) ->
      [
        ( w.ok,
          fun () ->
            gen_expr ctx sub nid a >>= fun p ->
            G.return (E_ok (fst p, e), snd p) );
        ( w.err,
          fun () ->
            gen_expr ctx sub nid e >>= fun p ->
            G.return (E_err (fst p, a), snd p) );
      ]
  | T_tuple _ -> []
  | T_fn (ps, r) ->
      [
        ( w.closure,
          fun () ->
            let prm = alloc_params ps nid in
            let inner =
              { ctx with env = append (fst prm) ctx.env; in_async = false }
            in
            closure_body inner sub (snd prm) r >>= fun p ->
            G.return (E_closure (fst prm, r, fst p), snd p) );
      ]
  | T_async_fn (ps, r) ->
      [
        ( w.async_closure,
          fun () ->
            let prm = alloc_params ps nid in
            let inner =
              { ctx with env = append (fst prm) ctx.env; in_async = true }
            in
            closure_body inner sub (snd prm) r >>= fun p ->
            G.return (E_async_closure (fst prm, r, fst p), snd p) );
      ]
  | T_future a ->
      let via_var =
        match async_fn_sites a ctx.env with
        | [] -> []
        | c :: cs ->
            [
              ( w.call_async_fn,
                fun () ->
                  pick_elt c cs >>= fun site ->
                  gen_args ctx sub nid (snd site) >>= fun p ->
                  G.return (E_call (E_var (fst site), fst p), snd p) );
            ]
      in
      append
        [
          ( w.call_async_closure,
            fun () ->
              gen_expr ctx sub nid (T_async_fn ([], a)) >>= fun p ->
              G.return (E_call (fst p, []), snd p) );
        ]
        via_var
  | T_signal a ->
      (match vars_at ctx.env (T_signal a) with
       | [] -> []
       | c :: cs ->
           [
             ( w.sig_var,
               fun () ->
                 pick_elt c cs >>= fun kv -> G.return (E_var (fst kv), nid) );
           ])

and sig_get ctx sub nid elem =
  match vars_at ctx.env (T_signal elem) with
  | [] -> []
  | _ :: _ ->
      [
        ( ctx.w.sig_get,
          fun () ->
            gen_expr ctx sub nid (T_signal elem) >>= fun p ->
            G.return (E_method (fst p, M_get, []), snd p) );
      ]

and sig_writes ctx sub nid =
  match ctx.sig_elems with
  | [] -> []
  | e0 :: es ->
      [
        ( ctx.w.sig_write,
          fun () -> pick_elt e0 es >>= fun elem -> write_at ctx sub nid elem );
      ]

and write_at ctx sub nid elem =
  let w = ctx.w in
  let extras =
    match elem with
    | T_bool ->
        [
          ( w.toggle,
            fun () ->
              gen_expr ctx sub nid (T_signal T_bool) >>= fun p ->
              G.return (E_method (fst p, M_toggle, []), snd p) );
        ]
    | T_f64 ->
        [
          ( w.inc_dec,
            fun () ->
              pick_elt M_increment [ M_decrement ] >>= fun m ->
              gen_expr ctx sub nid (T_signal T_f64) >>= fun p ->
              G.return (E_method (fst p, m, []), snd p) );
        ]
    | T_string ->
        [
          ( w.push_str,
            fun () ->
              gen_expr ctx sub nid (T_signal T_string) >>= fun ps ->
              gen_expr ctx sub (snd ps) T_string >>= fun pv ->
              G.return (E_method (fst ps, M_push_str, [ fst pv ]), snd pv) );
        ]
    | T_unit | T_option _ | T_result _ | T_tuple _ | T_fn _
    | T_async_fn _ | T_future _ | T_signal _ -> []
  in
  pick_w
    ( w.set_,
      fun () ->
        gen_expr ctx sub nid (T_signal elem) >>= fun ps ->
        gen_expr ctx sub (snd ps) elem >>= fun pv ->
        G.return (E_method (fst ps, M_set, [ fst pv ]), snd pv) )
    extras

(* A closure body at return type r: a plain expression, or a block
   whose tail returns. The never shape stays at the body tail, where
   wf's expect_shape accepts it. *)
and closure_body ctx fuel nid r =
  let w = ctx.w in
  let ret_unit =
    if ty_eq r T_unit then
      [
        ( w.body_return_unit,
          fun () -> G.return (E_block ([], E_return_unit), nid) );
      ]
    else []
  in
  pick_w
    (w.body_plain, fun () -> gen_expr ctx fuel nid r)
    (append
       [
         ( w.body_return,
           fun () ->
             gen_expr ctx fuel nid r >>= fun p ->
             G.return (E_block ([], E_return (fst p)), snd p) );
       ]
       ret_unit)

(* A loop body: statements plus an optional trailing break or
   continue. wf sees the body under in_loop, so the trailing
   statement is always legal here and nowhere else. *)
and gen_loop_body ctx fuel nid =
  let w = ctx.w in
  gen_stmts ctx fuel nid >>= fun (stmts, _ctx1, n1) ->
  pick_w
    (w.suffix_none, fun () -> G.return [])
    [
      (w.suffix_break, fun () -> G.return [ E_break ]);
      (w.suffix_continue, fun () -> G.return [ E_continue ]);
    ]
  >>= fun suffix -> G.return (E_block_unit (append stmts suffix), n1)

(* Zero to two statements. A let extends the environment for the
   statements and tail after it; ids strictly increase, so nothing
   shadows. *)
and gen_stmts ctx fuel nid = G.int_bound 2 >>= fun n -> stmts_go ctx fuel nid n []

and stmts_go ctx fuel nid n acc =
  if n <= 0 then G.return (rev acc, ctx, nid)
  else
    pick_w
      ( ctx.w.stmt_let,
        fun () ->
          gen_ty ctx.w ctx.sig_elems 1 >>= fun pt0 ->
          let pt = param_safe pt0 in
          gen_expr ctx fuel nid pt >>= fun p ->
          G.return ([ (snd p, pt) ], E_let (snd p, fst p), snd p + 1) )
      [
        ( ctx.w.stmt_expr,
          fun () ->
            gen_ty ctx.w ctx.sig_elems 1 >>= fun dt ->
            gen_expr ctx fuel nid dt >>= fun p ->
            G.return ([], fst p, snd p) );
      ]
    >>= fun step ->
    let (delta, stmt, n2) = step in
    stmts_go { ctx with env = append delta ctx.env } fuel n2 (n - 1)
      (stmt :: acc)

and gen_args ctx fuel nid ps =
  match ps with
  | [] -> G.return ([], nid)
  | p :: rest ->
      gen_expr ctx fuel nid p >>= fun pe ->
      gen_args ctx fuel (snd pe) rest >>= fun q ->
      G.return (fst pe :: fst q, snd q)

(* Top-level sample: target type, then expression at it. Both fuels
   draw uniformly (type 0..2, expression 0..6) instead of through
   QCheck's size parameter: Gen.nat in qcheck-core 0.91 skews small
   (half of all draws are under 10), which would leave over half the
   samples at fuel 0 and never exercise a recursive production
   (review finding, 2026-08-27). The top context matches wf's
   check_top: no loop, no closure, not async. *)
let gen_target_w (w : Weights.t) g =
  let elems = map snd g.signals in
  G.int_bound 2 >>= fun tyfuel ->
  G.int_bound 6 >>= fun fuel ->
  gen_ty w elems tyfuel >>= fun t ->
  gen_expr
    { env = wf_env g; in_async = false; sig_elems = elems; w }
    fuel (first_fresh g) t
  >>= fun p -> G.return (t, fst p)

let gen_target g = gen_target_w Weights.default g
