(* M14/M15 gate: floatops golden vectors from the rustc probe
   (research/m13-rust-render-probe.md), QCheck bit-exact round-trips
   on random bit patterns, strops vectors, real-renderer printer
   goldens, and hand-written interpreter vectors per construct.
   House style: no match on option/result values; verdicts through
   Option.fold / Alcotest testables. *)

open Ast
open Obs

(* ---------- helpers ---------- *)

let bits x = Floatops.of_float x

let fl x = E_lit (L_f64_bits (fst (bits x), snd (bits x)))

let vf x = V_f64_bits (fst (bits x), snd (bits x))

let ivf x = Interp.I_f64 (fst (bits x), snd (bits x))

let run ?(inputs = []) ?(sigs = []) ?(fuel = 10000) e : Interp.run_result =
  Interp.eval_top Ops.interp_ops inputs sigs fuel e

let chk_out name expected (r : Interp.run_result) =
  Alcotest.(check string)
    name
    (encode_outcome expected)
    (encode_outcome r.outcome)

let chk_sigs name expected (r : Interp.run_result) =
  Alcotest.(check string)
    name
    (encode_signals expected)
    (encode_signals r.signals)

(* ---------- floatops goldens (rustc probe vectors) ---------- *)

let dd name x exp_d exp_q =
  let p = bits x in
  Alcotest.(check string)
    (name ^ " display") exp_d
    (Floatops.f_display (fst p) (snd p));
  Alcotest.(check string)
    (name ^ " debug") exp_q
    (Floatops.f_debug (fst p) (snd p))

let test_float_render () =
  dd "one" 1.0 "1" "1.0";
  dd "1e300" 1e300 ("1" ^ String.make 300 '0') "1e300";
  dd "1e16" 1e16 "10000000000000000" "1e16";
  dd "1e15" 1e15 "1000000000000000" "1000000000000000.0";
  dd "5e-324" 5e-324 ("0." ^ String.make 323 '0' ^ "5") "5e-324";
  dd "1e-5" 1e-5 "0.00001" "1e-5";
  dd "tenth" 0.1 "0.1" "0.1";
  dd "neg zero" (-0.0) "-0" "-0.0";
  dd "inf" infinity "inf" "inf";
  dd "neg inf" neg_infinity "-inf" "-inf";
  dd "nan" nan "NaN" "NaN";
  dd "1.5e-7" 1.5e-7 "0.00000015" "1.5e-7";
  dd "large sig" 123456789012345680.0 "123456789012345680"
    "1.2345678901234568e17"

let test_float_literal () =
  let lit x =
    let p = bits x in
    Floatops.f_literal (fst p) (snd p)
  in
  Alcotest.(check string) "1.5" "1.5" (lit 1.5);
  Alcotest.(check string) "-0.0" "-0.0" (lit (-0.0));
  Alcotest.(check string) "-0.25" "-0.25" (lit (-0.25));
  Alcotest.(check string) "nan marker" "f64::NAN" (lit nan)

(* ---------- QCheck round-trips on random bit patterns ---------- *)

let split_bits b =
  ( Int64.to_int (Int64.shift_right_logical b 32),
    Int64.to_int (Int64.logand b 0xFFFFFFFFL) )

let roundtrip render b =
  let p = split_bits b in
  Option.fold ~none:false
    ~some:(fun v -> Int64.equal (Int64.bits_of_float v) b)
    (float_of_string_opt (render (fst p) (snd p)))

let qt_display =
  QCheck.Test.make ~count:1000 ~name:"display bit-exact roundtrip"
    QCheck.int64 (fun b ->
      Float.is_nan (Int64.float_of_bits b) || roundtrip Floatops.f_display b)

let qt_debug =
  QCheck.Test.make ~count:1000 ~name:"debug bit-exact roundtrip"
    QCheck.int64 (fun b ->
      Float.is_nan (Int64.float_of_bits b) || roundtrip Floatops.f_debug b)

let qt_literal =
  QCheck.Test.make ~count:1000 ~name:"literal bit-exact roundtrip"
    QCheck.int64 (fun b ->
      match Float.classify_float (Int64.float_of_bits b) with
      | FP_nan | FP_infinite -> true
      | FP_zero | FP_normal | FP_subnormal ->
          roundtrip Floatops.f_literal b)

(* ---------- strops ---------- *)

let ws_probe = "\xc2\x85x\xc2\xa0\xe3\x80\x80y\xe2\x80\xa8 "

let test_strops_trim () =
  Alcotest.(check string)
    "trim_start" "x\xc2\xa0\xe3\x80\x80y\xe2\x80\xa8 "
    (Strops.trim_start ws_probe);
  Alcotest.(check string)
    "trim_end" "\xc2\x85x\xc2\xa0\xe3\x80\x80y"
    (Strops.trim_end ws_probe);
  Alcotest.(check string)
    "trim" "x\xc2\xa0\xe3\x80\x80y" (Strops.trim ws_probe)

let test_strops_misc () =
  Alcotest.(check string)
    "debug escapes"
    "\"a\\\"b\\\\c\\nd\\0e\\u{7f}\\u{1b}\xc3\xa9\""
    (Strops.debug "a\"b\\c\nd\x00e\x7f\x1b\xc3\xa9");
  Alcotest.(check bool) "z before e-acute (byte order)" true
    (Strops.cmp "z" "\xc3\xa9" < 0);
  Alcotest.(check bool) "contains" true (Strops.contains "abcd" "bc");
  Alcotest.(check bool) "contains empty needle" true
    (Strops.contains "abcd" "");
  Alcotest.(check bool) "contains miss" false (Strops.contains "abcd" "ca");
  Alcotest.(check bool) "starts_with" true (Strops.starts_with "abcd" "ab");
  Alcotest.(check bool) "ends_with" true (Strops.ends_with "abcd" "cd")

(* ---------- printer with the real renderer ---------- *)

let test_printer_real () =
  let p e = Printer_rust.print Ops.printer_renderer e in
  Alcotest.(check string) "lit 1.5" "1.5" (p (fl 1.5));
  Alcotest.(check string) "lit -0.0" "-0.0" (p (fl (-0.0)));
  Alcotest.(check string) "sum of literals" "(1.5) + (-0.25)"
    (p (E_binary (B_add, fl 1.5, fl (-0.25))));
  Alcotest.(check string) "string literal" "\"a\\nb\""
    (p (E_lit (L_str "a\nb")))

(* ---------- interpreter vectors ---------- *)

let test_interp_arith () =
  chk_out "0.1 + 0.2" (O_value (vf 0.30000000000000004))
    (run (E_binary (B_add, fl 0.1, fl 0.2)));
  chk_out "1.0 / 0.0 = inf" (O_value (vf infinity))
    (run (E_binary (B_div, fl 1.0, fl 0.0)));
  chk_out "NaN == NaN" (O_value (V_bool false))
    (run (E_binary (B_eq, fl nan, fl nan)));
  chk_out "NaN != NaN" (O_value (V_bool true))
    (run (E_binary (B_ne, fl nan, fl nan)));
  chk_out "-0.0 == 0.0" (O_value (V_bool true))
    (run (E_binary (B_eq, fl (-0.0), fl 0.0)));
  chk_out "string byte order" (O_value (V_bool true))
    (run (E_binary (B_lt, E_lit (L_str "z"), E_lit (L_str "\xc3\xa9"))))

let test_interp_panics () =
  chk_out "unwrap None"
    (O_panic (P_unwrap, "called `Option::unwrap()` on a `None` value"))
    (run (E_method (E_none T_f64, M_unwrap, [])));
  chk_out "unwrap Err"
    (O_panic (P_unwrap, "called `Result::unwrap()` on an `Err` value: 1.5"))
    (run (E_method (E_err (fl 1.5, T_f64), M_unwrap, [])));
  chk_out "expect Err"
    (O_panic (P_expect, "boom: 1.5"))
    (run
       (E_method (E_err (fl 1.5, T_f64), M_expect, [ E_lit (L_str "boom") ])));
  chk_out "unwrap_err Ok"
    (O_panic
       (P_unwrap_err, "called `Result::unwrap_err()` on an `Ok` value: \"a\""))
    (run (E_method (E_ok (E_lit (L_str "a"), T_f64), M_unwrap_err, [])))

let test_interp_closures () =
  chk_out "closure call" (O_value (vf 3.5))
    (run
       (E_call
          ( E_closure
              ([ (0, T_f64) ], T_f64, E_binary (B_add, E_var 0, fl 1.0)),
            [ fl 2.5 ] )));
  let writer =
    E_closure
      ( [],
        T_f64,
        E_block ([ E_method (E_var 7, M_set, [ fl 9.0 ]) ], fl 3.0) )
  in
  let r_false =
    run ~sigs:[ (7, ivf 0.0) ]
      (E_method (E_lit (L_bool false), M_then, [ writer ]))
  in
  chk_out "false.then value" (O_value V_none) r_false;
  chk_sigs "false.then leaves signal (lazy)" [ (7, vf 0.0) ] r_false;
  let r_true =
    run ~sigs:[ (7, ivf 0.0) ]
      (E_method (E_lit (L_bool true), M_then, [ writer ]))
  in
  chk_out "true.then value" (O_value (V_some (vf 3.0))) r_true;
  chk_sigs "true.then writes signal" [ (7, vf 9.0) ] r_true;
  let r_eager =
    run ~sigs:[ (7, ivf 0.0) ]
      (E_method
         ( E_lit (L_bool false),
           M_then_some,
           [ E_block ([ E_method (E_var 7, M_set, [ fl 9.0 ]) ], fl 7.0) ] ))
  in
  chk_out "false.then_some value" (O_value V_none) r_eager;
  chk_sigs "then_some argument is eager" [ (7, vf 9.0) ] r_eager

let test_interp_signals () =
  let r =
    run ~sigs:[ (7, ivf 0.0) ]
      (E_block
         ( [
             E_method (E_var 7, M_set, [ fl 5.0 ]);
             E_method (E_var 7, M_increment, []);
           ],
           E_method (E_var 7, M_get, []) ))
  in
  chk_out "set/increment/get" (O_value (vf 6.0)) r;
  chk_sigs "final store" [ (7, vf 6.0) ] r;
  let r2 =
    run ~sigs:[ (8, Interp.I_bool false) ]
      (E_block_unit [ E_method (E_var 8, M_toggle, []) ])
  in
  chk_out "toggle outcome" (O_value V_unit) r2;
  chk_sigs "toggle final" [ (8, V_bool true) ] r2;
  let r3 =
    run ~sigs:[ (9, Interp.I_str "a") ]
      (E_block_unit
         [ E_method (E_var 9, M_push_str, [ E_lit (L_str "bc") ]) ])
  in
  chk_sigs "push_str final" [ (9, V_str "abc") ] r3;
  let r4 =
    run ~sigs:[ (7, ivf 1.0) ]
      (E_block
         ( [
             E_let (1, E_method (E_var 7, M_clone, []));
             E_method (E_var 1, M_set, [ fl 4.0 ]);
           ],
           E_method (E_var 7, M_get, []) ))
  in
  chk_out "clone aliases the signal" (O_value (vf 4.0)) r4

let test_interp_loops () =
  let r =
    run ~sigs:[ (7, ivf 0.0) ]
      (E_block
         ( [
             E_while
               ( E_binary (B_lt, E_method (E_var 7, M_get, []), fl 3.0),
                 E_block_unit [ E_method (E_var 7, M_increment, []) ] );
           ],
           E_method (E_var 7, M_get, []) ))
  in
  chk_out "while counts to 3" (O_value (vf 3.0)) r;
  chk_out "bare loop exhausts fuel" O_no_terminate
    (run ~fuel:1000 (E_loop (E_block_unit [])));
  chk_out "loop with break" (O_value V_unit)
    (run (E_loop (E_block_unit [ E_break ])))

let test_interp_async () =
  let writer = E_async_closure ([], T_unit, E_method (E_var 7, M_set, [ fl 9.9 ])) in
  let r =
    run ~sigs:[ (7, ivf 0.0) ]
      (E_block
         ([ E_let (1, E_call (writer, [])) ], E_lit (L_bool true)))
  in
  chk_out "unawaited call value" (O_value (V_bool true)) r;
  chk_sigs "future is lazy: no write" [ (7, vf 0.0) ] r;
  (* wf rejects top-level await (in_async = false); the interpreter
     is total over the AST and models the leg behavior directly. *)
  let r2 = run ~sigs:[ (7, ivf 0.0) ] (E_await (E_call (writer, []))) in
  chk_out "awaited value" (O_value V_unit) r2;
  chk_sigs "await runs the body" [ (7, vf 9.9) ] r2

let test_interp_misc () =
  chk_out "let shadowing" (O_value (vf 2.0))
    (run
       (E_block
          ( [
              E_let (1, fl 1.0);
              E_let (1, E_binary (B_add, E_var 1, fl 1.0));
            ],
            E_var 1 )));
  chk_out "tuple field projection" (O_value (V_bool true))
    (run
       ~inputs:[ (3, Interp.I_tuple [ ivf 1.5; Interp.I_bool true ]) ]
       (E_field (E_var 3, 1)));
  chk_out "trim" (O_value (V_str "ab"))
    (run (E_method (E_lit (L_str " ab "), M_trim, [])));
  chk_out "trim_start" (O_value (V_str "ab "))
    (run (E_method (E_lit (L_str " ab "), M_trim_start, [])));
  chk_out "trim_end" (O_value (V_str " ab"))
    (run (E_method (E_lit (L_str " ab "), M_trim_end, [])));
  chk_out "len is byte length" (O_value (vf 7.0))
    (run (E_method (E_lit (L_str "a\xc3\xa9\xf0\x9f\x98\x80"), M_len, [])));
  chk_out "if_else value" (O_value (vf 1.5))
    (run (E_if_else (E_lit (L_bool true), fl 1.5, fl 2.5)))

(* ---------- runner ---------- *)

let () =
  Alcotest.run "topcoat-oracle shell"
    [
      ( "floatops",
        [
          Alcotest.test_case "render goldens" `Quick test_float_render;
          Alcotest.test_case "literal goldens" `Quick test_float_literal;
          QCheck_alcotest.to_alcotest qt_display;
          QCheck_alcotest.to_alcotest qt_debug;
          QCheck_alcotest.to_alcotest qt_literal;
        ] );
      ( "strops",
        [
          Alcotest.test_case "trim family" `Quick test_strops_trim;
          Alcotest.test_case "debug/cmp/search" `Quick test_strops_misc;
        ] );
      ( "printer-real",
        [ Alcotest.test_case "real renderer" `Quick test_printer_real ] );
      ( "interp",
        [
          Alcotest.test_case "arith/eq" `Quick test_interp_arith;
          Alcotest.test_case "panics" `Quick test_interp_panics;
          Alcotest.test_case "closures/then" `Quick test_interp_closures;
          Alcotest.test_case "signals" `Quick test_interp_signals;
          Alcotest.test_case "loops/fuel" `Quick test_interp_loops;
          Alcotest.test_case "async laziness" `Quick test_interp_async;
          Alcotest.test_case "blocks/strings/misc" `Quick test_interp_misc;
        ] );
    ]
