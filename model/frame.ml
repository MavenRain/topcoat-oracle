(* Named transitions of the pipeline. Ctlk.system_of consumes [post].
   [Coupled] is the shipped design: filing is guarded by a diverge
   verdict. [Uncoupled] is the negative control: it can file without a
   verdict, and the property table must catch it. *)

open State

type coupling = Coupled | Uncoupled

type agent = Rust_leg | Js_leg | Ref_leg | Triager

let agents = [ Rust_leg; Js_leg; Ref_leg; Triager ]

type tname =
  | Shape_ok | Shape_fail | Print_ok | Compile_ok | Compile_fail
  | Exec_rust_ok | Exec_rust_crash | Exec_js_ok | Exec_js_crash
  | Exec_ref_ok | Exec_ref_crash
  | Judge_agree | Judge_diverge | Judge_known | Judge_infra
  | File_unjudged | Shrink | Shrink_done | Stay

let leg_str = function L_pending -> "p" | L_ok -> "o" | L_crashed -> "c"

let stage_str = function
  | Generated -> "generated" | Shaped -> "shaped" | Printed -> "printed"
  | Compiled -> "compiled" | Executed -> "executed"
  | Minimizing_hi -> "minimizing_hi" | Minimizing_lo -> "minimizing_lo"
  | Filed -> "filed" | Dropped_agree -> "dropped_agree"
  | Dropped_known -> "dropped_known" | Gen_bug -> "gen_bug"
  | Oracle_bug -> "oracle_bug" | Leg_failed -> "leg_failed"

(* Each agent observes one field. The three legs each see only their
   own outcome. The triager sees only the disposition (the stage), not
   the verdict; knowledge of divergence at filing time must therefore
   come from the shape of the reachable space, which is exactly what
   the coupling guard provides. *)
let view agent w =
  match agent with
  | Rust_leg -> leg_str w.rust
  | Js_leg -> leg_str w.js
  | Ref_leg -> leg_str w.reference
  | Triager -> stage_str w.stage

(* Legs run in a fixed order (rust, js, reference) with
   nondeterministic outcomes. The last decision moves to Executed. *)
let exec_steps w =
  match w.rust with
  | L_pending ->
    [ (Exec_rust_ok, { w with rust = L_ok });
      (Exec_rust_crash, { w with rust = L_crashed }) ]
  | L_ok | L_crashed ->
    (match w.js with
     | L_pending ->
       [ (Exec_js_ok, { w with js = L_ok });
         (Exec_js_crash, { w with js = L_crashed }) ]
     | L_ok | L_crashed ->
       (match w.reference with
        | L_pending ->
          [ (Exec_ref_ok, { w with reference = L_ok; stage = Executed });
            (Exec_ref_crash,
             { w with reference = L_crashed; stage = Executed }) ]
        | L_ok | L_crashed -> []))

let judge_steps coupling w =
  match w.reference with
  | L_crashed -> [ (Judge_infra, { w with stage = Oracle_bug }) ]
  | L_pending -> []
  | L_ok ->
    (match w.rust with
     | L_crashed -> [ (Judge_infra, { w with stage = Leg_failed }) ]
     | L_pending -> []
     | L_ok ->
       (match w.js with
        | L_crashed -> [ (Judge_infra, { w with stage = Leg_failed }) ]
        | L_pending -> []
        | L_ok ->
          let judged =
            [ (Judge_agree, { w with stage = Dropped_agree; verdict = V_agree });
              (Judge_known, { w with stage = Dropped_known; verdict = V_known });
              (Judge_diverge,
               { w with stage = Minimizing_hi; verdict = V_diverge }) ]
          in
          (match coupling with
           | Coupled -> judged
           | Uncoupled -> (File_unjudged, { w with stage = Filed }) :: judged)))

let steps coupling w =
  match w.stage with
  | Generated ->
    [ (Shape_ok, { w with stage = Shaped });
      (Shape_fail, { w with stage = Gen_bug }) ]
  | Shaped -> [ (Print_ok, { w with stage = Printed }) ]
  | Printed ->
    [ (Compile_ok, { w with stage = Compiled });
      (Compile_fail, { w with stage = Gen_bug }) ]
  | Compiled -> exec_steps w
  | Executed -> judge_steps coupling w
  | Minimizing_hi ->
    [ (Shrink, { w with stage = Minimizing_lo });
      (Shrink_done, { w with stage = Filed }) ]
  | Minimizing_lo -> [ (Shrink_done, { w with stage = Filed }) ]
  | Filed | Dropped_agree | Dropped_known | Gen_bug | Oracle_bug
  | Leg_failed -> [ (Stay, w) ]

let post coupling w = List.map snd (steps coupling w)
