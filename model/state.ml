(* Lifecycle of one generated sample in the oracle pipeline.
   This is the carrier type of the CTLK model. Keep it small: the
   kernel evaluates fixpoints over the full reachable space. *)

type stage =
  | Generated (* the generator produced an AST *)
  | Shaped (* the AST passed the wf type-shape check *)
  | Printed (* Rust source text emitted *)
  | Compiled (* driver crate compiled; native value and JS text captured *)
  | Executed (* all three legs ran; outcomes recorded *)
  | Minimizing_hi (* shrink loop, budget remaining *)
  | Minimizing_lo (* shrink loop, budget exhausted after next step *)
  | Filed (* terminal: minimized repro written *)
  | Dropped_agree (* terminal: all legs agree *)
  | Dropped_known (* terminal: documented intentional asymmetry *)
  | Gen_bug (* terminal: generator or printer produced an invalid sample *)
  | Oracle_bug (* terminal: the reference leg crashed; our bug *)
  | Leg_failed (* terminal: a product leg crashed; infrastructure issue *)

type leg = L_pending | L_ok | L_crashed

type verdict = V_none | V_agree | V_diverge | V_known

type state = {
  stage : stage;
  rust : leg; (* rustc-native leg *)
  js : leg; (* topcoat-emitted JS under node *)
  reference : leg; (* OCaml reference interpreter *)
  verdict : verdict;
}

let init =
  { stage = Generated; rust = L_pending; js = L_pending;
    reference = L_pending; verdict = V_none }
