(* AST to Rust expression text accepted by the topcoat expr! macro
   (M13). The macro parses the full syn::Expr grammar and whitelists
   shapes during lowering (grammar/src/expr.rs:134-158 dispatch), so
   the printer targets exactly that surface:
   - syn::Expr::Paren IS dispatched (expr/expr_paren.rs) and lowers
     to parens on both the Rust and JS halves, so the printer
     parenthesizes non-atomic sub-expressions at every use site
     instead of reasoning about precedence.
   - Tuple EXPRESSIONS have no dispatch arm: `(a, b)` and the bare
     unit `()` are rejected with "unsupported expression" even though
     tuple types are vocabulary (values enter via hydrated bindings
     and leave via .0 projection). E_tuple still prints its natural
     Rust text so the printer stays total; the generator gives it
     weight zero, and M20 printer-soundness catches any leak.
   - Float literals are the injected renderer's job: Rust Debug form
     ("1.0", "1e300", "-0.0") is always a valid f64-literal token
     (possibly under unary minus), while Display form ("1") would be
     an integer literal, which expr_lit.rs rejects. NaN and the
     infinities have no literal spelling; the renderer's output for
     them will not compile under expr! by design.
   - A `let` outside statement position has no Rust expression form;
     it prints as the one-statement unit block `{ let vn = e; }`,
     matching its wf type (unit, binds nothing downstream).
   ZxCaml subset: core/ never inspects string contents, so both
   literal renderers arrive as injected closures from the shell. *)

open Prelude
open Ast

type renderer = {
  lit_f64 : int -> int -> string; (* hi32 lo32 -> literal text, sign included *)
  lit_str : string -> string; (* Rust string literal, quotes included *)
}

let unop_str op =
  match op with
  | U_neg -> "-"
  | U_not -> "!"
  | U_deref -> "*"

let binop_str op =
  match op with
  | B_add -> " + "
  | B_sub -> " - "
  | B_mul -> " * "
  | B_div -> " / "
  | B_eq -> " == "
  | B_ne -> " != "
  | B_lt -> " < "
  | B_le -> " <= "
  | B_gt -> " > "
  | B_ge -> " >= "

let meth_name m =
  match m with
  | M_then -> "then"
  | M_then_some -> "then_some"
  | M_len -> "len"
  | M_is_empty -> "is_empty"
  | M_trim -> "trim"
  | M_trim_start -> "trim_start"
  | M_trim_end -> "trim_end"
  | M_starts_with -> "starts_with"
  | M_ends_with -> "ends_with"
  | M_contains -> "contains"
  | M_to_owned -> "to_owned"
  | M_is_some -> "is_some"
  | M_is_none -> "is_none"
  | M_is_ok -> "is_ok"
  | M_is_err -> "is_err"
  | M_ok -> "ok"
  | M_err -> "err"
  | M_unwrap_err -> "unwrap_err"
  | M_expect_err -> "expect_err"
  | M_unwrap -> "unwrap"
  | M_expect -> "expect"
  | M_get -> "get"
  | M_set -> "set"
  | M_toggle -> "toggle"
  | M_increment -> "increment"
  | M_decrement -> "decrement"
  | M_push_str -> "push_str"
  | M_clone -> "clone"

let var_str n = "v" ^ nat_to_string n

(* Atomic = safe unparenthesized in operand, receiver, and callee
   position. Postfix chains (call, method, field, index, .await) and
   the constructor calls stay bare; anything operator-headed,
   block-headed, or statement-like gets parens at use sites. f64
   literals are non-atomic because the rendered text may start with a
   sign. E_call's callee position is the one spot where parens would
   CHANGE meaning (Some/Ok/Err are special-cased single-segment
   paths), but those are separate constructors here, never E_call
   callees. *)
let atomic e =
  match e with
  | E_var _ -> true
  | E_lit l ->
      (match l with
       | L_f64_bits (_, _) -> false
       | L_bool _ -> true
       | L_str _ -> true)
  | E_some _ | E_none _ | E_ok (_, _) | E_err (_, _) -> true
  | E_call (_, _) | E_method (_, _, _) | E_field (_, _)
  | E_index (_, _) | E_await _ -> true
  | E_tuple _ -> true (* prints with its own parens *)
  | E_unary (_, _) | E_binary (_, _, _) | E_closure (_, _, _)
  | E_async_closure (_, _, _) | E_let (_, _) | E_block (_, _)
  | E_block_unit _ | E_if (_, _) | E_if_else (_, _, _) | E_loop _
  | E_while (_, _) | E_break | E_continue | E_return_unit
  | E_return _ -> false

let rec print r e =
  match e with
  | E_lit l ->
      (match l with
       | L_f64_bits (hi, lo) -> r.lit_f64 hi lo
       | L_bool b -> if b then "true" else "false"
       | L_str s -> r.lit_str s)
  | E_var n -> var_str n
  | E_unary (op, e1) -> unop_str op ^ atomize r e1
  | E_binary (op, a, b) -> atomize r a ^ binop_str op ^ atomize r b
  | E_tuple es ->
      (match es with
       | [] -> "()"
       | e1 :: [] -> "(" ^ print r e1 ^ ",)"
       | _ :: _ :: _ -> "(" ^ joined ", " (map (print r) es) ^ ")")
  | E_some e1 -> "Some(" ^ print r e1 ^ ")"
  | E_none t -> "None::<" ^ ty_to_string t ^ ">"
  | E_ok (e1, _) -> "Ok(" ^ print r e1 ^ ")"
  | E_err (e1, _) -> "Err(" ^ print r e1 ^ ")"
  | E_call (f, args) ->
      atomize r f ^ "(" ^ joined ", " (map (print r) args) ^ ")"
  | E_method (recv, m, args) ->
      atomize r recv ^ "." ^ meth_name m ^ "("
      ^ joined ", " (map (print r) args)
      ^ ")"
  | E_field (e1, i) -> atomize r e1 ^ "." ^ nat_to_string i
  | E_index (a, b) -> atomize r a ^ "[" ^ print r b ^ "]"
  | E_let (x, rhs) -> "{ " ^ let_stmt r x rhs ^ " }"
  | E_block (stmts, tail) ->
      "{ " ^ stmts_text r stmts ^ print r tail ^ " }"
  | E_block_unit stmts ->
      (match stmts with
       | [] -> "{ }"
       | _ :: _ -> "{ " ^ stmts_text r stmts ^ "}")
  | E_if (c, thn) -> "if " ^ atomize r c ^ " " ^ body r thn
  | E_if_else (c, a, b) ->
      "if " ^ atomize r c ^ " " ^ body r a ^ " else " ^ else_part r b
  | E_loop e1 -> "loop " ^ body r e1
  | E_while (c, e1) -> "while " ^ atomize r c ^ " " ^ body r e1
  | E_break -> "break"
  | E_continue -> "continue"
  | E_return_unit -> "return"
  | E_return e1 -> "return " ^ atomize r e1
  | E_closure (ps, ret, e1) ->
      "|" ^ params_text ps ^ "| -> " ^ ty_to_string ret ^ " " ^ body r e1
  | E_async_closure (ps, ret, e1) ->
      "async |" ^ params_text ps ^ "| -> " ^ ty_to_string ret ^ " "
      ^ body r e1
  | E_await e1 -> atomize r e1 ^ ".await"

and atomize r e = if atomic e then print r e else "(" ^ print r e ^ ")"

(* A branch or loop body must be a braced block in Rust source. A
   block-shaped AST node contributes its own braces directly: an
   extra nesting level would lower to an extra JS IIFE, which is not
   semantics-neutral for break/continue crossing. *)
and body r e =
  match e with
  | E_block (_, _) | E_block_unit _ -> print r e
  | E_lit _ | E_var _ | E_unary (_, _) | E_binary (_, _, _) | E_tuple _
  | E_some _ | E_none _ | E_ok (_, _) | E_err (_, _) | E_call (_, _)
  | E_method (_, _, _) | E_field (_, _) | E_index (_, _) | E_let (_, _)
  | E_if (_, _) | E_if_else (_, _, _) | E_loop _ | E_while (_, _)
  | E_break | E_continue | E_return_unit | E_return _
  | E_closure (_, _, _) | E_async_closure (_, _, _) | E_await _ ->
      "{ " ^ print r e ^ " }"

(* syn's else-branch is either a block or another if: chain the
   latter as `else if` so no extra block level appears. *)
and else_part r e =
  match e with
  | E_if (_, _) | E_if_else (_, _, _) -> print r e
  | E_lit _ | E_var _ | E_unary (_, _) | E_binary (_, _, _) | E_tuple _
  | E_some _ | E_none _ | E_ok (_, _) | E_err (_, _) | E_call (_, _)
  | E_method (_, _, _) | E_field (_, _) | E_index (_, _) | E_let (_, _)
  | E_block (_, _) | E_block_unit _ | E_loop _ | E_while (_, _)
  | E_break | E_continue | E_return_unit | E_return _
  | E_closure (_, _, _) | E_async_closure (_, _, _) | E_await _ ->
      body r e

and let_stmt r x rhs = "let " ^ var_str x ^ " = " ^ print r rhs ^ ";"

and stmt_text r s =
  match Wf.classify_stmt s with
  | Wf.Sc_let (x, rhs) -> let_stmt r x rhs
  | Wf.Sc_expr -> print r s ^ ";"

(* Statements rendered with a trailing separator so the tail (or the
   closing brace) can be appended directly. *)
and stmts_text r stmts =
  concat (map (fun s -> stmt_text r s ^ " ") stmts)

and params_text ps =
  joined ", "
    (map (fun p -> var_str (fst p) ^ ": " ^ ty_to_string (snd p)) ps)
