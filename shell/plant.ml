(* M28 planted oracle (DESIGN.md M28, spec section 3).  Two deliberate
   bugs, one per non-rust leg, selected at RUN TIME by one CLI flag.

   The table is a closed sum type and not a string map on purpose.  A
   third plant is then a compiler-checked edit in two functions, and a
   misspelled plant name is a usage error at the boundary instead of a
   silent no-plant run that the gate would score as green.

   The module is PURE:  no process, no file and no channel.  ref_ops
   returns a record, js_args returns a list, and the shells do the
   rest. *)

(* One constructor per plant.  Rp_display_sign flips the sign bit of
   the float the reference leg is about to DISPLAY, so the value bits
   the differ compares are untouched and the rendered channel is the
   one that moves (core/obs.ml:72-93 encodes the two fields apart). *)
type ref_plant = Rp_display_sign

(* Jp_signal_get_plus_one adds one to the number a signal READ returns
   inside the worker's glue.  The stored signal is untouched, so the
   value channel moves and the signals channel does not. *)
type js_plant = Jp_signal_get_plus_one

type t = No_plant | Ref of ref_plant | Js of js_plant

let ref_name (p : ref_plant) : string =
  match p with Rp_display_sign -> "display_sign"

let js_name (p : js_plant) : string =
  match p with Jp_signal_get_plus_one -> "signal_get_plus_one"

let name (p : t) : string =
  match p with
  | No_plant -> "none"
  | Ref r -> "ref:" ^ ref_name r
  | Js j -> "js:" ^ js_name j

(* "none" is REJECTED.  No plant is the ABSENCE of the flag, and
   accepting a spelling for it would let a typo in the gate select the
   unplanted run while the stderr said a plant was set.

   The two spellings are rebuilt from name/ref_name/js_name rather than
   written out again, so the printer and the parser can never drift.
   No prefix strip and no String.sub:  the house rules deny the partial
   accessor and the whole-string compare needs neither. *)
let of_string (s : string) : t option =
  match () with
  | () when String.equal s ("ref:" ^ ref_name Rp_display_sign) ->
      Some (Ref Rp_display_sign)
  | () when String.equal s ("js:" ^ js_name Jp_signal_get_plus_one) ->
      Some (Js Jp_signal_get_plus_one)
  | () -> None

(* The planted interpreter.  Exactly one field of Ops.interp_ops is
   replaced;  the other twenty are the shipped closures, and
   test/test_plant.ml checks all twenty-one one by one. *)
let ref_ops (p : ref_plant) : Interp.ops =
  match p with
  | Rp_display_sign ->
      {
        Ops.interp_ops with
        Interp.f_display =
          (fun hi lo -> Ops.interp_ops.Interp.f_display (hi lxor 0x80000000) lo);
      }

let ops (p : t) : Interp.ops =
  match p with
  | No_plant -> Ops.interp_ops
  | Js _ -> Ops.interp_ops
  | Ref r -> ref_ops r

(* The js plant crosses a process boundary, so it travels as argv and
   not as a closure.  No_plant and a ref plant add nothing, which is
   what keeps the fifteen-element vector test_js_leg.ml pins byte
   identical (test/test_js_leg.ml:211-221). *)
let js_args (p : t) : string list =
  match p with
  | No_plant -> []
  | Ref _ -> []
  | Js j -> [ "--plant"; js_name j ]
