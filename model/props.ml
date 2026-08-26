(* Atomic propositions and the CTLK property table.
   Every entry carries an expected verdict for BOTH systems, so the
   negative control is itself gated: a property that cannot tell
   Coupled from Uncoupled where it should is a check failure. *)

open State
module C = Ctlk

type atom =
  | Is_filed
  | Is_terminal
  | Diverged
  | All_legs_ok
  | Rust_crashed
  | Ref_crashed
  | Agree_terminal

let is_terminal = function
  | Filed | Dropped_agree | Dropped_known | Gen_bug | Oracle_bug
  | Leg_failed -> true
  | Generated | Shaped | Printed | Compiled | Executed | Minimizing_hi
  | Minimizing_lo -> false

let leg_ok = function L_ok -> true | L_pending -> false | L_crashed -> false

let leg_crashed = function
  | L_crashed -> true
  | L_pending -> false
  | L_ok -> false

let den atom w =
  match atom with
  | Is_filed -> String.equal (Frame.stage_str w.stage) "filed"
  | Is_terminal -> is_terminal w.stage
  | Diverged ->
    (match w.verdict with
     | V_diverge -> true
     | V_none | V_agree | V_known -> false)
  | All_legs_ok -> leg_ok w.rust && leg_ok w.js && leg_ok w.reference
  | Rust_crashed -> leg_crashed w.rust
  | Ref_crashed -> leg_crashed w.reference
  | Agree_terminal -> String.equal (Frame.stage_str w.stage) "dropped_agree"

type kind = Valid | Satisfiable

type entry = {
  name : string;
  form : (atom, Frame.agent) C.form;
  kind : kind;
  expect_coupled : bool;
  expect_uncoupled : bool;
}

let imp a b = C.Imp (a, b)

let table =
  [ { name = "P1 filed-implies-diverged";
      form = C.Ag (imp (C.Atom Is_filed) (C.Atom Diverged));
      kind = Valid; expect_coupled = true; expect_uncoupled = false };
    { name = "P2 agreement-needs-all-legs";
      form = C.Ag (imp (C.Atom Agree_terminal) (C.Atom All_legs_ok));
      kind = Valid; expect_coupled = true; expect_uncoupled = true };
    { name = "P3 every-sample-terminates";
      form = C.Af (C.Atom Is_terminal);
      kind = Valid; expect_coupled = true; expect_uncoupled = true };
    { name = "P4 triager-knows-divergence-at-filing";
      form =
        C.Ag (imp (C.Atom Is_filed) (C.Know (Frame.Triager, C.Atom Diverged)));
      kind = Valid; expect_coupled = true; expect_uncoupled = false };
    { name = "P5 reference-crash-never-files";
      form = C.Ag (imp (C.Atom Ref_crashed) (C.Not (C.Ef (C.Atom Is_filed))));
      kind = Valid; expect_coupled = true; expect_uncoupled = true };
    { name = "P6 rust-leg-knows-own-crash";
      form =
        C.Ag
          (imp (C.Atom Rust_crashed)
             (C.Know (Frame.Rust_leg, C.Atom Rust_crashed)));
      kind = Valid; expect_coupled = true; expect_uncoupled = true };
    { name = "P7 filing-reachable";
      form = C.Atom Is_filed;
      kind = Satisfiable; expect_coupled = true; expect_uncoupled = true };
    { name = "P8 agreement-reachable";
      form = C.Atom Agree_terminal;
      kind = Satisfiable; expect_coupled = true; expect_uncoupled = true };
    { name = "P9 no-common-knowledge-of-divergence";
      form =
        C.Ag
          (imp (C.Atom Is_filed)
             (C.Common
                ([ Frame.Rust_leg; Frame.Js_leg; Frame.Ref_leg ],
                 C.Atom Diverged)));
      kind = Valid; expect_coupled = false; expect_uncoupled = false } ]
