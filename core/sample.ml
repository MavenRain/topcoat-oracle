(* M21: one complete differential test case.

   A sample carries everything the three legs need: the value
   environment, the signal environment, the target type, the body,
   and the mode that fixes the diff arity (core/taxonomy.ml).

   Data only, on purpose. The draw lives in shell/sample_gen.ml,
   because QCheck is a shell dependency and this module is
   dual-compiled with the rest of core/. *)

open Prelude
open Ast

(* One bound variable. For a signal, `ty` is the ELEMENT type, not
   T_signal of it: wf_env below does the wrapping, exactly as
   Gen.wf_env does for the generation environment.

   `init` is a CLOSED literal expression: no free variables, no
   signals, no calls. Wf accepts it at `ty` in the empty environment
   and the interpreter reduces it to a value (Interp.eval_init). The
   rust driver (M23) renders it with the same printer as the body:
   `let vID: T = <init>;` for an input, `let vID = Signal::new(<init>);`
   for a signal. *)
type binding = {
  id : int;
  ty : ty;
  init : expr;
}

type t = {
  mode : Taxonomy.mode;
  inputs : binding list;
  signals : binding list;
  target : ty;
  body : expr;
}

(* The environment Wf.check_top wants: signals first as T_signal of
   their element type, then the inputs. Same order as Gen.wf_env, so
   a sample and the generation environment it was drawn from agree on
   variable lookup order. *)
let wf_env (s : t) : (int * ty) list =
  append
    (map (fun (b : binding) -> (b.id, T_signal b.ty)) s.signals)
    (map (fun (b : binding) -> (b.id, b.ty)) s.inputs)

(* Bound ids in wf_env order. *)
let ids (s : t) : int list =
  append
    (map (fun (b : binding) -> b.id) s.signals)
    (map (fun (b : binding) -> b.id) s.inputs)

(* Does the recorded mode match what the classifier reads off the
   body? The generator sets `mode` from the draw it requested, so
   this is an independent cross-check: the M21 gate asserts it on
   every sample. *)
let mode_ok (s : t) : bool = Taxonomy.mode_eq s.mode (Taxonomy.mode_of s.body)
