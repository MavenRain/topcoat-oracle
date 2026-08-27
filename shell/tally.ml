(* M18: constructor tally over generated samples (DESIGN.md Phase C).
   Counts every AST constructor a sample set exercises, keyed by the
   constructor's source name. The M18 gate asserts each reachable
   constructor appears at N=10k and each excluded constructor stays
   at zero; the report string is the counter report. *)

open Ast

let bump k m =
  Option.fold
    ~none:((k, 1) :: m)
    ~some:(fun n -> (k, n + 1) :: List.remove_assoc k m)
    (List.assoc_opt k m)

let count k m = Option.fold ~none:0 ~some:(fun n -> n) (List.assoc_opt k m)

let lit_name l =
  match l with
  | L_f64_bits _ -> "L_f64_bits"
  | L_bool _ -> "L_bool"
  | L_str _ -> "L_str"

let unop_name o =
  match o with
  | U_neg -> "U_neg"
  | U_not -> "U_not"
  | U_deref -> "U_deref"

let binop_name o =
  match o with
  | B_add -> "B_add"
  | B_sub -> "B_sub"
  | B_mul -> "B_mul"
  | B_div -> "B_div"
  | B_eq -> "B_eq"
  | B_ne -> "B_ne"
  | B_lt -> "B_lt"
  | B_le -> "B_le"
  | B_gt -> "B_gt"
  | B_ge -> "B_ge"

let meth_name m =
  match m with
  | M_then -> "M_then"
  | M_then_some -> "M_then_some"
  | M_len -> "M_len"
  | M_is_empty -> "M_is_empty"
  | M_trim -> "M_trim"
  | M_trim_start -> "M_trim_start"
  | M_trim_end -> "M_trim_end"
  | M_starts_with -> "M_starts_with"
  | M_ends_with -> "M_ends_with"
  | M_contains -> "M_contains"
  | M_to_owned -> "M_to_owned"
  | M_is_some -> "M_is_some"
  | M_is_none -> "M_is_none"
  | M_is_ok -> "M_is_ok"
  | M_is_err -> "M_is_err"
  | M_ok -> "M_ok"
  | M_err -> "M_err"
  | M_unwrap_err -> "M_unwrap_err"
  | M_expect_err -> "M_expect_err"
  | M_unwrap -> "M_unwrap"
  | M_expect -> "M_expect"
  | M_get -> "M_get"
  | M_set -> "M_set"
  | M_toggle -> "M_toggle"
  | M_increment -> "M_increment"
  | M_decrement -> "M_decrement"
  | M_push_str -> "M_push_str"
  | M_clone -> "M_clone"

let rec expr_walk acc e =
  match e with
  | E_lit l -> bump (lit_name l) (bump "E_lit" acc)
  | E_var _ -> bump "E_var" acc
  | E_unary (o, a) -> expr_walk (bump (unop_name o) (bump "E_unary" acc)) a
  | E_binary (o, a, b) ->
      expr_walk (expr_walk (bump (binop_name o) (bump "E_binary" acc)) a) b
  | E_tuple es -> List.fold_left expr_walk (bump "E_tuple" acc) es
  | E_some a -> expr_walk (bump "E_some" acc) a
  | E_none _ -> bump "E_none" acc
  | E_ok (a, _) -> expr_walk (bump "E_ok" acc) a
  | E_err (a, _) -> expr_walk (bump "E_err" acc) a
  | E_call (f, args) ->
      List.fold_left expr_walk (expr_walk (bump "E_call" acc) f) args
  | E_method (r, m, args) ->
      List.fold_left expr_walk
        (expr_walk (bump (meth_name m) (bump "E_method" acc)) r)
        args
  | E_field (a, _) -> expr_walk (bump "E_field" acc) a
  | E_index (a, b) -> expr_walk (expr_walk (bump "E_index" acc) a) b
  | E_let (_, a) -> expr_walk (bump "E_let" acc) a
  | E_block (ss, tail) ->
      expr_walk (List.fold_left expr_walk (bump "E_block" acc) ss) tail
  | E_block_unit ss -> List.fold_left expr_walk (bump "E_block_unit" acc) ss
  | E_if (c, t1) -> expr_walk (expr_walk (bump "E_if" acc) c) t1
  | E_if_else (c, t1, e1) ->
      expr_walk (expr_walk (expr_walk (bump "E_if_else" acc) c) t1) e1
  | E_loop b -> expr_walk (bump "E_loop" acc) b
  | E_while (c, b) -> expr_walk (expr_walk (bump "E_while" acc) c) b
  | E_break -> bump "E_break" acc
  | E_continue -> bump "E_continue" acc
  | E_return_unit -> bump "E_return_unit" acc
  | E_return a -> expr_walk (bump "E_return" acc) a
  | E_closure (_, _, b) -> expr_walk (bump "E_closure" acc) b
  | E_async_closure (_, _, b) -> expr_walk (bump "E_async_closure" acc) b
  | E_await a -> expr_walk (bump "E_await" acc) a

let rec ty_walk acc t =
  match t with
  | T_f64 -> bump "T_f64" acc
  | T_bool -> bump "T_bool" acc
  | T_string -> bump "T_string" acc
  | T_unit -> bump "T_unit" acc
  | T_option a -> ty_walk (bump "T_option" acc) a
  | T_result (a, e) -> ty_walk (ty_walk (bump "T_result" acc) a) e
  | T_tuple ts -> List.fold_left ty_walk (bump "T_tuple" acc) ts
  | T_fn (ps, r) -> ty_walk (List.fold_left ty_walk (bump "T_fn" acc) ps) r
  | T_async_fn (ps, r) ->
      ty_walk (List.fold_left ty_walk (bump "T_async_fn" acc) ps) r
  | T_future a -> ty_walk (bump "T_future" acc) a
  | T_signal a -> ty_walk (bump "T_signal" acc) a

(* A sample is (target type, expression); the walk covers both. *)
let of_samples samples =
  List.fold_left
    (fun acc s -> ty_walk (expr_walk acc (snd s)) (fst s))
    [] samples

let report m =
  let sorted = List.sort (fun a b -> compare (fst a) (fst b)) m in
  List.fold_left
    (fun acc kv -> acc ^ fst kv ^ " " ^ string_of_int (snd kv) ^ "\n")
    "" sorted
