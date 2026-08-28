(* M20 gate tests (DESIGN.md M20; scope in
   research/m20-expr-macro-probe.md round 2):
   - 1000 samples at seed 0x4d3230 through the m20 config are all
     m20_safe AND wf at the drawn target type;
   - the banned-constructor tally (M18 style) is all-zero;
   - the emitter is byte-deterministic (fresh draw, same seed, same
     bytes);
   - m20_safe rejects a banned AST outright (mutation-tooth anchor:
     blinding the auditor turns exactly this vector red). *)

open Ast

let genv = M20.genv
let env = Gen.wf_env genv
let n = 1000
let seed = 0x4d3230

let draw () =
  QCheck.Gen.generate ~n
    ~rand:(Random.State.make [| seed |])
    (Gen.gen_target_m20 genv)

let samples = draw ()

let show sample =
  ty_to_string (fst sample)
  ^ " :: "
  ^ Printer_rust.print Ops.printer_renderer (snd sample)

let wf_at_target sample =
  Result.fold
    ~ok:(fun t -> ty_eq (fst sample) t)
    ~error:(fun _e -> false)
    (Wf.check_top env (snd sample))

let check_safe () =
  let bad = List.filter (fun s -> not (M20.m20_safe (snd s))) samples in
  Alcotest.(check (list string)) "every sample m20_safe" []
    (List.map show bad)

let check_wf () =
  let bad = List.filter (fun s -> not (wf_at_target s)) samples in
  Alcotest.(check (list string)) "every sample wf at target" []
    (List.map show bad)

let banned =
  [
    "E_call"; "E_await"; "E_closure"; "E_async_closure"; "E_some"; "E_none";
    "E_ok"; "E_err"; "E_tuple"; "E_field"; "E_index"; "E_return";
    "E_return_unit"; "U_deref"; "M_trim"; "M_trim_start"; "M_trim_end";
    "M_then"; "T_fn"; "T_async_fn"; "T_future"; "T_tuple"; "T_signal";
  ]

let counts = Tally.of_samples samples

let check_banned_zero () =
  let hit = List.filter (fun k -> Tally.count k counts > 0) banned in
  Alcotest.(check (list string)) "banned constructors stay at zero" [] hit

let batch samples_in =
  Emit.crate_files ~name:"m20-batch" ~dep_prefix:"../../../"
    (Emit.batch_cases samples_in)

let check_deterministic () =
  Alcotest.(check (list (pair string string)))
    "emit twice, identical bytes" (batch samples) (batch (draw ()))

let check_banned_vector () =
  Alcotest.(check bool) "m20_safe rejects E_call" false
    (M20.m20_safe (E_call (E_var 0, [])))

let check_signal_meth_receiver () =
  Alcotest.(check bool) "m20_safe rejects M_get off a cloned receiver"
    false
    (M20.m20_safe (E_method (E_method (E_var 2, M_clone, []), M_get, [])))

let check_stray_break () =
  Alcotest.(check bool) "m20_safe rejects a loopless break" false
    (M20.m20_safe E_break)

let check_while_cond_break () =
  Alcotest.(check bool) "m20_safe rejects a while-condition break" false
    (M20.m20_safe (E_loop (E_while (E_break, E_block_unit []))))

let () =
  Alcotest.run "emit"
    [
      ( "m20",
        [
          Alcotest.test_case "1k samples m20_safe" `Quick check_safe;
          Alcotest.test_case "1k samples wf at target" `Quick check_wf;
          Alcotest.test_case "banned tally all-zero" `Quick check_banned_zero;
          Alcotest.test_case "emitter deterministic" `Quick
            check_deterministic;
          Alcotest.test_case "m20_safe rejects banned AST" `Quick
            check_banned_vector;
          Alcotest.test_case "m20_safe rejects nested-clone signal meth"
            `Quick check_signal_meth_receiver;
          Alcotest.test_case "m20_safe rejects loopless break" `Quick
            check_stray_break;
          Alcotest.test_case "m20_safe rejects while-cond break" `Quick
            check_while_cond_break;
        ] );
    ]
