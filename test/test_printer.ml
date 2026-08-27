(* M13 printer golden tests with a STUB renderer: structural goldens
   only, so this executable stays core-only (no shell float
   rendering). Real-renderer goldens live in test_shell.ml. House
   style: no match on option/result values. *)

open Prelude
open Ast

let stub =
  {
    Printer_rust.lit_f64 =
      (fun hi lo -> "f" ^ nat_to_string hi ^ "_" ^ nat_to_string lo);
    lit_str = (fun s -> "\"" ^ s ^ "\"");
  }

let g name expected e =
  Alcotest.(check string) name expected (Printer_rust.print stub e)

let test_atoms () =
  g "var" "v3" (E_var 3);
  g "bool" "true" (E_lit (L_bool true));
  g "str" "\"hi\"" (E_lit (L_str "hi"));
  g "f64 stub" "f1_2" (E_lit (L_f64_bits (1, 2)))

let test_operators () =
  g "nested binary parens" "(v0 + v1) * v2"
    (E_binary (B_mul, E_binary (B_add, E_var 0, E_var 1), E_var 2));
  g "f64 literal operand parens" "(f1_2) + v0"
    (E_binary (B_add, E_lit (L_f64_bits (1, 2)), E_var 0));
  g "neg" "-v0" (E_unary (U_neg, E_var 0));
  g "not" "!v0" (E_unary (U_not, E_var 0));
  g "deref prints though wf rejects" "*v0" (E_unary (U_deref, E_var 0))

let test_calls_methods () =
  g "method chain" "v0.trim().len()"
    (E_method (E_method (E_var 0, M_trim, []), M_len, []));
  g "method on non-atomic receiver" "(v0 + v1).clone()"
    (E_method (E_binary (B_add, E_var 0, E_var 1), M_clone, []));
  g "nested tuple field" "v0.0.1" (E_field (E_field (E_var 0, 0), 1));
  g "closure call" "(|v0: f64| -> f64 { v0 })(v1)"
    (E_call (E_closure ([ (0, T_f64) ], T_f64, E_var 0), [ E_var 1 ]));
  g "index prints though wf rejects" "v0[v1]"
    (E_index (E_var 0, E_var 1))

let test_constructors () =
  g "some" "Some(v0)" (E_some (E_var 0));
  g "none turbofish" "None::<f64>" (E_none T_f64);
  g "ok" "Ok(v0)" (E_ok (E_var 0, T_bool));
  g "err" "Err(v1)" (E_err (E_var 1, T_f64));
  (* Tuple expressions have no syn::Expr::Tuple dispatch arm in the
     macro; the printer stays total anyway. *)
  g "unit tuple" "()" (E_tuple []);
  g "one-tuple" "(v0,)" (E_tuple [ E_var 0 ]);
  g "pair" "(v0, v1)" (E_tuple [ E_var 0; E_var 1 ])

let test_blocks () =
  g "block with let and stmt" "{ let v1 = v0; v1.clone(); v1 }"
    (E_block
       ( [ E_let (1, E_var 0); E_method (E_var 1, M_clone, []) ],
         E_var 1 ));
  g "empty unit block" "{ }" (E_block_unit []);
  g "bare let becomes unit block" "{ let v1 = v0; }" (E_let (1, E_var 0))

let test_control () =
  g "if with non-atomic cond" "if (v0 < v1) { }"
    (E_if (E_binary (B_lt, E_var 0, E_var 1), E_block_unit []));
  g "else-if chain" "if v0 { v1 } else if v2 { v3 } else { v4 }"
    (E_if_else
       ( E_var 0,
         E_block ([], E_var 1),
         E_if_else
           (E_var 2, E_block ([], E_var 3), E_block ([], E_var 4)) ));
  g "non-block branches get braces" "if v0 { v1 } else { v2 }"
    (E_if_else (E_var 0, E_var 1, E_var 2));
  g "loop break" "loop { break; }" (E_loop (E_block_unit [ E_break ]));
  g "while continue" "while v0 { continue; }"
    (E_while (E_var 0, E_block_unit [ E_continue ]))

let test_closures () =
  g "unit closure with return" "|| -> () { return }"
    (E_closure ([], T_unit, E_return_unit));
  g "async closure with await" "async |v0: f64| -> f64 { v1().await }"
    (E_async_closure
       ( [ (0, T_f64) ],
         T_f64,
         E_await (E_call (E_var 1, [])) ))

let () =
  Alcotest.run "topcoat-oracle printer"
    [
      ( "printer",
        [
          Alcotest.test_case "atoms" `Quick test_atoms;
          Alcotest.test_case "operators" `Quick test_operators;
          Alcotest.test_case "calls/methods" `Quick test_calls_methods;
          Alcotest.test_case "constructors" `Quick test_constructors;
          Alcotest.test_case "blocks" `Quick test_blocks;
          Alcotest.test_case "control" `Quick test_control;
          Alcotest.test_case "closures" `Quick test_closures;
        ] );
    ]
