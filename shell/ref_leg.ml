(* M26 reference leg (DESIGN.md M26, spec section 4).  The third
   observation of every seed:  core/interp.ml evaluates the sample, and
   this module composes the rendered channel that Interp.run_result does
   not carry (core/interp.ml:693-695 names this milestone as its
   owner).

   The module sits in shell/ and not in core/, because its default op
   record is built from Floatops and Strops, and both are full-OCaml
   float and string modules.  The config carries the record, so a
   planted run and a clean run share no state (shell/plant.ml).

   The leg is PURE:  no process, no file and no directory.  It reads
   Driver.seed_cases, which is a value. *)

(* Two fields on purpose.  M29's minimizer adds a per-run node budget,
   and a bare int parameter would have to be threaded through every call
   site again.  The op record is the second field because M28 selects a
   planted interpreter at run time (shell/plant.ml), and a global would
   make the planted run and the clean run share state. *)
type config = { fuel : int; ops : Interp.ops }

(* 10000 is the pinned number:  test/test_sample.ml:27 let fuel =
   10_000, and shell/cover.ml let init_n = 10_000.  Fuel exhaustion is
   O_no_terminate (core/interp.ml:704), which is an observation and
   never a silent stop, so the cap is loud by construction. *)
let default_config : config = { fuel = 10000; ops = Ops.interp_ops }

(* ---------- the rendered channel (spec 4.3) ---------- *)

(* Rust Display, with NO html escaping.  The escaper is an HTML-context
   transform that the SERVER applies;  modelling it here would build the
   server's answer into the oracle.  Case 1 therefore renders a<b>+c,
   six bytes, and not the escaped twelve bytes of the Rust leg.  That is
   divergence D2 and M26 prints it.

   The rust leg picks its renderable set from the TARGET TYPE
   (Driver.renderable, shell/driver.ml:181-186, and the harness switch
   at driver-rs/harness.rs:157-167).  This list picks it from the VALUE
   SHAPE.  Well formedness makes the observed value carry the target
   type, so a shape and its type are in the set together or out of it
   together, and every absent shape renders "" on both sides. *)
let rec rendered_of_value (ops : Interp.ops) (v : Obs.value) : string =
  match v with
  | Obs.V_f64_bits (hi, lo) -> ops.Interp.f_display hi lo
  | Obs.V_str s -> s
  | Obs.V_bool b -> if b then "true" else "false"
  | Obs.V_unit -> ""
  | Obs.V_some v1 -> rendered_of_value ops v1
  | Obs.V_none -> ""
  | Obs.V_tuple _ | Obs.V_ok _ | Obs.V_err _ | Obs.V_closure -> ""

(* A panic and a no-terminate render the empty string.  The harness
   reports an empty rendered_hex for both, so Obs.encode prints |r0:| on
   each side. *)
let rendered_of_outcome (cfg : config) (o : Obs.outcome) : string =
  match o with
  | Obs.O_value v -> rendered_of_value cfg.ops v
  | Obs.O_panic (_, _) -> ""
  | Obs.O_no_terminate -> ""

(* ---------- the entry point (spec 4.2) ---------- *)

let observe (cfg : config) (s : Sample.t) : Obs.observation =
  let r = Interp.run_sample cfg.ops cfg.fuel s in
  {
    Obs.outcome = r.Interp.outcome;
    rendered = rendered_of_outcome cfg r.Interp.outcome;
    signals = r.Interp.signals;
  }

(* Sample.t has no hint field (core/sample.ml:30-42), so the static scan
   of the body is the only route, and it is the one the emitter uses. *)
let hint (s : Sample.t) : Driver.hint = Driver.hint_of s.Sample.body
