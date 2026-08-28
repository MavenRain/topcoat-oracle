(* M19 type-preserving shrinker (DESIGN.md Phase C). Every candidate
   this module offers for an expression e well-formed at target type
   t is (a) strictly smaller under `size`, so shrink chains
   terminate, and (b) well-formed at the SAME t in the SAME context.
   The rules are type- and scope-preserving BY CONSTRUCTION and the
   module never consults Wf, so the M19 gate's independent wf
   re-check (test/test_shrink.ml) keeps its teeth.

   Soundness inventory, one line per rule family:
   - collapse: `minimal t` is closed and value-shaped (no vars, no
     break/continue/return/await at its own level), so it is wf at t
     in every context; guarded by a strict size decrease.
   - extraction (operand, branch, tail, thunk body, receiver): the
     candidate is a strict subterm kept AT THE SAME position, so the
     surrounding loop/closure/async context is unchanged. Never-shaped
     subterms are never hoisted: generated never-forms sit only in
     loop-body statement suffixes and closure tails (shell/gen.ml),
     positions these rules do not extract from, and no rule introduces
     a new never-form.
   - statement drop: a block statement's value is discarded
     (Wf.infer_block, Sc_expr) and only a let extends the block
     environment, so a let drops only when its id is not mentioned
     later in the block (conservative over shadowing).
   - loop-body extraction is guarded on `escapes_loop`; thunk-call
     body extraction on an empty parameter list (no param capture)
     and `has_return` (no return escaping its closure).
   - rewrap: children recurse only at positions whose type is
     syntactically determined (operator operands, constructor
     payloads, closure bodies, literal-callee arguments), replacing
     value-shaped children with value-shaped children.
   - return: the enclosing closure's declared return type is now
     threaded through the recursion (`ret`, reset to `Some r` at each
     closure body); the E_return rules fire only when the position's
     target type equals it, since never-coercion can otherwise carry
     a return into a type-changing position where Wf checks the
     payload against `ret`, not the local target `t`. *)

open Prelude
open Ast

let exists p xs = fold (fun acc x -> acc || p x) false xs

(* Direct sub-expressions, one arm per constructor. Traversals that
   must stop at binders (loops, closures) refine their own arms
   instead of using this. *)
let children e =
  match e with
  | E_lit _ | E_var _ | E_none _ | E_break | E_continue | E_return_unit ->
      []
  | E_unary (_, a)
  | E_some a
  | E_ok (a, _)
  | E_err (a, _)
  | E_field (a, _)
  | E_let (_, a)
  | E_loop a
  | E_return a
  | E_closure (_, _, a)
  | E_async_closure (_, _, a)
  | E_await a -> a :: []
  | E_binary (_, a, b) | E_index (a, b) | E_if (a, b) | E_while (a, b) ->
      a :: b :: []
  | E_if_else (a, b, c) -> a :: b :: c :: []
  | E_tuple es | E_block_unit es -> es
  | E_block (stmts, tail) -> append stmts (tail :: [])
  | E_call (f, args) -> f :: args
  | E_method (recv, _, args) -> recv :: args

(* Payload weight beyond the node itself, so literal content shrinks
   strictly too (nonzero f64 bits, true, nonempty strings). *)
let own_weight e =
  match e with
  | E_lit l ->
      (match l with
       | L_f64_bits (hi, lo) -> if hi = 0 && lo = 0 then 0 else 1
       | L_bool b -> if b then 1 else 0
       | L_str s -> String.length s)
  | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _ | E_none _
  | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _ | E_index _
  | E_let _ | E_block _ | E_block_unit _ | E_if _ | E_if_else _
  | E_loop _ | E_while _ | E_break | E_continue | E_return_unit
  | E_return _ | E_closure _ | E_async_closure _ | E_await _ -> 0

let rec size e =
  1 + own_weight e + fold (fun acc c -> acc + size c) 0 (children e)

(* Conservative occurrence check for a variable id: any use OR any
   rebinding anywhere below counts, so shadowed uses still keep an
   outer binding (sound for the statement-drop guard). *)
let rec mentions x e =
  let here =
    match e with
    | E_var y -> y = x
    | E_let (y, _) -> y = x
    | E_lit _ | E_unary _ | E_binary _ | E_tuple _ | E_some _ | E_none _
    | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _ | E_index _
    | E_block _ | E_block_unit _ | E_if _ | E_if_else _ | E_loop _
    | E_while _ | E_break | E_continue | E_return_unit | E_return _
    | E_closure _ | E_async_closure _ | E_await _ -> false
  in
  here || exists (mentions x) (children e)

(* A top-level break/continue that would bind to the ENCLOSING loop:
   descends value positions but not nested loop bodies (their own loop
   binds them) or closure bodies (wf resets in_loop there). A while
   condition sits at the enclosing level; its body does not. *)
let rec escapes_loop e =
  match e with
  | E_break | E_continue -> true
  | E_loop _ | E_closure _ | E_async_closure _ -> false
  | E_while (c, _) -> escapes_loop c
  | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
  | E_none _ | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _
  | E_index _ | E_let _ | E_block _ | E_block_unit _ | E_if _
  | E_if_else _ | E_return_unit | E_return _ | E_await _ ->
      exists escapes_loop (children e)

(* A return that would bind to the ENCLOSING closure: does not descend
   into nested closures, whose own R_fn absorbs their returns. *)
let rec has_return e =
  match e with
  | E_return _ | E_return_unit -> true
  | E_closure _ | E_async_closure _ -> false
  | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
  | E_none _ | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _
  | E_index _ | E_let _ | E_block _ | E_block_unit _ | E_if _
  | E_if_else _ | E_loop _ | E_while _ | E_break | E_continue
  | E_await _ -> exists has_return (children e)

(* Shape probes, one exhaustive match each (shell/gen.ml pattern), so
   rule sites stay on Option.fold. *)
let option_elem t =
  match t with
  | T_option a -> Some a
  | T_f64 | T_bool | T_string | T_unit | T_result _ | T_tuple _ | T_fn _
  | T_async_fn _ | T_future _ | T_signal _ -> None

let result_sides t =
  match t with
  | T_result (a, e) -> Some (a, e)
  | T_f64 | T_bool | T_string | T_unit | T_option _ | T_tuple _ | T_fn _
  | T_async_fn _ | T_future _ | T_signal _ -> None

(* Literal callee: its own type paired with its parameter types, both
   syntactically known. *)
let callee_shape f =
  match f with
  | E_closure (ps, r, _) -> Some (T_fn (map snd ps, r), map snd ps)
  | E_async_closure (ps, r, _) -> Some (T_async_fn (map snd ps, r), map snd ps)
  | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
  | E_none _ | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _
  | E_index _ | E_let _ | E_block _ | E_block_unit _ | E_if _
  | E_if_else _ | E_loop _ | E_while _ | E_break | E_continue
  | E_return_unit | E_return _ | E_await _ -> None

(* Body of a parameterless sync closure: nothing to capture, so the
   body may replace a call of it (return guard applied at the site). *)
let thunk_body f =
  match f with
  | E_closure (ps, _, body) ->
      (match ps with [] -> Some body | _ :: _ -> None)
  | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
  | E_none _ | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _
  | E_index _ | E_let _ | E_block _ | E_block_unit _ | E_if _
  | E_if_else _ | E_loop _ | E_while _ | E_break | E_continue
  | E_return_unit | E_return _ | E_async_closure _ | E_await _ -> None

let async_thunk_body f =
  match f with
  | E_async_closure (ps, _, body) ->
      (match ps with [] -> Some body | _ :: _ -> None)
  | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
  | E_none _ | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _
  | E_index _ | E_let _ | E_block _ | E_block_unit _ | E_if _
  | E_if_else _ | E_loop _ | E_while _ | E_break | E_continue
  | E_return_unit | E_return _ | E_closure _ | E_await _ -> None

let call_parts e =
  match e with
  | E_call (f, args) -> Some (f, args)
  | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
  | E_none _ | E_ok _ | E_err _ | E_method _ | E_field _ | E_index _
  | E_let _ | E_block _ | E_block_unit _ | E_if _ | E_if_else _
  | E_loop _ | E_while _ | E_break | E_continue | E_return_unit
  | E_return _ | E_closure _ | E_async_closure _ | E_await _ -> None

let or_opt a b = Option.fold ~none:b ~some:(fun x -> Some x) a

(* Parameter idents for a minimal closure: the body is closed, so the
   ids only need to exist; 900000+ keeps them visually apart from
   generated ids in repro output (any ids would be sound). *)
let fresh_params ps =
  rev (fold (fun acc t -> (900000 + len acc, t) :: acc) [] ps)

(* Smallest closed expression of a type, when the type is
   constructible under expr! at all: tuples are not (no
   syn::Expr::Tuple arm, M18 excluded set) and signals only enter
   through the environment. Closed and value-shaped, hence wf at its
   type in every context. *)
let rec minimal t =
  match t with
  | T_f64 -> Some (E_lit (L_f64_bits (0, 0)))
  | T_bool -> Some (E_lit (L_bool false))
  | T_string -> Some (E_lit (L_str ""))
  | T_unit -> Some (E_block_unit [])
  | T_option a -> Some (E_none a)
  | T_result (a, e) ->
      or_opt
        (Option.map (fun m -> E_ok (m, e)) (minimal a))
        (Option.map (fun m -> E_err (m, a)) (minimal e))
  | T_tuple _ -> None
  | T_fn (ps, r) ->
      Option.map (fun m -> E_closure (fresh_params ps, r, m)) (minimal r)
  | T_async_fn (ps, r) ->
      Option.map (fun m -> E_async_closure (fresh_params ps, r, m)) (minimal r)
  | T_future a ->
      Option.map (fun m -> E_call (E_async_closure ([], a, m), [])) (minimal a)
  | T_signal _ -> None

(* Let ids bound by a statement list. *)
let let_ids stmts =
  fold
    (fun acc s ->
      match Wf.classify_stmt s with
      | Wf.Sc_let (x, _) -> x :: acc
      | Wf.Sc_expr -> acc)
    [] stmts

(* One candidate per droppable statement: an expression statement's
   value is discarded so it always drops; a let drops only when its
   id is not mentioned in the rest of the block (`later` carries the
   tail, if any). *)
let rec drop_one stmts later =
  match stmts with
  | [] -> []
  | s :: rest ->
      let ok =
        match Wf.classify_stmt s with
        | Wf.Sc_let (x, _) -> not (exists (mentions x) (append rest later))
        | Wf.Sc_expr -> true
      in
      let here = if ok then rest :: [] else [] in
      append here (map (fun rest' -> s :: rest') (drop_one rest later))

(* Shrink candidates for e well-formed at target type t, most
   aggressive first: whole-node collapse, then extractions and
   statement drops, then child rewraps. Callers uphold "e wf at t";
   on other inputs the result is still total, just uninteresting. *)
let rec go ret t e =
  let collapse =
    Option.fold ~none:[]
      ~some:(fun m -> if size m < size e then m :: [] else [])
      (minimal t)
  in
  append collapse (structural ret t e)

and structural ret t e =
  match e with
  | E_lit _ | E_var _ | E_none _ | E_break | E_continue | E_return_unit ->
      []
  (* unconstructible under expr! (M18 excluded set): no rules *)
  | E_tuple _ | E_field _ | E_index _ -> []
  | E_unary (op, a) ->
      (match op with
       | U_neg -> a :: map (fun a' -> E_unary (U_neg, a')) (go ret T_f64 a)
       | U_not -> a :: map (fun a' -> E_unary (U_not, a')) (go ret T_bool a)
       | U_deref -> [])
  | E_binary (op, a, b) ->
      (match op with
       | B_add | B_sub | B_mul | B_div ->
           a :: b
           :: append
                (map (fun a' -> E_binary (op, a', b)) (go ret T_f64 a))
                (map (fun b' -> E_binary (op, a, b')) (go ret T_f64 b))
       | B_eq | B_ne | B_lt | B_le | B_gt | B_ge ->
           (* comparison operand types are not syntactic (f64, bool or
              string); the collapse rule already covers the node *)
           [])
  | E_some a ->
      Option.fold ~none:[]
        ~some:(fun te -> map (fun a' -> E_some a') (go ret te a))
        (option_elem t)
  | E_ok (a, terr) ->
      Option.fold ~none:[]
        ~some:(fun s -> map (fun a' -> E_ok (a', terr)) (go ret (fst s) a))
        (result_sides t)
  | E_err (a, tok) ->
      Option.fold ~none:[]
        ~some:(fun s -> map (fun a' -> E_err (a', tok)) (go ret (snd s) a))
        (result_sides t)
  | E_call (f, args) ->
      let extract =
        match args with
        | [] ->
            Option.fold ~none:[]
              ~some:(fun b -> if has_return b then [] else b :: [])
              (thunk_body f)
        | _ :: _ -> []
      in
      append extract
        (Option.fold ~none:[]
           ~some:(fun cs ->
             append
               (map (fun f' -> E_call (f', args)) (go ret (fst cs) f))
               (args_cands ret (fun args' -> E_call (f, args')) (snd cs)
                  args))
           (callee_shape f))
  | E_method (recv, m, args) ->
      (match m with
       | M_clone ->
           recv
           :: map (fun r' -> E_method (r', M_clone, args)) (go ret t recv)
       | M_get ->
           map
             (fun r' -> E_method (r', M_get, args))
             (go ret (T_signal t) recv)
       | M_then | M_then_some | M_len | M_is_empty | M_trim | M_trim_start
       | M_trim_end | M_starts_with | M_ends_with | M_contains | M_to_owned
       | M_is_some | M_is_none | M_is_ok | M_is_err | M_ok | M_err
       | M_unwrap_err | M_expect_err | M_unwrap | M_expect | M_set
       | M_toggle | M_increment | M_decrement | M_push_str ->
           (* receiver type is not syntactic; collapse covers the node *)
           [])
  | E_let (_, _) ->
      (* statement position only in generated code; statement-level
         shrinking lives in the block arms *)
      []
  | E_block (stmts, tail) ->
      let unwrap =
        if exists (fun x -> mentions x tail) (let_ids stmts) then []
        else tail :: []
      in
      append unwrap
        (append
           (map (fun stmts' -> E_block (stmts', tail))
              (drop_one stmts (tail :: [])))
           (map (fun tl' -> E_block (stmts, tl')) (go ret t tail)))
  | E_block_unit stmts ->
      map (fun stmts' -> E_block_unit stmts') (drop_one stmts [])
  | E_if (c, thn) ->
      thn
      :: append
           (map (fun c' -> E_if (c', thn)) (go ret T_bool c))
           (map (fun th' -> E_if (c, th')) (go ret T_unit thn))
  | E_if_else (c, a, b) ->
      a :: b
      :: append
           (map (fun c' -> E_if_else (c', a, b)) (go ret T_bool c))
           (append
              (map (fun a' -> E_if_else (c, a', b)) (go ret t a))
              (map (fun b' -> E_if_else (c, a, b')) (go ret t b)))
  | E_loop body ->
      let extract = if escapes_loop body then [] else body :: [] in
      append extract (map (fun b' -> E_loop b') (go ret T_unit body))
  | E_while (c, body) ->
      let extract = if escapes_loop body then [] else body :: [] in
      append extract
        (append
           (map (fun c' -> E_while (c', body)) (go ret T_bool c))
           (map (fun b' -> E_while (c, b')) (go ret T_unit body)))
  | E_return a ->
      (* wf checks the payload against the enclosing closure's return
         type, not the position's target; never-coercion can carry a
         return into a type-changing position, so these rules fire
         only when the two agree *)
      Option.fold ~none:[]
        ~some:(fun r ->
          if ty_eq t r then a :: map (fun a' -> E_return a') (go ret t a)
          else [])
        ret
  | E_closure (ps, r, body) ->
      map (fun b' -> E_closure (ps, r, b')) (go (Some r) r body)
  | E_async_closure (ps, r, body) ->
      map (fun b' -> E_async_closure (ps, r, b')) (go (Some r) r body)
  | E_await a ->
      let direct =
        Option.fold ~none:[]
          ~some:(fun fa ->
            match snd fa with
            | [] ->
                Option.fold ~none:[]
                  ~some:(fun b -> if has_return b then [] else b :: [])
                  (async_thunk_body (fst fa))
            | _ :: _ -> [])
          (call_parts a)
      in
      append direct (map (fun a' -> E_await a') (go ret (T_future t) a))

(* Rewrap candidates for a call's arguments, each argument recursed at
   its syntactically known parameter type; `wrap` rebuilds the full
   argument list around the changed element. *)
and args_cands ret wrap tys args =
  match tys with
  | [] -> []
  | t1 :: trest ->
      (match args with
       | [] -> []
       | a :: arest ->
           append
             (map (fun a' -> wrap (a' :: arest)) (go ret t1 a))
             (args_cands ret (fun rest' -> wrap (a :: rest')) trest arest))

let cands t e = go None t e
