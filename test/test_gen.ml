(* M17 gate: 1000 generated samples; wf accepts each one and infers
   exactly the drawn target type. The printer renders failures for
   the QCheck counterexample report. *)

open Ast

let genv = Gen.default_genv
let env = Gen.wf_env genv

let show sample =
  ty_to_string (fst sample)
  ^ " :: "
  ^ Printer_rust.print Ops.printer_renderer (snd sample)

let wf_at_target sample =
  Result.fold
    ~ok:(fun t -> ty_eq (fst sample) t)
    ~error:(fun _e -> false)
    (Wf.check_top env (snd sample))

let qt_wf =
  QCheck.Test.make ~count:1000 ~name:"generated exprs wf at target ty"
    (QCheck.make ~print:show (Gen.gen_target genv))
    wf_at_target

let () =
  Alcotest.run "gen" [ ("m17", [ QCheck_alcotest.to_alcotest qt_wf ]) ]
