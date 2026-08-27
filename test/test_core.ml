(* M11/M12 unit-test gate: Prelude combinators, Wf.check_top positive
   and negative vectors, Obs canonical encoding vectors plus an
   injectivity sweep. House style: no match on option/result values;
   verdicts go through Result.fold / Alcotest testables. *)

open Prelude
open Ast

(* ---------- helpers ---------- *)

let f64_lit = E_lit (L_f64_bits (1, 2))

let wf_ok_ty name env e expected =
  Alcotest.(check bool)
    name true
    (Result.fold
       ~ok:(fun t -> ty_eq t expected)
       ~error:(fun _ -> false)
       (Wf.check_top env e))

let wf_err name env e expected_code =
  Alcotest.(check string)
    name expected_code
    (Result.fold
       ~ok:(fun _ -> "OK")
       ~error:Wf.wf_error_code
       (Wf.check_top env e))

(* ---------- Prelude ---------- *)

let test_nth_opt () =
  Alcotest.(check (option int)) "hit" (Some 20) (nth_opt [ 10; 20; 30 ] 1);
  Alcotest.(check (option int)) "oob" None (nth_opt [ 10; 20; 30 ] 3);
  Alcotest.(check (option int)) "negative" None (nth_opt [ 10; 20; 30 ] (-1))

let test_div_opt () =
  Alcotest.(check (option int)) "zero divisor" None (div_opt 7 0);
  Alcotest.(check (option int)) "nonzero" (Some 3) (div_opt 7 2)

let test_fold_map () =
  Alcotest.(check int) "fold sum" 10 (fold (fun a x -> a + x) 0 [ 1; 2; 3; 4 ]);
  Alcotest.(check (list int)) "map" [ 2; 4; 6 ] (map (fun x -> x * 2) [ 1; 2; 3 ])

let test_len_rev_append () =
  Alcotest.(check int) "len" 4 (len [ 9; 9; 9; 9 ]);
  Alcotest.(check (list int)) "rev" [ 3; 2; 1 ] (rev [ 1; 2; 3 ]);
  Alcotest.(check (list int)) "append" [ 1; 2; 3; 4 ] (append [ 1; 2 ] [ 3; 4 ])

let test_assoc_opt () =
  let eq = (fun a b -> a = b) in
  Alcotest.(check (option string))
    "hit" (Some "b")
    (assoc_opt eq 2 [ (1, "a"); (2, "b"); (3, "c") ]);
  Alcotest.(check (option string))
    "miss" None
    (assoc_opt eq 9 [ (1, "a"); (2, "b"); (3, "c") ])

let test_nat_to_string () =
  Alcotest.(check string) "zero" "0" (nat_to_string 0);
  Alcotest.(check string) "12345" "12345" (nat_to_string 12345);
  Alcotest.(check string) "negative clamps" "0" (nat_to_string (-7))

(* ---------- Wf positive ---------- *)

let test_wf_pos_literals () =
  wf_ok_ty "f64 literal" [] f64_lit T_f64;
  wf_ok_ty "if_else two f64 branches" []
    (E_if_else (E_lit (L_bool true), f64_lit, E_lit (L_f64_bits (3, 4))))
    T_f64;
  wf_ok_ty "some f64" [] (E_some f64_lit) (T_option T_f64)

let test_wf_pos_closure_call () =
  wf_ok_ty "closure applied to f64" []
    (E_call (E_closure ([ (0, T_f64) ], T_f64, E_var 0), [ f64_lit ]))
    T_f64

let test_wf_pos_methods () =
  wf_ok_ty "unwrap on option env var"
    [ (7, T_option T_f64) ]
    (E_method (E_var 7, M_unwrap, []))
    T_f64;
  wf_ok_ty "toggle on bool signal"
    [ (8, T_signal T_bool) ]
    (E_method (E_var 8, M_toggle, []))
    T_unit;
  wf_ok_ty "string len" []
    (E_method (E_lit (L_str "ab"), M_len, []))
    T_f64

let test_wf_pos_block_let () =
  wf_ok_ty "block let then var" []
    (E_block ([ E_let (1, f64_lit) ], E_var 1))
    T_f64

let test_wf_pos_async_await () =
  wf_ok_ty "async closure awaits async fn param" []
    (E_async_closure
       ( [ (2, T_async_fn ([], T_f64)) ],
         T_f64,
         E_await (E_call (E_var 2, [])) ))
    (T_async_fn ([ T_async_fn ([], T_f64) ], T_f64))

let test_wf_pos_while_break () =
  wf_ok_ty "while loop with break in body" []
    (E_while (E_lit (L_bool true), E_block_unit [ E_break ]))
    T_unit

let test_wf_pos_tuple_field () =
  wf_ok_ty "field 0 of (f64, f64)" []
    (E_field (E_tuple [ f64_lit; E_lit (L_f64_bits (3, 4)) ], 0))
    T_f64

(* ---------- Wf negative ---------- *)

let test_wf_neg_scope () =
  wf_err "unbound var" [] (E_var 99) "unbound";
  wf_err "break at top" [] E_break "break-outside-loop";
  wf_err "return at top" [] (E_return f64_lit) "return-outside-closure";
  wf_err "await outside async" []
    (E_await (E_call (E_var 2, [])))
    "await-outside-async"

let test_wf_neg_shapes () =
  wf_err "f64 if condition" []
    (E_if (f64_lit, E_block_unit []))
    "mismatch";
  wf_err "tuple field out of range" []
    (E_field (E_tuple [ f64_lit; E_lit (L_f64_bits (3, 4)) ], 5))
    "field-out-of-range";
  wf_err "index unsupported" []
    (E_index (E_lit (L_str "ab"), f64_lit))
    "index-unsupported";
  wf_err "deref unsupported" [] (E_unary (U_deref, f64_lit))
    "deref-unsupported"

let test_wf_neg_methods () =
  wf_err "toggle on f64 signal"
    [ (8, T_signal T_f64) ]
    (E_method (E_var 8, M_toggle, []))
    "bad-method";
  wf_err "expect with no args"
    [ (7, T_option T_f64) ]
    (E_method (E_var 7, M_expect, []))
    "arity";
  wf_err "negative f64 bits" [] (E_lit (L_f64_bits (-1, 0))) "bad-f64-bits"

(* ---------- Obs ---------- *)

let test_obs_encode_value () =
  Alcotest.(check string) "unit" "u" (Obs.encode_value Obs.V_unit);
  Alcotest.(check string) "true" "b1" (Obs.encode_value (Obs.V_bool true));
  Alcotest.(check string) "false" "b0" (Obs.encode_value (Obs.V_bool false));
  Alcotest.(check string) "f64 bits" "f1:2;"
    (Obs.encode_value (Obs.V_f64_bits (1, 2)));
  Alcotest.(check string) "str ab" "s2:ab" (Obs.encode_value (Obs.V_str "ab"));
  Alcotest.(check string) "str empty" "s0:" (Obs.encode_value (Obs.V_str ""));
  Alcotest.(check string) "tuple" "t2:b1n"
    (Obs.encode_value (Obs.V_tuple [ Obs.V_bool true; Obs.V_none ]));
  Alcotest.(check string) "some unit" "Su" (Obs.encode_value (Obs.V_some Obs.V_unit));
  Alcotest.(check string) "ok unit" "Ou" (Obs.encode_value (Obs.V_ok Obs.V_unit));
  Alcotest.(check string) "err false" "Eb0"
    (Obs.encode_value (Obs.V_err (Obs.V_bool false)));
  Alcotest.(check string) "closure" "c" (Obs.encode_value Obs.V_closure)

let test_obs_encode_outcome () =
  Alcotest.(check string) "value outcome" "Vu"
    (Obs.encode_outcome (Obs.O_value Obs.V_unit));
  Alcotest.(check string) "panic unwrap boom" "Punwrap:4:boom"
    (Obs.encode_outcome (Obs.O_panic (Obs.P_unwrap, "boom")));
  Alcotest.(check string) "no terminate" "T"
    (Obs.encode_outcome Obs.O_no_terminate)

let test_obs_encode_observation () =
  Alcotest.(check string) "full observation" "Vb1|r2:hi|g3:f0:1;"
    (Obs.encode
       {
         Obs.outcome = Obs.O_value (Obs.V_bool true);
         rendered = "hi";
         signals = [ (3, Obs.V_f64_bits (0, 1)) ];
       })

(* Injectivity: every value in a diverse corpus encodes to a code that
   appears exactly once, so all pairwise encodings are distinct. *)
let test_obs_injectivity () =
  let corpus =
    [
      Obs.V_unit;
      Obs.V_bool true;
      Obs.V_bool false;
      Obs.V_f64_bits (1, 2);
      Obs.V_f64_bits (12, 0);
      Obs.V_str "ab";
      Obs.V_str "";
      Obs.V_str "u";
      Obs.V_tuple [ Obs.V_bool true; Obs.V_none ];
      Obs.V_tuple [];
      Obs.V_none;
      Obs.V_some Obs.V_unit;
      Obs.V_some Obs.V_none;
      Obs.V_ok Obs.V_unit;
      Obs.V_err Obs.V_unit;
      Obs.V_closure;
    ]
  in
  let codes = map Obs.encode_value corpus in
  let occurrences c =
    fold (fun n c2 -> n + (if String.equal c c2 then 1 else 0)) 0 codes
  in
  let unique_count =
    fold (fun n c -> n + (if occurrences c = 1 then 1 else 0)) 0 codes
  in
  Alcotest.(check int) "all pairwise distinct" (len codes) unique_count

(* ---------- runner ---------- *)

let () =
  Alcotest.run "topcoat-oracle core"
    [
      ( "prelude",
        [
          Alcotest.test_case "nth_opt" `Quick test_nth_opt;
          Alcotest.test_case "div_opt" `Quick test_div_opt;
          Alcotest.test_case "fold/map" `Quick test_fold_map;
          Alcotest.test_case "len/rev/append" `Quick test_len_rev_append;
          Alcotest.test_case "assoc_opt" `Quick test_assoc_opt;
          Alcotest.test_case "nat_to_string" `Quick test_nat_to_string;
        ] );
      ( "wf-positive",
        [
          Alcotest.test_case "literals and constructors" `Quick
            test_wf_pos_literals;
          Alcotest.test_case "closure call" `Quick test_wf_pos_closure_call;
          Alcotest.test_case "methods" `Quick test_wf_pos_methods;
          Alcotest.test_case "block let" `Quick test_wf_pos_block_let;
          Alcotest.test_case "async await" `Quick test_wf_pos_async_await;
          Alcotest.test_case "while break" `Quick test_wf_pos_while_break;
          Alcotest.test_case "tuple field" `Quick test_wf_pos_tuple_field;
        ] );
      ( "wf-negative",
        [
          Alcotest.test_case "scope errors" `Quick test_wf_neg_scope;
          Alcotest.test_case "shape errors" `Quick test_wf_neg_shapes;
          Alcotest.test_case "method errors" `Quick test_wf_neg_methods;
        ] );
      ( "obs",
        [
          Alcotest.test_case "encode_value vectors" `Quick
            test_obs_encode_value;
          Alcotest.test_case "encode_outcome vectors" `Quick
            test_obs_encode_outcome;
          Alcotest.test_case "encode observation" `Quick
            test_obs_encode_observation;
          Alcotest.test_case "injectivity" `Quick test_obs_injectivity;
        ] );
    ]
