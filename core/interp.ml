(* Reference interpreter for the topcoat expr! AST (M14). Total:
   panics are values (C_panic), fuel exhaustion is a value (C_fuel),
   and wf-rejected or type-stuck shapes map to a P_other panic with a
   stable "stuck:*" code instead of raising. Semantics follow the
   RUST side of the pinned compiler (research/study-topcoat.md):
   IEEE-754 f64 via the injected ops record, byte-length str::len,
   Rust panic message texts, lazy futures (an async closure call
   binds its arguments but defers the body to .await), eager
   then_some / lazy then, and Signal writes applied to a functional
   store keyed by variable id.
   ZxCaml subset: no floats (f64 as (hi32, lo32) bit pairs), no
   exceptions, no string inspection in core (float and string ops
   arrive as one injected closure record from the shell), variables
   are int ids, no tuple patterns in binding position (pairs are
   taken apart with fst/snd). *)

open Prelude
open Ast
open Obs

(* Injected operation record. f64 values are (hi32, lo32) bit pairs
   passed as two curried ints; pair results are projected with
   fst/snd. Comparison ops are IEEE (NaN compares false, -0 == 0);
   the canonical bit-exact channel lives in Obs, not here. String
   receivers are UTF-8 byte strings; cmp is byte order (= code-point
   order), trim strips Rust's White_Space set, debug renders Rust
   Debug form ("1.0", "\"a\\nb\""). *)
type ops = {
  f_add : int -> int -> int -> int -> int * int;
  f_sub : int -> int -> int -> int -> int * int;
  f_mul : int -> int -> int -> int -> int * int;
  f_div : int -> int -> int -> int -> int * int;
  f_neg : int -> int -> int * int;
  f_eq : int -> int -> int -> int -> bool;
  f_lt : int -> int -> int -> int -> bool;
  f_le : int -> int -> int -> int -> bool;
  f_gt : int -> int -> int -> int -> bool;
  f_ge : int -> int -> int -> int -> bool;
  f_of_int : int -> int * int;
  f_display : int -> int -> string;
  f_debug : int -> int -> string;
  str_cmp : string -> string -> int;
  str_debug : string -> string;
  str_trim : string -> string;
  str_trim_start : string -> string;
  str_trim_end : string -> string;
  str_starts_with : string -> string -> bool;
  str_ends_with : string -> string -> bool;
  str_contains : string -> string -> bool;
}

(* Runtime values. Closures capture their defining environment;
   I_future carries the environment with arguments already bound
   (Rust evaluates and moves arguments at the call) plus the deferred
   body. I_signal is a reference into the store by variable id, so
   .clone() on a signal aliases, matching Rust Signal::clone. *)
type ivalue =
  | I_unit
  | I_f64 of int * int
  | I_bool of bool
  | I_str of string
  | I_tuple of ivalue list
  | I_none
  | I_some of ivalue
  | I_ok of ivalue
  | I_err of ivalue
  | I_closure of (int * ty) list * expr * (int * ivalue) list
  | I_async_closure of (int * ty) list * expr * (int * ivalue) list
  | I_future of (int * ivalue) list * expr
  | I_signal of int

type control =
  | C_value of ivalue
  | C_break
  | C_continue
  | C_return of ivalue
  | C_panic of panic_class * string
  | C_fuel

type store = (int * ivalue) list

type step = { ctl : control; store : store; fuel : int }

let value_step v st fu = { ctl = C_value v; store = st; fuel = fu }

let panic_step p msg st fu = { ctl = C_panic (p, msg); store = st; fuel = fu }

(* A shape the type checker rejects, or a type-stuck state that wf
   would have caught: totalized as a P_other panic with a stable
   code. Unreachable when the input passed Wf.check_top. *)
let stuck code st fu = panic_step P_other ("stuck:" ^ code) st fu

let on_value s k =
  match s.ctl with
  | C_value v -> k v s.store s.fuel
  | C_break | C_continue | C_return _ | C_panic (_, _) | C_fuel -> s

(* ---------- shape projections (bool/f64/str/signal or nothing) ---------- *)

let as_f64 v =
  match v with
  | I_f64 (hi, lo) -> Some (hi, lo)
  | I_unit | I_bool _ | I_str _ | I_tuple _ | I_none | I_some _ | I_ok _
  | I_err _ | I_closure (_, _, _) | I_async_closure (_, _, _)
  | I_future (_, _) | I_signal _ -> None

let as_bool v =
  match v with
  | I_bool b -> Some b
  | I_unit | I_f64 (_, _) | I_str _ | I_tuple _ | I_none | I_some _
  | I_ok _ | I_err _ | I_closure (_, _, _) | I_async_closure (_, _, _)
  | I_future (_, _) | I_signal _ -> None

let as_str v =
  match v with
  | I_str s -> Some s
  | I_unit | I_f64 (_, _) | I_bool _ | I_tuple _ | I_none | I_some _
  | I_ok _ | I_err _ | I_closure (_, _, _) | I_async_closure (_, _, _)
  | I_future (_, _) | I_signal _ -> None

let as_signal v =
  match v with
  | I_signal x -> Some x
  | I_unit | I_f64 (_, _) | I_bool _ | I_str _ | I_tuple _ | I_none
  | I_some _ | I_ok _ | I_err _ | I_closure (_, _, _)
  | I_async_closure (_, _, _) | I_future (_, _) -> None

type opt_shape =
  | Op_some of ivalue
  | Op_none
  | Op_not_option

let opt_shape v =
  match v with
  | I_some x -> Op_some x
  | I_none -> Op_none
  | I_unit | I_f64 (_, _) | I_bool _ | I_str _ | I_tuple _ | I_ok _
  | I_err _ | I_closure (_, _, _) | I_async_closure (_, _, _)
  | I_future (_, _) | I_signal _ -> Op_not_option

type res_shape =
  | Rs_ok of ivalue
  | Rs_err of ivalue
  | Rs_not_result

let res_shape v =
  match v with
  | I_ok x -> Rs_ok x
  | I_err x -> Rs_err x
  | I_unit | I_f64 (_, _) | I_bool _ | I_str _ | I_tuple _ | I_none
  | I_some _ | I_closure (_, _, _) | I_async_closure (_, _, _)
  | I_future (_, _) | I_signal _ -> Rs_not_result

(* ---------- store and environment ---------- *)

let int_eq a b = a = b

let rec store_set st x v =
  match st with
  | [] -> (x, v) :: []
  | kv :: rest ->
      if int_eq (fst kv) x then (x, v) :: rest
      else kv :: store_set rest x v

let rec bind_params ps args env =
  match ps with
  | [] -> (match args with [] -> Some env | _ :: _ -> None)
  | p :: ps' ->
      (match args with
       | [] -> None
       | a :: args' -> bind_params ps' args' ((fst p, a) :: env))

(* ---------- Rust Debug rendering of runtime values ---------- *)

(* Used only inside panic message texts, mirroring Rust's
   {:?} payload formatting. Closures, futures, and signals are not
   Debug in Rust (such programs fail rustc, caught by leg M20), so an
   opaque marker keeps this total. *)
let rec debug_value ops v =
  match v with
  | I_unit -> "()"
  | I_f64 (hi, lo) -> ops.f_debug hi lo
  | I_bool b -> if b then "true" else "false"
  | I_str s -> ops.str_debug s
  | I_tuple vs ->
      (match vs with
       | [] -> "()"
       | v1 :: [] -> "(" ^ debug_value ops v1 ^ ",)"
       | _ :: _ :: _ ->
           "(" ^ joined ", " (map (debug_value ops) vs) ^ ")")
  | I_none -> "None"
  | I_some v1 -> "Some(" ^ debug_value ops v1 ^ ")"
  | I_ok v1 -> "Ok(" ^ debug_value ops v1 ^ ")"
  | I_err v1 -> "Err(" ^ debug_value ops v1 ^ ")"
  | I_closure (_, _, _) | I_async_closure (_, _, _) -> "<closure>"
  | I_future (_, _) -> "<future>"
  | I_signal _ -> "<signal>"

(* ---------- equality (wf: eq_comparable = f64/bool/string) ---------- *)

let value_eq ops a b =
  match a with
  | I_f64 (h1, l1) ->
      Option.map (fun p -> ops.f_eq h1 l1 (fst p) (snd p)) (as_f64 b)
  | I_bool x -> Option.map (fun y -> if x then y else not y) (as_bool b)
  | I_str s -> Option.map (fun t -> int_eq (ops.str_cmp s t) 0) (as_str b)
  | I_unit | I_tuple _ | I_none | I_some _ | I_ok _ | I_err _
  | I_closure (_, _, _) | I_async_closure (_, _, _) | I_future (_, _)
  | I_signal _ -> None

(* ---------- evaluator ---------- *)

let rec eval ops env st fuel e =
  if fuel <= 0 then { ctl = C_fuel; store = st; fuel = 0 }
  else
    let fu = fuel - 1 in
    match e with
    | E_lit l ->
        (match l with
         | L_f64_bits (hi, lo) -> value_step (I_f64 (hi, lo)) st fu
         | L_bool b -> value_step (I_bool b) st fu
         | L_str s -> value_step (I_str s) st fu)
    | E_var x ->
        Option.fold
          ~none:(stuck "unbound" st fu)
          ~some:(fun v -> value_step v st fu)
          (assoc_opt int_eq x env)
    | E_unary (op, e1) ->
        on_value (eval ops env st fu e1) (fun v st1 fu1 ->
            match op with
            | U_neg ->
                Option.fold
                  ~none:(stuck "type" st1 fu1)
                  ~some:(fun p ->
                    let q = ops.f_neg (fst p) (snd p) in
                    value_step (I_f64 (fst q, snd q)) st1 fu1)
                  (as_f64 v)
            | U_not ->
                Option.fold
                  ~none:(stuck "type" st1 fu1)
                  ~some:(fun b -> value_step (I_bool (not b)) st1 fu1)
                  (as_bool v)
            | U_deref -> stuck "unsupported" st1 fu1)
    (* Both operands always evaluate, left first: every binop in the
       vocabulary is strict. The grammar has no && / || at all
       (study-topcoat.md section 2), so there is no short-circuit
       case to model here. *)
    | E_binary (op, a, b) ->
        on_value (eval ops env st fu a) (fun va st1 fu1 ->
            on_value (eval ops env st1 fu1 b) (fun vb st2 fu2 ->
                binary_step ops op va vb st2 fu2))
    | E_tuple es ->
        eval_args ops env st fu es (fun vs st1 fu1 ->
            value_step (I_tuple vs) st1 fu1)
    | E_some e1 ->
        on_value (eval ops env st fu e1) (fun v st1 fu1 ->
            value_step (I_some v) st1 fu1)
    | E_none _ -> value_step I_none st fu
    | E_ok (e1, _) ->
        on_value (eval ops env st fu e1) (fun v st1 fu1 ->
            value_step (I_ok v) st1 fu1)
    | E_err (e1, _) ->
        on_value (eval ops env st fu e1) (fun v st1 fu1 ->
            value_step (I_err v) st1 fu1)
    | E_call (f, args) ->
        on_value (eval ops env st fu f) (fun vf st1 fu1 ->
            eval_args ops env st1 fu1 args (fun vs st2 fu2 ->
                apply ops vf vs st2 fu2))
    | E_method (recv, m, args) ->
        on_value (eval ops env st fu recv) (fun vr st1 fu1 ->
            eval_args ops env st1 fu1 args (fun vs st2 fu2 ->
                method_step ops m vr vs st2 fu2))
    | E_field (e1, i) ->
        on_value (eval ops env st fu e1) (fun v st1 fu1 ->
            match v with
            | I_tuple vs ->
                Option.fold
                  ~none:(stuck "field" st1 fu1)
                  ~some:(fun vi -> value_step vi st1 fu1)
                  (nth_opt vs i)
            | I_unit | I_f64 (_, _) | I_bool _ | I_str _ | I_none
            | I_some _ | I_ok _ | I_err _ | I_closure (_, _, _)
            | I_async_closure (_, _, _) | I_future (_, _) | I_signal _ ->
                stuck "field" st1 fu1)
    | E_index (_, _) -> stuck "unsupported" st fu
    | E_let (_, rhs) ->
        (* Outside statement position a let binds nothing downstream;
           the rhs still evaluates for effect (wf types it unit). *)
        on_value (eval ops env st fu rhs) (fun _v st1 fu1 ->
            value_step I_unit st1 fu1)
    | E_block (stmts, tail) ->
        eval_block ops env st fu stmts (fun env' st1 fu1 ->
            eval ops env' st1 fu1 tail)
    | E_block_unit stmts ->
        eval_block ops env st fu stmts (fun _env' st1 fu1 ->
            value_step I_unit st1 fu1)
    | E_if (c, thn) ->
        on_value (eval ops env st fu c) (fun vc st1 fu1 ->
            Option.fold
              ~none:(stuck "type" st1 fu1)
              ~some:(fun b ->
                if b then
                  on_value (eval ops env st1 fu1 thn) (fun _v st2 fu2 ->
                      value_step I_unit st2 fu2)
                else value_step I_unit st1 fu1)
              (as_bool vc))
    | E_if_else (c, a, b) ->
        on_value (eval ops env st fu c) (fun vc st1 fu1 ->
            Option.fold
              ~none:(stuck "type" st1 fu1)
              ~some:(fun cond ->
                if cond then eval ops env st1 fu1 a
                else eval ops env st1 fu1 b)
              (as_bool vc))
    | E_loop body -> eval_loop ops env st fu body
    | E_while (c, body) -> eval_while ops env st fu c body
    | E_break -> { ctl = C_break; store = st; fuel = fu }
    | E_continue -> { ctl = C_continue; store = st; fuel = fu }
    | E_return_unit -> { ctl = C_return I_unit; store = st; fuel = fu }
    | E_return e1 ->
        on_value (eval ops env st fu e1) (fun v st1 fu1 ->
            { ctl = C_return v; store = st1; fuel = fu1 })
    | E_closure (ps, _, body) ->
        value_step (I_closure (ps, body, env)) st fu
    | E_async_closure (ps, _, body) ->
        value_step (I_async_closure (ps, body, env)) st fu
    | E_await e1 ->
        on_value (eval ops env st fu e1) (fun v st1 fu1 ->
            match v with
            | I_future (env', body) ->
                finish_call (eval ops env' st1 fu1 body)
            | I_unit | I_f64 (_, _) | I_bool _ | I_str _ | I_tuple _
            | I_none | I_some _ | I_ok _ | I_err _ | I_closure (_, _, _)
            | I_async_closure (_, _, _) | I_signal _ ->
                stuck "await" st1 fu1)

and eval_args ops env st fu args k =
  match args with
  | [] -> k [] st fu
  | a :: rest ->
      on_value (eval ops env st fu a) (fun v st1 fu1 ->
          eval_args ops env st1 fu1 rest (fun vs st2 fu2 ->
              k (v :: vs) st2 fu2))

and eval_block ops env st fu stmts k =
  match stmts with
  | [] -> k env st fu
  | s :: rest ->
      (match Wf.classify_stmt s with
       | Wf.Sc_let (x, rhs) ->
           on_value (eval ops env st fu rhs) (fun v st1 fu1 ->
               eval_block ops ((x, v) :: env) st1 fu1 rest k)
       | Wf.Sc_expr ->
           on_value (eval ops env st fu s) (fun _v st1 fu1 ->
               eval_block ops env st1 fu1 rest k))

(* Fuel strictly decreases through the body evaluation, so both loop
   forms terminate on C_fuel at the latest. *)
and eval_loop ops env st fu body =
  let s1 = eval ops env st fu body in
  match s1.ctl with
  | C_value _ -> eval_loop ops env s1.store s1.fuel body
  | C_continue -> eval_loop ops env s1.store s1.fuel body
  | C_break -> value_step I_unit s1.store s1.fuel
  | C_return _ | C_panic (_, _) | C_fuel -> s1

and eval_while ops env st fu c body =
  on_value (eval ops env st fu c) (fun vc st1 fu1 ->
      Option.fold
        ~none:(stuck "type" st1 fu1)
        ~some:(fun cond ->
          if cond then
            let s1 = eval ops env st1 fu1 body in
            match s1.ctl with
            | C_value _ -> eval_while ops env s1.store s1.fuel c body
            | C_continue -> eval_while ops env s1.store s1.fuel c body
            | C_break -> value_step I_unit s1.store s1.fuel
            | C_return _ | C_panic (_, _) | C_fuel -> s1
          else value_step I_unit st1 fu1)
        (as_bool vc))

(* Calling a sync closure runs the body now (C_return becomes the
   call's value); calling an async closure binds the arguments and
   defers the body, matching lazy Rust futures. *)
and apply ops vf args st fu =
  match vf with
  | I_closure (ps, body, cenv) ->
      Option.fold
        ~none:(stuck "arity" st fu)
        ~some:(fun env' -> finish_call (eval ops env' st fu body))
        (bind_params ps args cenv)
  | I_async_closure (ps, body, cenv) ->
      Option.fold
        ~none:(stuck "arity" st fu)
        ~some:(fun env' -> value_step (I_future (env', body)) st fu)
        (bind_params ps args cenv)
  | I_unit | I_f64 (_, _) | I_bool _ | I_str _ | I_tuple _ | I_none
  | I_some _ | I_ok _ | I_err _ | I_future (_, _) | I_signal _ ->
      stuck "not-callable" st fu

and finish_call s =
  match s.ctl with
  | C_value v -> value_step v s.store s.fuel
  | C_return v -> value_step v s.store s.fuel
  | C_break -> stuck "control-escape" s.store s.fuel
  | C_continue -> stuck "control-escape" s.store s.fuel
  | C_panic (_, _) | C_fuel -> s

(* ---------- binary operators ---------- *)

and arith_step f va vb st fu =
  Option.fold
    ~none:(stuck "type" st fu)
    ~some:(fun p ->
      Option.fold
        ~none:(stuck "type" st fu)
        ~some:(fun q ->
          let r = f (fst p) (snd p) (fst q) (snd q) in
          value_step (I_f64 (fst r, snd r)) st fu)
        (as_f64 vb))
    (as_f64 va)

and ord_step ffloat fstr va vb st fu =
  match va with
  | I_f64 (h1, l1) ->
      Option.fold
        ~none:(stuck "type" st fu)
        ~some:(fun p ->
          value_step (I_bool (ffloat h1 l1 (fst p) (snd p))) st fu)
        (as_f64 vb)
  | I_str s ->
      Option.fold
        ~none:(stuck "type" st fu)
        ~some:(fun t -> value_step (I_bool (fstr s t)) st fu)
        (as_str vb)
  | I_unit | I_bool _ | I_tuple _ | I_none | I_some _ | I_ok _ | I_err _
  | I_closure (_, _, _) | I_async_closure (_, _, _) | I_future (_, _)
  | I_signal _ -> stuck "type" st fu

and eq_step ops negate va vb st fu =
  Option.fold
    ~none:(stuck "type" st fu)
    ~some:(fun b ->
      value_step (I_bool (if negate then not b else b)) st fu)
    (value_eq ops va vb)

and binary_step ops op va vb st fu =
  match op with
  | B_add -> arith_step ops.f_add va vb st fu
  | B_sub -> arith_step ops.f_sub va vb st fu
  | B_mul -> arith_step ops.f_mul va vb st fu
  | B_div -> arith_step ops.f_div va vb st fu
  | B_eq -> eq_step ops false va vb st fu
  | B_ne -> eq_step ops true va vb st fu
  | B_lt -> ord_step ops.f_lt (fun s t -> ops.str_cmp s t < 0) va vb st fu
  | B_le -> ord_step ops.f_le (fun s t -> ops.str_cmp s t <= 0) va vb st fu
  | B_gt -> ord_step ops.f_gt (fun s t -> ops.str_cmp s t > 0) va vb st fu
  | B_ge -> ord_step ops.f_ge (fun s t -> ops.str_cmp s t >= 0) va vb st fu

(* ---------- methods ---------- *)

and with0 vs st fu k =
  match vs with
  | [] -> k st fu
  | _ :: _ -> stuck "arity" st fu

and with1 vs st fu k =
  match vs with
  | v :: [] -> k v st fu
  | [] -> stuck "arity" st fu
  | _ :: _ :: _ -> stuck "arity" st fu

and on_str_recv vr st fu k =
  Option.fold ~none:(stuck "type" st fu) ~some:(fun s -> k s st fu)
    (as_str vr)

and str_pred f vr vs st fu =
  on_str_recv vr st fu (fun s st1 fu1 ->
      with1 vs st1 fu1 (fun v st2 fu2 ->
          Option.fold
            ~none:(stuck "type" st2 fu2)
            ~some:(fun t -> value_step (I_bool (f s t)) st2 fu2)
            (as_str v)))

and str_map f vr vs st fu =
  on_str_recv vr st fu (fun s st1 fu1 ->
      with0 vs st1 fu1 (fun st2 fu2 -> value_step (I_str (f s)) st2 fu2))

and signal_read vr st fu k =
  Option.fold
    ~none:(stuck "type" st fu)
    ~some:(fun x ->
      Option.fold
        ~none:(stuck "signal-unbound" st fu)
        ~some:(fun v -> k x v st fu)
        (assoc_opt int_eq x st))
    (as_signal vr)

and expect_msg vs st fu k =
  with1 vs st fu (fun v st1 fu1 ->
      Option.fold ~none:(stuck "type" st1 fu1)
        ~some:(fun m -> k m st1 fu1)
        (as_str v))

and method_step ops m vr vs st fu =
  match m with
  | M_then ->
      with1 vs st fu (fun vf st1 fu1 ->
          Option.fold
            ~none:(stuck "type" st1 fu1)
            ~some:(fun b ->
              if b then
                on_value (apply ops vf [] st1 fu1) (fun v st2 fu2 ->
                    value_step (I_some v) st2 fu2)
              else value_step I_none st1 fu1)
            (as_bool vr))
  | M_then_some ->
      with1 vs st fu (fun v st1 fu1 ->
          Option.fold
            ~none:(stuck "type" st1 fu1)
            ~some:(fun b ->
              if b then value_step (I_some v) st1 fu1
              else value_step I_none st1 fu1)
            (as_bool vr))
  | M_len ->
      on_str_recv vr st fu (fun s st1 fu1 ->
          with0 vs st1 fu1 (fun st2 fu2 ->
              let p = ops.f_of_int (String.length s) in
              value_step (I_f64 (fst p, snd p)) st2 fu2))
  | M_is_empty ->
      on_str_recv vr st fu (fun s st1 fu1 ->
          with0 vs st1 fu1 (fun st2 fu2 ->
              value_step (I_bool (int_eq (String.length s) 0)) st2 fu2))
  | M_trim -> str_map ops.str_trim vr vs st fu
  | M_trim_start -> str_map ops.str_trim_start vr vs st fu
  | M_trim_end -> str_map ops.str_trim_end vr vs st fu
  | M_to_owned -> str_map (fun s -> s) vr vs st fu
  | M_starts_with -> str_pred ops.str_starts_with vr vs st fu
  | M_ends_with -> str_pred ops.str_ends_with vr vs st fu
  | M_contains -> str_pred ops.str_contains vr vs st fu
  | M_is_some ->
      with0 vs st fu (fun st1 fu1 ->
          match opt_shape vr with
          | Op_some _ -> value_step (I_bool true) st1 fu1
          | Op_none -> value_step (I_bool false) st1 fu1
          | Op_not_option -> stuck "type" st1 fu1)
  | M_is_none ->
      with0 vs st fu (fun st1 fu1 ->
          match opt_shape vr with
          | Op_some _ -> value_step (I_bool false) st1 fu1
          | Op_none -> value_step (I_bool true) st1 fu1
          | Op_not_option -> stuck "type" st1 fu1)
  | M_is_ok ->
      with0 vs st fu (fun st1 fu1 ->
          match res_shape vr with
          | Rs_ok _ -> value_step (I_bool true) st1 fu1
          | Rs_err _ -> value_step (I_bool false) st1 fu1
          | Rs_not_result -> stuck "type" st1 fu1)
  | M_is_err ->
      with0 vs st fu (fun st1 fu1 ->
          match res_shape vr with
          | Rs_ok _ -> value_step (I_bool false) st1 fu1
          | Rs_err _ -> value_step (I_bool true) st1 fu1
          | Rs_not_result -> stuck "type" st1 fu1)
  | M_ok ->
      with0 vs st fu (fun st1 fu1 ->
          match res_shape vr with
          | Rs_ok v -> value_step (I_some v) st1 fu1
          | Rs_err _ -> value_step I_none st1 fu1
          | Rs_not_result -> stuck "type" st1 fu1)
  | M_err ->
      with0 vs st fu (fun st1 fu1 ->
          match res_shape vr with
          | Rs_ok _ -> value_step I_none st1 fu1
          | Rs_err v -> value_step (I_some v) st1 fu1
          | Rs_not_result -> stuck "type" st1 fu1)
  | M_unwrap ->
      with0 vs st fu (fun st1 fu1 ->
          match opt_shape vr with
          | Op_some v -> value_step v st1 fu1
          | Op_none ->
              panic_step P_unwrap
                "called `Option::unwrap()` on a `None` value" st1 fu1
          | Op_not_option ->
              (match res_shape vr with
               | Rs_ok v -> value_step v st1 fu1
               | Rs_err e ->
                   panic_step P_unwrap
                     ("called `Result::unwrap()` on an `Err` value: "
                      ^ debug_value ops e)
                     st1 fu1
               | Rs_not_result -> stuck "type" st1 fu1))
  | M_expect ->
      expect_msg vs st fu (fun msg st1 fu1 ->
          match opt_shape vr with
          | Op_some v -> value_step v st1 fu1
          | Op_none -> panic_step P_expect msg st1 fu1
          | Op_not_option ->
              (match res_shape vr with
               | Rs_ok v -> value_step v st1 fu1
               | Rs_err e ->
                   panic_step P_expect
                     (msg ^ ": " ^ debug_value ops e) st1 fu1
               | Rs_not_result -> stuck "type" st1 fu1))
  | M_unwrap_err ->
      with0 vs st fu (fun st1 fu1 ->
          match res_shape vr with
          | Rs_err v -> value_step v st1 fu1
          | Rs_ok v ->
              panic_step P_unwrap_err
                ("called `Result::unwrap_err()` on an `Ok` value: "
                 ^ debug_value ops v)
                st1 fu1
          | Rs_not_result -> stuck "type" st1 fu1)
  | M_expect_err ->
      expect_msg vs st fu (fun msg st1 fu1 ->
          match res_shape vr with
          | Rs_err v -> value_step v st1 fu1
          | Rs_ok v ->
              panic_step P_expect_err
                (msg ^ ": " ^ debug_value ops v) st1 fu1
          | Rs_not_result -> stuck "type" st1 fu1)
  | M_get ->
      with0 vs st fu (fun st1 fu1 ->
          signal_read vr st1 fu1 (fun _x v st2 fu2 ->
              value_step v st2 fu2))
  | M_set ->
      with1 vs st fu (fun v st1 fu1 ->
          Option.fold
            ~none:(stuck "type" st1 fu1)
            ~some:(fun x -> value_step I_unit (store_set st1 x v) fu1)
            (as_signal vr))
  | M_toggle ->
      with0 vs st fu (fun st1 fu1 ->
          signal_read vr st1 fu1 (fun x v st2 fu2 ->
              Option.fold
                ~none:(stuck "type" st2 fu2)
                ~some:(fun b ->
                  value_step I_unit (store_set st2 x (I_bool (not b))) fu2)
                (as_bool v)))
  | M_increment -> signal_delta ops.f_add vr vs st fu
  | M_decrement -> signal_delta ops.f_sub vr vs st fu
  | M_push_str ->
      expect_msg vs st fu (fun t st1 fu1 ->
          signal_read vr st1 fu1 (fun x v st2 fu2 ->
              Option.fold
                ~none:(stuck "type" st2 fu2)
                ~some:(fun s ->
                  value_step I_unit (store_set st2 x (I_str (s ^ t))) fu2)
                (as_str v)))
  | M_clone -> with0 vs st fu (fun st1 fu1 -> value_step vr st1 fu1)

and signal_delta f vr vs st fu =
  with0 vs st fu (fun st1 fu1 ->
      signal_read vr st1 fu1 (fun x v st2 fu2 ->
          Option.fold
            ~none:(stuck "type" st2 fu2)
            ~some:(fun p ->
              (* 1072693248 = high 32 bits of IEEE 1.0; low half 0.
                 Bound locally: ZxCaml emits top-level constants only
                 for the entrypoint. *)
              let one_hi = 1072693248 in
              let q = f (fst p) (snd p) one_hi 0 in
              value_step I_unit
                (store_set st2 x (I_f64 (fst q, snd q)))
                fu2)
            (as_f64 v)))

(* ---------- observation projection and top-level entry ---------- *)

(* Closures, futures, and signals have no value-channel encoding
   (V_closure is the opaque marker); the generator keeps them away
   from observable positions. *)
let rec project v =
  match v with
  | I_unit -> V_unit
  | I_f64 (hi, lo) -> V_f64_bits (hi, lo)
  | I_bool b -> V_bool b
  | I_str s -> V_str s
  | I_tuple vs -> V_tuple (map project vs)
  | I_none -> V_none
  | I_some v1 -> V_some (project v1)
  | I_ok v1 -> V_ok (project v1)
  | I_err v1 -> V_err (project v1)
  | I_closure (_, _, _) | I_async_closure (_, _, _) | I_future (_, _)
  | I_signal _ -> V_closure

type run_result = {
  outcome : outcome;
  signals : (int * value) list; (* final signal states by variable id *)
}

(* inputs: plain pre-bound variables. sig_init: initial signal store;
   each signal id is also bound in the environment as I_signal id.
   The rendered channel is composed by the ref-leg adapter (M26), not
   here. *)
let eval_top ops inputs sig_init fuel e =
  let sig_env = map (fun kv -> (fst kv, I_signal (fst kv))) sig_init in
  let s = eval ops (append sig_env inputs) sig_init fuel e in
  let signals = map (fun kv -> (fst kv, project (snd kv))) s.store in
  match s.ctl with
  | C_value v -> { outcome = O_value (project v); signals }
  | C_panic (p, msg) -> { outcome = O_panic (p, msg); signals }
  | C_fuel -> { outcome = O_no_terminate; signals }
  | C_break | C_continue | C_return _ ->
      (* Wf rejects all three at top level (break/continue outside a
         loop; E_return under R_top is W_return_outside_closure), so
         a control escape here means the input skipped wf. Totalized
         as a stuck panic - deliberately NOT as a value for C_return,
         which would silently accept un-wf-checked input. *)
      { outcome = O_panic (P_other, "stuck:control-escape"); signals }

(* ---------- M21: sample initializers and whole-sample runs ---------- *)

(* A closed initializer (Sample.binding.init) reduces to a store
   value, or it does not: a panic, fuel exhaustion, or a control
   escape all mean the generator drew an init it should not have.
   None reports that instead of substituting a value, and the M21
   gate asserts Some on every drawn init. *)
let eval_init ops fuel e =
  let s = eval ops [] [] fuel e in
  match s.ctl with
  | C_value v -> Some v
  | C_panic (_, _) | C_fuel | C_break | C_continue | C_return _ -> None

(* One binding to its (id, value) pair, or nothing when the init
   fails to reduce. *)
let binding_pair ops fuel b =
  Option.fold
    ~none:None
    ~some:(fun v -> Some (b.Sample.id, v))
    (eval_init ops fuel b.Sample.init)

(* Every binding in order, or nothing when any one of them fails.
   The accumulator is itself an option, so a single failure carries
   through to the end without an exception or an option match. The
   pairs come out reversed and the caller's `rev` restores the
   binding order. *)
let eval_bindings_rev ops fuel bs =
  fold
    (fun acc b ->
      Option.fold ~none:None
        ~some:(fun kvs ->
          Option.fold ~none:None
            ~some:(fun kv -> Some (kv :: kvs))
            (binding_pair ops fuel b))
        acc)
    (Some []) bs

let eval_bindings ops fuel bs =
  Option.map rev (eval_bindings_rev ops fuel bs)

(* Run one sample: reduce every initializer in the EMPTY environment
   (the inits are closed by construction), bind the inputs by value
   and the signals into the store, then hand the body to eval_top.
   An init that fails to reduce surfaces as O_panic (P_other,
   "stuck:init") rather than being dropped, so a generator bug shows
   up on the pipeline's own observation channel instead of shrinking
   the sample count silently.

   The ~none arm builds a record, which Option.fold evaluates
   eagerly; that is a constant, so the eager arm costs nothing. *)
let run_sample ops fuel (s : Sample.t) =
  Option.fold
    ~none:{ outcome = O_panic (P_other, "stuck:init"); signals = [] }
    ~some:(fun p -> eval_top ops (fst p) (snd p) fuel s.Sample.body)
    (Option.fold ~none:None
       ~some:(fun ins ->
         Option.fold ~none:None
           ~some:(fun sigs -> Some (ins, sigs))
           (eval_bindings ops fuel s.Sample.signals))
       (eval_bindings ops fuel s.Sample.inputs))
