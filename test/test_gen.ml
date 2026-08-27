(* M17 gate: 1000 generated samples; wf accepts each one and infers
   exactly the drawn target type. The printer renders failures for
   the QCheck counterexample report.

   M18 gate: 10k samples from a fixed seed, tallied by constructor.
   Every constructor the generator can reach appears at least once;
   the excluded set (E_tuple, E_field, E_index, U_deref, T_tuple:
   unconstructible under expr! or wf-rejected) stays at zero. The
   fixed seed keeps the tally and the counter report deterministic;
   the report prints before the alcotest run. *)

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

(* M18 coverage tally. *)

let n_m18 = 10_000

let samples_m18 =
  QCheck.Gen.generate ~n:n_m18
    ~rand:(Random.State.make [| 0x4d3138 |])
    (Gen.gen_target genv)

let counts = Tally.of_samples samples_m18

let required =
  [
    "E_lit"; "E_var"; "E_unary"; "E_binary"; "E_some"; "E_none"; "E_ok";
    "E_err"; "E_call"; "E_method"; "E_let"; "E_block"; "E_block_unit";
    "E_if"; "E_if_else"; "E_loop"; "E_while"; "E_break"; "E_continue";
    "E_return_unit"; "E_return"; "E_closure"; "E_async_closure"; "E_await";
    "L_f64_bits"; "L_bool"; "L_str"; "U_neg"; "U_not"; "B_add"; "B_sub";
    "B_mul"; "B_div"; "B_eq"; "B_ne"; "B_lt"; "B_le"; "B_gt"; "B_ge";
    "M_then"; "M_then_some"; "M_len"; "M_is_empty"; "M_trim";
    "M_trim_start"; "M_trim_end"; "M_starts_with"; "M_ends_with";
    "M_contains"; "M_to_owned"; "M_is_some"; "M_is_none"; "M_is_ok";
    "M_is_err"; "M_ok"; "M_err"; "M_unwrap_err"; "M_expect_err";
    "M_unwrap"; "M_expect"; "M_get"; "M_set"; "M_toggle"; "M_increment";
    "M_decrement"; "M_push_str"; "M_clone"; "T_f64"; "T_bool"; "T_string";
    "T_unit"; "T_option"; "T_result"; "T_fn"; "T_async_fn"; "T_future";
    "T_signal";
  ]

let excluded = [ "E_tuple"; "E_field"; "E_index"; "U_deref"; "T_tuple" ]

let check_reached () =
  let missing = List.filter (fun k -> Tally.count k counts = 0) required in
  Alcotest.(check (list string)) "all required constructors reached" [] missing

let check_excluded () =
  let hit = List.filter (fun k -> Tally.count k counts > 0) excluded in
  Alcotest.(check (list string)) "excluded constructors stay at zero" [] hit

let () =
  print_string
    ("m18 counter report (n=" ^ string_of_int n_m18 ^ ", seed 0x4d3138)\n");
  print_string (Tally.report counts);
  Alcotest.run "gen"
    [
      ("m17", [ QCheck_alcotest.to_alcotest qt_wf ]);
      ( "m18",
        [
          Alcotest.test_case "required reached at 10k" `Quick check_reached;
          Alcotest.test_case "excluded stay zero" `Quick check_excluded;
        ] );
    ]
