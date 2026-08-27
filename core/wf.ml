(* Type-shape checker for the topcoat expr! AST (M11). Total: every
   ill-shaped input maps to a wf_error value. ZxCaml-subset notes:
   anonymous functions take `fun _ ->` (a `()` parameter pattern is a
   Tpat_construct, rejected by omlz, M08 probe); Option/Result are
   only touched through their stdlib combinator surface. *)

open Prelude
open Ast

type shape =
  | Sh_ty of ty
  | Sh_never

type wf_error =
  | W_unbound of int
  | W_mismatch of ty * ty (* expected, got *)
  | W_arity of int * int (* expected, got *)
  | W_not_bool of ty
  | W_not_callable of ty
  | W_bad_method of ty (* receiver that lacks the method *)
  | W_bad_operand of ty
  | W_break_outside_loop
  | W_continue_outside_loop
  | W_return_outside_closure
  | W_await_outside_async
  | W_await_non_future of ty
  | W_deref_unsupported
  | W_index_unsupported
  | W_field_on of ty
  | W_field_out_of_range of int
  | W_bad_f64_bits
  | W_never_operand (* a diverging operand where a value type is required *)
  | W_never_at_top

(* Stable short codes for tests and repro output. *)
let wf_error_code e =
  match e with
  | W_unbound _ -> "unbound"
  | W_mismatch (_, _) -> "mismatch"
  | W_arity (_, _) -> "arity"
  | W_not_bool _ -> "not-bool"
  | W_not_callable _ -> "not-callable"
  | W_bad_method _ -> "bad-method"
  | W_bad_operand _ -> "bad-operand"
  | W_break_outside_loop -> "break-outside-loop"
  | W_continue_outside_loop -> "continue-outside-loop"
  | W_return_outside_closure -> "return-outside-closure"
  | W_await_outside_async -> "await-outside-async"
  | W_await_non_future _ -> "await-non-future"
  | W_deref_unsupported -> "deref-unsupported"
  | W_index_unsupported -> "index-unsupported"
  | W_field_on _ -> "field-on"
  | W_field_out_of_range _ -> "field-out-of-range"
  | W_bad_f64_bits -> "bad-f64-bits"
  | W_never_operand -> "never-operand"
  | W_never_at_top -> "never-at-top"

type ret_ctx =
  | R_top
  | R_fn of ty

type ctx = {
  env : (int * ty) list;
  in_loop : bool;
  ret : ret_ctx;
  in_async : bool;
}

let int_eq a b = a = b

(* A statement is either a let (extends the block environment) or a
   plain expression; classifying into an own ADT keeps the block
   walker free of option matching. *)
type stmt_class =
  | Sc_let of int * expr
  | Sc_expr

let classify_stmt s =
  match s with
  | E_let (x, rhs) -> Sc_let (x, rhs)
  | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
  | E_none _ | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _
  | E_index _ | E_block _ | E_block_unit _ | E_if _ | E_if_else _
  | E_loop _ | E_while _ | E_break | E_continue | E_return_unit
  | E_return _ | E_closure _ | E_async_closure _ | E_await _ -> Sc_expr

(* Shapes of tuple components: either all value types, or at least
   one diverging component (which makes the whole tuple diverge). *)
type tys_or_never =
  | Tys of ty list
  | Has_never

let rec collect_tys shapes =
  match shapes with
  | [] -> Tys []
  | sh :: rest ->
      (match sh with
       | Sh_never -> Has_never
       | Sh_ty t ->
           (match collect_tys rest with
            | Has_never -> Has_never
            | Tys ts -> Tys (t :: ts)))

(* Never unifies with every type (Rust's ! coercion). *)
let expect_shape sh t =
  match sh with
  | Sh_never -> Ok ()
  | Sh_ty t' -> if ty_eq t t' then Ok () else Error (W_mismatch (t, t'))

(* Positions that need the operand's value type reject divergence. *)
let value_ty sh =
  match sh with
  | Sh_never -> Error W_never_operand
  | Sh_ty t -> Ok t

let join_shapes a b =
  match a with
  | Sh_never -> Ok b
  | Sh_ty ta ->
      (match b with
       | Sh_never -> Ok a
       | Sh_ty tb ->
           if ty_eq ta tb then Ok a else Error (W_mismatch (ta, tb)))

let eq_comparable t =
  match t with
  | T_f64 | T_bool | T_string -> true
  | T_unit | T_option _ | T_result _ | T_tuple _ | T_fn _ | T_async_fn _
  | T_future _ | T_signal _ -> false

let ord_comparable t =
  match t with
  | T_f64 | T_string -> true
  | T_bool | T_unit | T_option _ | T_result _ | T_tuple _ | T_fn _
  | T_async_fn _ | T_future _ | T_signal _ -> false

let bits32_ok n = n >= 0 && n <= 4294967295

let rec infer ctx e =
  match e with
  | E_lit l ->
      (match l with
       | L_f64_bits (hi, lo) ->
           if bits32_ok hi && bits32_ok lo then Ok (Sh_ty T_f64)
           else Error W_bad_f64_bits
       | L_bool _ -> Ok (Sh_ty T_bool)
       | L_str _ -> Ok (Sh_ty T_string))
  | E_var x ->
      Option.fold ~none:(Error (W_unbound x))
        ~some:(fun t -> Ok (Sh_ty t))
        (assoc_opt int_eq x ctx.env)
  | E_unary (op, e1) ->
      Result.bind (infer ctx e1) (fun sh ->
          match op with
          | U_neg ->
              Result.bind (expect_shape sh T_f64) (fun _ -> Ok (Sh_ty T_f64))
          | U_not ->
              Result.bind (expect_shape sh T_bool) (fun _ ->
                  Ok (Sh_ty T_bool))
          | U_deref -> Error W_deref_unsupported)
  | E_binary (op, a, b) ->
      Result.bind (infer ctx a) (fun sa ->
          Result.bind (infer ctx b) (fun sb ->
              match op with
              | B_add | B_sub | B_mul | B_div ->
                  Result.bind (expect_shape sa T_f64) (fun _ ->
                      Result.bind (expect_shape sb T_f64) (fun _ ->
                          Ok (Sh_ty T_f64)))
              | B_eq | B_ne ->
                  Result.bind (value_ty sa) (fun ta ->
                      Result.bind (expect_shape sb ta) (fun _ ->
                          if eq_comparable ta then Ok (Sh_ty T_bool)
                          else Error (W_bad_operand ta)))
              | B_lt | B_le | B_gt | B_ge ->
                  Result.bind (value_ty sa) (fun ta ->
                      Result.bind (expect_shape sb ta) (fun _ ->
                          if ord_comparable ta then Ok (Sh_ty T_bool)
                          else Error (W_bad_operand ta)))))
  | E_tuple es ->
      Result.bind (infer_all ctx es) (fun shapes ->
          match collect_tys shapes with
          | Has_never -> Ok Sh_never
          | Tys ts -> Ok (Sh_ty (T_tuple ts)))
  | E_some e1 ->
      Result.bind (infer ctx e1) (fun sh ->
          match sh with
          | Sh_never -> Ok Sh_never
          | Sh_ty t -> Ok (Sh_ty (T_option t)))
  | E_none t -> Ok (Sh_ty (T_option t))
  | E_ok (e1, terr) ->
      Result.bind (infer ctx e1) (fun sh ->
          match sh with
          | Sh_never -> Ok Sh_never
          | Sh_ty t -> Ok (Sh_ty (T_result (t, terr))))
  | E_err (e1, tok) ->
      Result.bind (infer ctx e1) (fun sh ->
          match sh with
          | Sh_never -> Ok Sh_never
          | Sh_ty t -> Ok (Sh_ty (T_result (tok, t))))
  | E_call (f, args) ->
      Result.bind (infer ctx f) (fun sf ->
          match sf with
          | Sh_never -> Ok Sh_never
          | Sh_ty tf ->
              (match tf with
               | T_fn (ps, r) ->
                   Result.bind (check_args ctx ps args) (fun _ ->
                       Ok (Sh_ty r))
               | T_async_fn (ps, r) ->
                   Result.bind (check_args ctx ps args) (fun _ ->
                       Ok (Sh_ty (T_future r)))
               | T_f64 | T_bool | T_string | T_unit | T_option _
               | T_result _ | T_tuple _ | T_future _ | T_signal _ ->
                   Error (W_not_callable tf)))
  | E_method (recv, m, args) ->
      Result.bind (infer ctx recv) (fun sr ->
          match sr with
          | Sh_never -> Ok Sh_never
          | Sh_ty tr ->
              Result.bind (infer_method ctx tr m args) (fun t ->
                  Ok (Sh_ty t)))
  | E_field (e1, i) ->
      Result.bind (infer ctx e1) (fun sh ->
          match sh with
          | Sh_never -> Ok Sh_never
          | Sh_ty t ->
              (match t with
               | T_tuple ts ->
                   Option.fold
                     ~none:(Error (W_field_out_of_range i))
                     ~some:(fun tf -> Ok (Sh_ty tf))
                     (nth_opt ts i)
               | T_f64 | T_bool | T_string | T_unit | T_option _
               | T_result _ | T_fn _ | T_async_fn _ | T_future _
               | T_signal _ -> Error (W_field_on t)))
  | E_index (_, _) -> Error W_index_unsupported
  | E_let (_, rhs) ->
      (* A let outside a block binds nothing downstream; its own value
         is unit. *)
      Result.bind (infer ctx rhs) (fun _ -> Ok (Sh_ty T_unit))
  | E_block (stmts, tail) ->
      Result.bind (infer_block ctx stmts) (fun ctx' -> infer ctx' tail)
  | E_block_unit stmts ->
      Result.bind (infer_block ctx stmts) (fun _ -> Ok (Sh_ty T_unit))
  | E_if (c, thn) ->
      Result.bind (infer ctx c) (fun sc ->
          Result.bind (expect_shape sc T_bool) (fun _ ->
              Result.bind (infer ctx thn) (fun st ->
                  Result.bind (expect_shape st T_unit) (fun _ ->
                      Ok (Sh_ty T_unit)))))
  | E_if_else (c, a, b) ->
      Result.bind (infer ctx c) (fun sc ->
          Result.bind (expect_shape sc T_bool) (fun _ ->
              Result.bind (infer ctx a) (fun sa ->
                  Result.bind (infer ctx b) (fun sb -> join_shapes sa sb))))
  | E_loop body ->
      Result.bind (infer { ctx with in_loop = true } body) (fun sb ->
          Result.bind (expect_shape sb T_unit) (fun _ -> Ok (Sh_ty T_unit)))
  | E_while (c, body) ->
      Result.bind (infer ctx c) (fun sc ->
          Result.bind (expect_shape sc T_bool) (fun _ ->
              Result.bind (infer { ctx with in_loop = true } body)
                (fun sb ->
                  Result.bind (expect_shape sb T_unit) (fun _ ->
                      Ok (Sh_ty T_unit)))))
  | E_break -> if ctx.in_loop then Ok Sh_never else Error W_break_outside_loop
  | E_continue ->
      if ctx.in_loop then Ok Sh_never else Error W_continue_outside_loop
  | E_return_unit ->
      (match ctx.ret with
       | R_top -> Error W_return_outside_closure
       | R_fn t ->
           if ty_eq t T_unit then Ok Sh_never
           else Error (W_mismatch (t, T_unit)))
  | E_return e1 ->
      (match ctx.ret with
       | R_top -> Error W_return_outside_closure
       | R_fn t ->
           Result.bind (infer ctx e1) (fun sh ->
               Result.bind (expect_shape sh t) (fun _ -> Ok Sh_never)))
  | E_closure (ps, ret, body) ->
      let inner =
        { env = append ps ctx.env; in_loop = false; ret = R_fn ret;
          in_async = false }
      in
      Result.bind (infer inner body) (fun sb ->
          Result.bind (expect_shape sb ret) (fun _ ->
              Ok (Sh_ty (T_fn (map snd ps, ret)))))
  | E_async_closure (ps, ret, body) ->
      let inner =
        { env = append ps ctx.env; in_loop = false; ret = R_fn ret;
          in_async = true }
      in
      Result.bind (infer inner body) (fun sb ->
          Result.bind (expect_shape sb ret) (fun _ ->
              Ok (Sh_ty (T_async_fn (map snd ps, ret)))))
  | E_await e1 ->
      if ctx.in_async then
        Result.bind (infer ctx e1) (fun sh ->
            match sh with
            | Sh_never -> Ok Sh_never
            | Sh_ty t ->
                (match t with
                 | T_future t1 -> Ok (Sh_ty t1)
                 | T_f64 | T_bool | T_string | T_unit | T_option _
                 | T_result _ | T_tuple _ | T_fn _ | T_async_fn _
                 | T_signal _ -> Error (W_await_non_future t)))
      else Error W_await_outside_async

and infer_all ctx es =
  match es with
  | [] -> Ok []
  | e :: rest ->
      Result.bind (infer ctx e) (fun sh ->
          Result.bind (infer_all ctx rest) (fun shapes ->
              Ok (sh :: shapes)))

and infer_block ctx stmts =
  match stmts with
  | [] -> Ok ctx
  | s :: rest ->
      (match classify_stmt s with
       | Sc_let (x, rhs) ->
           Result.bind (infer ctx rhs) (fun sh ->
               match sh with
               | Sh_never -> infer_block ctx rest
               | Sh_ty t ->
                   infer_block { ctx with env = (x, t) :: ctx.env } rest)
       | Sc_expr ->
           Result.bind (infer ctx s) (fun _ -> infer_block ctx rest))

and check_expect ctx e t =
  Result.bind (infer ctx e) (fun sh -> expect_shape sh t)

and check_args ctx expected args =
  let ne = len expected in
  let na = len args in
  if ne <> na then Error (W_arity (ne, na))
  else check_each ctx expected args

and check_each ctx expected args =
  match expected with
  | [] -> Ok ()
  | t :: ts ->
      (match args with
       | [] -> Ok () (* unreachable: lengths pre-checked equal *)
       | a :: rest ->
           Result.bind (check_expect ctx a t) (fun _ ->
               check_each ctx ts rest))

(* Receiver-directed method typing. Each arm checks the receiver and
   argument shapes and yields the result type. *)
and infer_method ctx recv m args =
  match m with
  | M_then ->
      (match recv with
       | T_bool ->
           (match args with
            | arg :: [] ->
                Result.bind (infer ctx arg) (fun sh ->
                    Result.bind (value_ty sh) (fun t ->
                        match t with
                        | T_fn (ps, r) ->
                            (match ps with
                             | [] -> Ok (T_option r)
                             | _ :: _ -> Error (W_bad_operand t))
                        | T_f64 | T_bool | T_string | T_unit | T_option _
                        | T_result _ | T_tuple _ | T_async_fn _
                        | T_future _ | T_signal _ ->
                            Error (W_bad_operand t)))
            | [] -> Error (W_arity (1, 0))
            | _ :: _ :: _ -> Error (W_arity (1, len args)))
       | T_f64 | T_string | T_unit | T_option _ | T_result _ | T_tuple _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ ->
           Error (W_bad_method recv))
  | M_then_some ->
      (match recv with
       | T_bool ->
           (match args with
            | arg :: [] ->
                Result.bind (infer ctx arg) (fun sh ->
                    Result.bind (value_ty sh) (fun t -> Ok (T_option t)))
            | [] -> Error (W_arity (1, 0))
            | _ :: _ :: _ -> Error (W_arity (1, len args)))
       | T_f64 | T_string | T_unit | T_option _ | T_result _ | T_tuple _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ ->
           Error (W_bad_method recv))
  | M_len -> on_string ctx recv args [] T_f64
  | M_is_empty -> on_string ctx recv args [] T_bool
  | M_trim -> on_string ctx recv args [] T_string
  | M_trim_start -> on_string ctx recv args [] T_string
  | M_trim_end -> on_string ctx recv args [] T_string
  | M_to_owned -> on_string ctx recv args [] T_string
  | M_starts_with -> on_string ctx recv args (T_string :: []) T_bool
  | M_ends_with -> on_string ctx recv args (T_string :: []) T_bool
  | M_contains -> on_string ctx recv args (T_string :: []) T_bool
  | M_is_some ->
      on_option ctx recv args [] (fun _ -> T_bool)
  | M_is_none ->
      on_option ctx recv args [] (fun _ -> T_bool)
  | M_is_ok -> on_result ctx recv args [] (fun _ e -> ignore2 e T_bool)
  | M_is_err -> on_result ctx recv args [] (fun _ e -> ignore2 e T_bool)
  | M_ok -> on_result ctx recv args [] (fun a e -> ignore2 e (T_option a))
  | M_err -> on_result ctx recv args [] (fun a e -> ignore2 a (T_option e))
  | M_unwrap_err ->
      on_result ctx recv args [] (fun a e -> ignore2 a e)
  | M_expect_err ->
      on_result ctx recv args (T_string :: []) (fun a e -> ignore2 a e)
  | M_unwrap ->
      (match recv with
       | T_option a -> Result.bind (check_args ctx [] args) (fun _ -> Ok a)
       | T_result (a, _) ->
           Result.bind (check_args ctx [] args) (fun _ -> Ok a)
       | T_f64 | T_bool | T_string | T_unit | T_tuple _ | T_fn _
       | T_async_fn _ | T_future _ | T_signal _ ->
           Error (W_bad_method recv))
  | M_expect ->
      (match recv with
       | T_option a ->
           Result.bind (check_args ctx (T_string :: []) args) (fun _ ->
               Ok a)
       | T_result (a, _) ->
           Result.bind (check_args ctx (T_string :: []) args) (fun _ ->
               Ok a)
       | T_f64 | T_bool | T_string | T_unit | T_tuple _ | T_fn _
       | T_async_fn _ | T_future _ | T_signal _ ->
           Error (W_bad_method recv))
  | M_get -> on_signal ctx recv args [] (fun a -> a)
  | M_set ->
      (match recv with
       | T_signal a ->
           Result.bind (check_args ctx (a :: []) args) (fun _ -> Ok T_unit)
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
       | T_tuple _ | T_fn _ | T_async_fn _ | T_future _ ->
           Error (W_bad_method recv))
  | M_toggle ->
      (match recv with
       | T_signal a ->
           if ty_eq a T_bool then
             Result.bind (check_args ctx [] args) (fun _ -> Ok T_unit)
           else Error (W_bad_method recv)
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
       | T_tuple _ | T_fn _ | T_async_fn _ | T_future _ ->
           Error (W_bad_method recv))
  | M_increment -> on_signal_of ctx recv args T_f64
  | M_decrement -> on_signal_of ctx recv args T_f64
  | M_push_str ->
      (match recv with
       | T_signal a ->
           if ty_eq a T_string then
             Result.bind (check_args ctx (T_string :: []) args) (fun _ ->
                 Ok T_unit)
           else Error (W_bad_method recv)
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
       | T_tuple _ | T_fn _ | T_async_fn _ | T_future _ ->
           Error (W_bad_method recv))
  | M_clone -> Result.bind (check_args ctx [] args) (fun _ -> Ok recv)

and on_string ctx recv args expected ret =
  match recv with
  | T_string ->
      Result.bind (check_args ctx expected args) (fun _ -> Ok ret)
  | T_f64 | T_bool | T_unit | T_option _ | T_result _ | T_tuple _
  | T_fn _ | T_async_fn _ | T_future _ | T_signal _ ->
      Error (W_bad_method recv)

and on_option ctx recv args expected k =
  match recv with
  | T_option a ->
      Result.bind (check_args ctx expected args) (fun _ -> Ok (k a))
  | T_f64 | T_bool | T_string | T_unit | T_result _ | T_tuple _ | T_fn _
  | T_async_fn _ | T_future _ | T_signal _ -> Error (W_bad_method recv)

and on_result ctx recv args expected k =
  match recv with
  | T_result (a, e) ->
      Result.bind (check_args ctx expected args) (fun _ -> Ok (k a e))
  | T_f64 | T_bool | T_string | T_unit | T_option _ | T_tuple _ | T_fn _
  | T_async_fn _ | T_future _ | T_signal _ -> Error (W_bad_method recv)

and on_signal ctx recv args expected k =
  match recv with
  | T_signal a ->
      Result.bind (check_args ctx expected args) (fun _ -> Ok (k a))
  | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
  | T_tuple _ | T_fn _ | T_async_fn _ | T_future _ ->
      Error (W_bad_method recv)

and on_signal_of ctx recv args elem =
  match recv with
  | T_signal a ->
      if ty_eq a elem then
        Result.bind (check_args ctx [] args) (fun _ -> Ok T_unit)
      else Error (W_bad_method recv)
  | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
  | T_tuple _ | T_fn _ | T_async_fn _ | T_future _ ->
      Error (W_bad_method recv)

(* Helper: consume one value, return the other; keeps the on_result
   continuations free of unused-variable warnings without wildcards
   in binding position. *)
and ignore2 _x y = y

(* Top-level entry: a generated expression is checked in an
   environment of pre-bound variables (signals and inputs), outside
   any loop or closure. *)
let check_top env e =
  Result.bind (infer { env; in_loop = false; ret = R_top; in_async = false } e)
    (fun sh ->
      match sh with
      | Sh_ty t -> Ok t
      | Sh_never -> Error W_never_at_top)
