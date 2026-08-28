(* M20 generation scope (DESIGN.md M20; research/m20-expr-macro-probe.md).

   genv: default_genv without v10, the fn-typed input. A bare mention
   of a fn-typed var is a guaranteed reject (no Surrogated impl for
   closures, round 1 g4), so the variable must not exist at all.

   m20_safe: syntactic auditor over the FINAL probe-adjudicated scope.
   It is an assertion over generated samples, not a sieve: Weights.m20
   plus gen.ml's m20 switches must already make every banned
   constructor unreachable, and the M20 gate turns red if a sample
   trips this walk. *)

open Prelude
open Ast

let genv : Gen.genv =
  {
    Gen.inputs =
      [
        (0, T_f64);
        (1, T_bool);
        (2, T_string);
        (6, T_result (T_f64, T_string));
        (7, T_result (T_string, T_f64));
        (8, T_option T_f64);
        (9, T_option T_string);
      ];
    signals = [ (3, T_f64); (4, T_bool); (5, T_string) ];
  }

let all p xs = fold (fun ok x -> ok && p x) true xs

let signal_id i = i = 3 || i = 4 || i = 5

(* The one shape a signal var may take: direct receiver of a signal
   method. Bare signal values move their once-bound external per use
   and per loop iteration (E0382, batch round 3). These rules are
   tied to this genv: 3/4/5 are its only signals, and ty_signal = 0
   means no let ever binds one. *)
let signal_meth m =
  match m with
  | M_get | M_set | M_toggle | M_increment | M_decrement | M_push_str ->
      true
  | M_then | M_then_some | M_len | M_is_empty | M_trim | M_trim_start
  | M_trim_end | M_starts_with | M_ends_with | M_contains | M_to_owned
  | M_is_some | M_is_none | M_is_ok | M_is_err | M_ok | M_err
  | M_unwrap_err | M_expect_err | M_unwrap | M_expect | M_clone -> false

(* Methods whose single arg must be a string literal: pattern args and
   expect messages take &StrSurrogate; a StringSurrogate value there
   is E0308 (batch round 3; round 2b p31 shows the literal passes). *)
let lit_arg_meth m =
  match m with
  | M_starts_with | M_ends_with | M_contains | M_expect | M_expect_err ->
      true
  | M_then | M_then_some | M_len | M_is_empty | M_trim | M_trim_start
  | M_trim_end | M_to_owned | M_is_some | M_is_none | M_is_ok | M_is_err
  | M_ok | M_err | M_unwrap_err | M_unwrap | M_get | M_set | M_toggle
  | M_increment | M_decrement | M_push_str | M_clone -> false

let is_clone m =
  match m with
  | M_clone -> true
  | M_then | M_then_some | M_len | M_is_empty | M_trim | M_trim_start
  | M_trim_end | M_starts_with | M_ends_with | M_contains | M_to_owned
  | M_is_some | M_is_none | M_is_ok | M_is_err | M_ok | M_err
  | M_unwrap_err | M_expect_err | M_unwrap | M_expect | M_get | M_set
  | M_toggle | M_increment | M_decrement | M_push_str -> false

let var_id e =
  match e with
  | E_var i -> Some i
  | E_lit _ | E_unary (_, _) | E_binary (_, _, _) | E_tuple _ | E_some _
  | E_none _ | E_ok (_, _) | E_err (_, _) | E_call (_, _)
  | E_method (_, _, _) | E_field (_, _) | E_index (_, _) | E_let (_, _)
  | E_block (_, _) | E_block_unit _ | E_if (_, _) | E_if_else (_, _, _)
  | E_loop _ | E_while (_, _) | E_break | E_continue | E_return_unit
  | E_return _ | E_closure (_, _, _) | E_async_closure (_, _, _)
  | E_await _ -> None

let str_lit e =
  match e with
  | E_lit l ->
      (match l with
       | L_str _ -> true
       | L_f64_bits (_, _) -> false
       | L_bool _ -> false)
  | E_var _ | E_unary (_, _) | E_binary (_, _, _) | E_tuple _ | E_some _
  | E_none _ | E_ok (_, _) | E_err (_, _) | E_call (_, _)
  | E_method (_, _, _) | E_field (_, _) | E_index (_, _) | E_let (_, _)
  | E_block (_, _) | E_block_unit _ | E_if (_, _) | E_if_else (_, _, _)
  | E_loop _ | E_while (_, _) | E_break | E_continue | E_return_unit
  | E_return _ | E_closure (_, _, _) | E_async_closure (_, _, _)
  | E_await _ -> false

let one_lit_arg args =
  match args with
  | a :: [] -> str_lit a
  | [] -> false
  | _ :: _ :: _ -> false

let no_args args =
  match args with
  | [] -> true
  | _ :: _ -> false

(* A break that binds the enclosing loop: descends value positions,
   not nested loop or closure bodies (Shrink.escapes_loop, break
   only). A loop with no such break has type !, which is not
   Surrogate (batch round 3, E0277). *)
let rec has_break e =
  match e with
  | E_break -> true
  | E_continue -> false
  | E_loop _ -> false
  | E_closure (_, _, _) | E_async_closure (_, _, _) -> false
  | E_while (_, _) ->
      (* a break in the body binds the while itself; a break in the
         condition is E0590, invalid outright. Neither escapes to the
         enclosing loop. *)
      false
  | E_lit _ | E_var _ | E_unary (_, _) | E_binary (_, _, _) | E_tuple _
  | E_some _ | E_none _ | E_ok (_, _) | E_err (_, _) | E_call (_, _)
  | E_method (_, _, _) | E_field (_, _) | E_index (_, _) | E_let (_, _)
  | E_block (_, _) | E_block_unit _ | E_if (_, _) | E_if_else (_, _, _)
  | E_return_unit | E_return _ | E_await _ ->
      Shrink.exists has_break (Shrink.children e)

(* Methods allowed anywhere in an M20 sample. M_trim, M_trim_start,
   M_trim_end: E0597 macro-temp borrow (rounds 1 and 2). M_then: its
   arg is an annotated closure in our print, rejected (round 2 p05).
   M_clone is NOT here: it is legal only in the var_use shape,
   special-cased in the walk. The signal methods are not here either:
   they type only against a bare signal var, the first arm of the
   walk, so any other receiver shape is a reject. *)
let meth_allowed m =
  match m with
  | M_then -> false
  | M_then_some -> true
  | M_len -> true
  | M_is_empty -> true
  | M_trim -> false
  | M_trim_start -> false
  | M_trim_end -> false
  | M_starts_with -> true
  | M_ends_with -> true
  | M_contains -> true
  | M_to_owned -> true
  | M_is_some -> true
  | M_is_none -> true
  | M_is_ok -> true
  | M_is_err -> true
  | M_ok -> true
  | M_err -> true
  | M_unwrap_err -> true
  | M_expect_err -> true
  | M_unwrap -> true
  | M_expect -> true
  | M_get -> false
  | M_set -> false
  | M_toggle -> false
  | M_increment -> false
  | M_decrement -> false
  | M_push_str -> false
  | M_clone -> false

(* f64 literal bits must be finite: the renderer prints NaN and the
   infinities as f64:: path expressions, which the macro grammar
   rejects (round 2 p27). *)
let finite_bits hi lo =
  let f = Floatops.to_float hi lo in
  Float.is_finite f

let rec safe_in in_loop e =
  match e with
  | E_lit (L_f64_bits (hi, lo)) -> finite_bits hi lo
  | E_lit (L_bool _) -> true
  | E_lit (L_str _) ->
      (* a bare string literal is &StrSurrogate and never unifies
         with StringSurrogate values; literals live only in the
         lit_arg_meth positions *)
      false
  | E_var i -> not (signal_id i)
  | E_unary (op, a) ->
      (match op with
       | U_neg -> safe_in in_loop a
       | U_not -> safe_in in_loop a
       | U_deref -> false)
  | E_binary (_op, a, b) -> safe_in in_loop a && safe_in in_loop b
  | E_tuple _ -> false
  | E_some _ -> false
  | E_none _ -> false
  | E_ok (_, _) -> false
  | E_err (_, _) -> false
  | E_call (_, _) -> false
  | E_method (recv, m, args) ->
      (match () with
       | () when Option.fold ~none:false ~some:signal_id (var_id recv) ->
           signal_meth m && all (safe_in in_loop) args
       | () when is_clone m ->
           (* var_use shape only: a fresh non-signal var, cloned once,
              no args. Every other clone receiver is out of scope. *)
           Option.fold ~none:false
             ~some:(fun i -> not (signal_id i))
             (var_id recv)
           && no_args args
       | () when lit_arg_meth m ->
           safe_in in_loop recv && one_lit_arg args
       | () ->
           meth_allowed m && safe_in in_loop recv
           && all (safe_in in_loop) args)
  | E_field (_, _) -> false
  | E_index (_, _) -> false
  | E_let (_, rhs) -> safe_in in_loop rhs
  | E_block (stmts, tail) ->
      all (safe_in in_loop) stmts && safe_in in_loop tail
  | E_block_unit stmts -> all (safe_in in_loop) stmts
  | E_if (c, t1) -> safe_in in_loop c && safe_in in_loop t1
  | E_if_else (c, a, b) ->
      safe_in in_loop c && safe_in in_loop a && safe_in in_loop b
  | E_loop b -> has_break b && safe_in true b
  | E_while (c, b) ->
      (* the body is a loop context of its own; the condition is not:
         an unlabeled break or continue there is E0590 *)
      safe_in false c && safe_in true b
  | E_break -> in_loop
  | E_continue -> in_loop
  | E_return_unit -> false
  | E_return _ -> false
  | E_closure (_, _, _) -> false
  | E_async_closure (_, _, _) -> false
  | E_await _ -> false

let m20_safe e = safe_in false e
