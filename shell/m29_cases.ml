(* M29 planted cases (DESIGN.md M29, spec section 6).  Two samples, one
   per plant, and nothing else.  The twelve M27 seeds of shell/driver.ml
   are the corpus of the earlier gates and are not touched here.

   Each case is built for one half of the loop.  The reference case is
   f64 valued, so Shrink.minimal offers the zero literal as the FIRST
   candidate of round 0 and the sign-flip plant survives it: the walk
   then spends its remaining rounds dropping bindings.  The js case
   reads a signal, so the same first candidate does NOT preserve the
   divergence and the walk follows the structural rules; its second
   candidate diverges on ANOTHER channel, which is the candidate the
   preservation rule must refuse.

   Every literal is a bit pattern, so no float text is parsed anywhere,
   and every node is one the M27 seeds already use. *)

open Ast

(* f64 bit patterns, hi word then lo word (core/obs.ml:16).  1.5 is
   0x3FF8000000000000, that is hi 1073217536 and lo 0, the pattern the
   M27 table prints as Vf1073217536:0.  2.5 is 0x4004000000000000, that
   is hi 1074003968 and lo 0. *)
let f1_5 : expr = E_lit (L_f64_bits (1073217536, 0))
let f2_5 : expr = E_lit (L_f64_bits (1074003968, 0))

(* One binding, named to keep the two case records short. *)
let binding (id : int) (t : ty) (init : expr) : Sample.binding =
  { Sample.id; Sample.ty = t; Sample.init }

(* The reference case, for ref:display_sign.

   Body v0 + v2 is 4 under both interpreters, but the plant flips the
   sign bit of every f64 the reference DISPLAYS, so the reference
   renders -4 where rust and js render 4: the rendered channel moves and
   the reference is the odd leg.  The start verdict is therefore
   diverge:rendered:odd:ref.

   v1 is a string the body never mentions: it is the binding drop the
   loop has to find.  Its Shrink.own_weight is 4, one per byte of
   "keep", which is why dropping it is worth more than one size point in
   a body reading but exactly one in size_of, where a binding weighs
   one. *)
let ref_case : Sample.t =
  {
    Sample.mode = Taxonomy.Read_only;
    Sample.inputs =
      [
        binding 0 T_f64 f1_5;
        binding 1 T_string (E_lit (L_str "keep"));
        binding 2 T_f64 f2_5;
      ];
    Sample.signals = [];
    Sample.target = T_f64;
    Sample.body = E_binary (B_add, E_var 0, E_var 2);
  }

(* The js case, for js:signal_get_plus_one.

   The condition is the literal false, so the body evaluates the ELSE
   branch and reads the signal v3.  Under the plant the js glue answers
   3.5 where rust and the reference answer 2.5, so the VALUE channel
   moves before the rendered one and the js leg is odd.  The start
   verdict is therefore diverge:value:odd:js.

   The THEN branch is an unwrap of a None, the shape of M27 seed 5.  It
   panics in rust and throws in js with a different class, so on its own
   it is diverge:class:odd:js, with or without a plant.  Shrink offers
   it as a bare candidate in round 0, right after the collapse, and the
   preservation rule refuses it because the channel is class and not
   value.  Without it the first tooth of section 13 would be vacuous.

   v5 is an INPUT the body never mentions and v8 becomes unmentioned as
   soon as the then branch is gone: those are the two binding drops.

   v5 is an input and not a signal on purpose.  driver-js/worker.mjs
   pairSignals joins the wire signal records to the signal uuids of the
   EMITTED JS TEXT positionally and refuses a count mismatch with the
   error signal_arity, and an unread signal never appears in the emitted
   JS at all.  So an unmentioned binding of a case is always an input,
   and every declared signal is read by the body.  v5 sits at the END of
   the inputs, after v8, so the candidate order of a round stays
   inputs-then-v5: v8 before v5 in round 1, and v0, v8, v5 in round 2. *)
let js_case : Sample.t =
  {
    Sample.mode = Taxonomy.Read_only;
    Sample.inputs =
      [
        binding 0 T_f64 f1_5;
        binding 8 (T_option T_f64) (E_none T_f64);
        binding 5 T_bool (E_lit (L_bool false));
      ];
    Sample.signals = [ binding 3 T_f64 f2_5 ];
    Sample.target = T_f64;
    Sample.body =
      E_if_else
        ( E_lit (L_bool false),
          E_method (E_method (E_var 8, M_clone, []), M_unwrap, []),
          E_binary (B_add, E_method (E_var 3, M_get, []), E_var 0) );
  }

(* R8, the corpus.  Two entries, in plant order. *)
let cases : (Plant.t * Sample.t) list =
  [
    (Plant.Ref Plant.Rp_display_sign, ref_case);
    (Plant.Js Plant.Jp_signal_get_plus_one, js_case);
  ]

(* The lookup the CLI uses.  A result and not an option, so the caller
   can name the plant in its error line without an eager Option.fold
   arm that would print on the success path.  The match is exhaustive
   over Plant.t, so a new plant is a compile error here and not a
   silent unplanted run. *)
let case_of (p : Plant.t) : (Sample.t, string) result =
  match p with
  | Plant.Ref Plant.Rp_display_sign -> Ok ref_case
  | Plant.Js Plant.Jp_signal_get_plus_one -> Ok js_case
  | Plant.No_plant -> Error "no M29 case belongs to the unplanted run"
