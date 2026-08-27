(* AST for the topcoat expr! vocabulary, pinned at 51caa01d (v0.6.2).
   Evidence for the construct set: research/study-topcoat.md sections
   on expr_lit/expr_binary/expr_unary/expr_call/expr_method_call and
   macro/docs/expr.md:41-51.

   f64 values are IEEE-754 binary64 bit patterns carried as a
   (hi32, lo32) pair of non-negative ints: OCaml's native int is
   63-bit, so a single int cannot hold the full 64-bit pattern
   (deviation from the DESIGN.md sketch "F64_bits of int", recorded
   there). Both halves are in [0, 0xFFFF_FFFF]. *)

open Prelude

type ty =
  | T_f64
  | T_bool
  | T_string
  | T_unit
  | T_option of ty
  | T_result of ty * ty
  | T_tuple of ty list
  | T_fn of ty list * ty
  | T_async_fn of ty list * ty
  | T_future of ty
  | T_signal of ty

type lit =
  | L_f64_bits of int * int
  | L_bool of bool
  | L_str of string

type unop =
  | U_neg
  | U_not
  | U_deref

type binop =
  | B_add
  | B_sub
  | B_mul
  | B_div
  | B_eq
  | B_ne
  | B_lt
  | B_le
  | B_gt
  | B_ge

(* Closed method vocabulary (macro/docs/expr.md:41-51 plus the
   duck-typed clone risk class). Operators are NOT methods here even
   though the JS half spells them .add()/.eq()/...: the AST keeps
   them as unop/binop. *)
type meth =
  (* bool *)
  | M_then
  | M_then_some
  (* String / &str *)
  | M_len
  | M_is_empty
  | M_trim
  | M_trim_start
  | M_trim_end
  | M_starts_with
  | M_ends_with
  | M_contains
  | M_to_owned
  (* Option *)
  | M_is_some
  | M_is_none
  (* Result *)
  | M_is_ok
  | M_is_err
  | M_ok
  | M_err
  | M_unwrap_err
  | M_expect_err
  (* Option and Result *)
  | M_unwrap
  | M_expect
  (* Signal *)
  | M_get
  | M_set
  | M_toggle
  | M_increment
  | M_decrement
  | M_push_str
  (* duck-typed, any receiver *)
  | M_clone

(* Rust infers the elided side of Option/Result constructors from
   context; the reference leg cannot, so E_none / E_ok / E_err carry
   the type annotation the printer omits (except None::<T>, the one
   turbofish the macro accepts). Blocks, if, and return come in
   value-tail and unit form as separate constructors so no payload is
   an option. Closures carry their return type: the generator is
   type-directed and wf needs it to check E_return. *)
(* Variables are int ids, not names: the environment then needs only
   int equality, so core/ never compares strings (the ZxCaml String
   surface has no total equality). The printer renders id n as "vn". *)
type expr =
  | E_lit of lit
  | E_var of int
  | E_unary of unop * expr
  | E_binary of binop * expr * expr
  | E_tuple of expr list
  | E_some of expr
  | E_none of ty (* element type *)
  | E_ok of expr * ty (* payload, error-side type *)
  | E_err of expr * ty (* payload, ok-side type *)
  | E_call of expr * expr list
  | E_method of expr * meth * expr list
  | E_field of expr * int (* tuple projection .0 / .1 / ... *)
  | E_index of expr * expr
  | E_let of int * expr
  | E_block of expr list * expr (* statements, value tail *)
  | E_block_unit of expr list (* statements, no tail *)
  | E_if of expr * expr (* no else: unit *)
  | E_if_else of expr * expr * expr
  | E_loop of expr
  | E_while of expr * expr
  | E_break
  | E_continue
  | E_return_unit
  | E_return of expr
  | E_closure of (int * ty) list * ty * expr (* params, return, body *)
  | E_async_closure of (int * ty) list * ty * expr
  | E_await of expr

let rec ty_eq a b =
  match a with
  | T_f64 ->
      (match b with
       | T_f64 -> true
       | T_bool | T_string | T_unit | T_option _ | T_result _ | T_tuple _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> false)
  | T_bool ->
      (match b with
       | T_bool -> true
       | T_f64 | T_string | T_unit | T_option _ | T_result _ | T_tuple _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> false)
  | T_string ->
      (match b with
       | T_string -> true
       | T_f64 | T_bool | T_unit | T_option _ | T_result _ | T_tuple _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> false)
  | T_unit ->
      (match b with
       | T_unit -> true
       | T_f64 | T_bool | T_string | T_option _ | T_result _ | T_tuple _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> false)
  | T_option a1 ->
      (match b with
       | T_option b1 -> ty_eq a1 b1
       | T_f64 | T_bool | T_string | T_unit | T_result _ | T_tuple _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> false)
  | T_result (a1, a2) ->
      (match b with
       | T_result (b1, b2) -> ty_eq a1 b1 && ty_eq a2 b2
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_tuple _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> false)
  | T_tuple xs ->
      (match b with
       | T_tuple ys -> list_eq ty_eq xs ys
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
       | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> false)
  | T_fn (ps, r) ->
      (match b with
       | T_fn (qs, s) -> list_eq ty_eq ps qs && ty_eq r s
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
       | T_tuple _ | T_async_fn _ | T_future _ | T_signal _ -> false)
  | T_async_fn (ps, r) ->
      (match b with
       | T_async_fn (qs, s) -> list_eq ty_eq ps qs && ty_eq r s
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
       | T_tuple _ | T_fn _ | T_future _ | T_signal _ -> false)
  | T_future a1 ->
      (match b with
       | T_future b1 -> ty_eq a1 b1
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
       | T_tuple _ | T_fn _ | T_async_fn _ | T_signal _ -> false)
  | T_signal a1 ->
      (match b with
       | T_signal b1 -> ty_eq a1 b1
       | T_f64 | T_bool | T_string | T_unit | T_option _ | T_result _
       | T_tuple _ | T_fn _ | T_async_fn _ | T_future _ -> false)

let rec ty_to_string t =
  match t with
  | T_f64 -> "f64"
  | T_bool -> "bool"
  | T_string -> "String"
  | T_unit -> "()"
  | T_option t1 -> "Option<" ^ ty_to_string t1 ^ ">"
  | T_result (t1, t2) ->
      "Result<" ^ ty_to_string t1 ^ ", " ^ ty_to_string t2 ^ ">"
  | T_tuple ts ->
      "(" ^ concat (map (fun t1 -> ty_to_string t1 ^ ",") ts)
      ^ ")"
  | T_fn (ps, r) ->
      "Fn(" ^ concat (map (fun t1 -> ty_to_string t1 ^ ",") ps)
      ^ ") -> " ^ ty_to_string r
  | T_async_fn (ps, r) ->
      "AsyncFn("
      ^ concat (map (fun t1 -> ty_to_string t1 ^ ",") ps)
      ^ ") -> " ^ ty_to_string r
  | T_future t1 -> "Future<" ^ ty_to_string t1 ^ ">"
  | T_signal t1 -> "Signal<" ^ ty_to_string t1 ^ ">"
