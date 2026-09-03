(* M21: the sample taxonomy, read-only versus signal-writing.

   DESIGN.md section 2 gives the two diff arities. A read-only sample
   diffs three ways (rust leg, js leg, reference). A signal-writing
   sample diffs two ways (js leg versus reference) because the server
   panics on the write shorthands by design, which core/obs.ml
   records as P_signal_write.

   Why the classification is SYNTACTIC, not semantic:
   - The diff arity must be decided BEFORE the legs run. The harness
     chooses two legs or three legs when it dispatches the sample, so
     a verdict that needed the run would be circular.
   - A write in an untaken branch still makes the rust leg's
     panic-by-design possible. `if c { s.set(x) }` panics on the
     server for every c that holds, and c is not known statically. A
     write inside a closure that this sample never calls is the same
     case, so `writes` descends into closure and async-closure
     bodies too.

   The walk therefore over-approximates: a body that would never run
   a write at this input still classifies as Signal_writing. That
   costs one leg on such a sample and never loses a divergence, which
   is the safe direction. *)

open Prelude
open Ast

type mode =
  | Read_only
  | Signal_writing

let mode_name m =
  match m with
  | Read_only -> "read_only"
  | Signal_writing -> "signal_writing"

let mode_eq a b =
  match a with
  | Read_only -> (match b with Read_only -> true | Signal_writing -> false)
  | Signal_writing ->
      (match b with Signal_writing -> true | Read_only -> false)

(* The five signal write shorthands: SignalSurrogate::set / toggle /
   increment / decrement / push_str (topcoat surrogate/signal.rs at
   51caa01d). M_get and M_clone read. Every remaining method belongs
   to a non-signal receiver. Each constructor gets its own arm, so a
   method added to Ast.meth breaks this match instead of silently
   defaulting to "reads". *)
let is_write (m : meth) : bool =
  match m with
  | M_set | M_toggle | M_increment | M_decrement | M_push_str -> true
  | M_then | M_then_some | M_len | M_is_empty | M_trim | M_trim_start
  | M_trim_end | M_starts_with | M_ends_with | M_contains | M_to_owned
  | M_is_some | M_is_none | M_is_ok | M_is_err | M_ok | M_err
  | M_unwrap_err | M_expect_err | M_unwrap | M_expect | M_get | M_clone ->
      false

(* Does this expression mention a write anywhere in its tree? One arm
   per expr constructor: a construct added to Ast.expr breaks the
   match rather than escaping the walk. *)
let rec writes (e : expr) : bool =
  match e with
  | E_lit _ -> false
  | E_var _ -> false
  | E_unary (_, a) -> writes a
  | E_binary (_, a, b) -> writes a || writes b
  | E_tuple es -> writes_any es
  | E_some a -> writes a
  | E_none _ -> false
  | E_ok (a, _) -> writes a
  | E_err (a, _) -> writes a
  | E_call (f, args) -> writes f || writes_any args
  | E_method (r, m, args) -> is_write m || writes r || writes_any args
  | E_field (a, _) -> writes a
  | E_index (a, b) -> writes a || writes b
  | E_let (_, a) -> writes a
  | E_block (ss, tail) -> writes_any ss || writes tail
  | E_block_unit ss -> writes_any ss
  | E_if (c, t) -> writes c || writes t
  | E_if_else (c, t, f) -> writes c || writes t || writes f
  | E_loop b -> writes b
  | E_while (c, b) -> writes c || writes b
  | E_break -> false
  | E_continue -> false
  | E_return_unit -> false
  | E_return a -> writes a
  | E_closure (_, _, b) -> writes b
  | E_async_closure (_, _, b) -> writes b
  | E_await a -> writes a

(* Prelude.fold is not short-circuiting; the walk stays total either
   way and the trees are shallow. *)
and writes_any es = fold (fun acc x -> acc || writes x) false es

let mode_of e = if writes e then Signal_writing else Read_only
