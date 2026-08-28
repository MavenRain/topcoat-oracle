(* M19 gate: on 1000 generated samples, EVERY shrink candidate at
   every step of a shrink chain is (a) strictly smaller under
   Shrink.size, so the chain terminates, and (b) wf at the SAME
   target type in the same environment. The walked chain follows the
   LAST candidate (the least aggressive rewrap) so chains stay long
   and exercise the structural rules, not just the collapse.
   Shrink never consults Wf -- its rules are type-preserving by
   construction -- so this re-check is independent. The deterministic
   vectors then pin each scope/escape guard one by one. *)

open Ast

let genv = Gen.default_genv
let env = Gen.wf_env genv

let show sample =
  ty_to_string (fst sample)
  ^ " :: "
  ^ Printer_rust.print Ops.printer_renderer (snd sample)

let wf_at t e =
  Result.fold
    ~ok:(fun t' -> ty_eq t t')
    ~error:(fun _e -> false)
    (Wf.check_top env e)

let rec last_opt xs =
  match xs with
  | [] -> None
  | x :: rest -> (match rest with [] -> Some x | _ :: _ -> last_opt rest)

let rec chain_ok t e =
  let cs = Shrink.cands t e in
  List.for_all (fun c -> Shrink.size c < Shrink.size e && wf_at t c) cs
  && Option.fold ~none:true ~some:(fun c -> chain_ok t c) (last_opt cs)

let qt_chain =
  QCheck.Test.make ~count:1000
    ~name:"shrink chains preserve wf at the target type"
    (QCheck.make ~print:show (Gen.gen_target genv))
    (fun sample -> chain_ok (fst sample) (snd sample))

(* Deterministic guard vectors. *)

let lit0 = E_lit (L_f64_bits (0, 0))
let lit1 = E_lit (L_f64_bits (1072693248, 0)) (* 1.0 *)

let check_cands name expected got =
  Alcotest.(check bool) name true (expected = got)

(* A tail that uses the let blocks both the unwrap and the drop: the
   only candidate left is the collapse. *)
let vec_captured_let () =
  check_cands "captured let: collapse only"
    (lit0 :: [])
    (Shrink.cands T_f64 (E_block (E_let (20, E_var 0) :: [], E_var 20)))

(* An unused let unwraps, drops, and the tail still rewraps. *)
let vec_free_let () =
  let stmt = E_let (20, E_var 0) in
  check_cands "free let: collapse, unwrap, drop, tail rewrap"
    (lit0 :: lit1
     :: E_block ([], lit1)
     :: E_block (stmt :: [], lit0)
     :: [])
    (Shrink.cands T_f64 (E_block (stmt :: [], lit1)))

(* A loop body with a top-level break must not be extracted out of the
   loop, and the break statement still drops inside it. *)
let vec_loop_escape () =
  let body = E_block_unit (E_break :: []) in
  let cs = Shrink.cands T_unit (E_loop body) in
  Alcotest.(check bool) "loop body with break stays inside" false
    (List.mem body cs);
  Alcotest.(check bool) "loop still collapses" true
    (List.mem (E_block_unit []) cs)

(* A thunk body with a return must not replace the call; without the
   return it must. *)
let vec_thunk_return () =
  let ret_body = E_return (E_var 0) in
  let guarded =
    Shrink.cands T_f64 (E_call (E_closure ([], T_f64, ret_body), []))
  in
  Alcotest.(check bool) "returning thunk body stays inside" false
    (List.mem ret_body guarded);
  let plain =
    Shrink.cands T_f64 (E_call (E_closure ([], T_f64, E_var 0), []))
  in
  Alcotest.(check bool) "plain thunk body extracts" true
    (List.mem (E_var 0) plain)

(* Awaiting an immediately-called async thunk collapses to its body. *)
let vec_await_collapse () =
  let e = E_await (E_call (E_async_closure ([], T_f64, lit1), [])) in
  Alcotest.(check bool) "await of async thunk extracts body" true
    (List.mem lit1 (Shrink.cands T_f64 e))

(* Minimal values: future wraps an async thunk call, the result falls
   back to the Err side when Ok is unconstructible, and signal/tuple
   types have no closed inhabitant. *)
let vec_minimal () =
  Alcotest.(check bool) "minimal future" true
    (Shrink.minimal (T_future T_bool)
     = Some (E_call (E_async_closure ([], T_bool, E_lit (L_bool false)), [])));
  Alcotest.(check bool) "minimal result err fallback" true
    (Shrink.minimal (T_result (T_signal T_f64, T_bool))
     = Some (E_err (E_lit (L_bool false), T_signal T_f64)));
  Alcotest.(check bool) "no minimal signal" true
    (Shrink.minimal (T_signal T_f64) = None);
  Alcotest.(check bool) "no minimal tuple" true
    (Shrink.minimal (T_tuple []) = None)

(* A never-coerced return in a type-changing position must not arm the
   E_return rules: wf checks the payload against the closure's return
   type, not the position's target (review finding, 2026-08-27). *)
let vec_return_coercion () =
  let body = E_some (E_return (E_none T_f64)) in
  let f = E_closure ([], T_option T_f64, body) in
  let tf = T_fn ([], T_option T_f64) in
  Alcotest.(check bool) "closure wf at its type" true (wf_at tf f);
  Alcotest.(check bool) "all candidates stay wf" true
    (List.for_all (fun c -> wf_at tf c) (Shrink.cands tf f));
  Alcotest.(check bool) "ill-typed payload extraction absent" false
    (List.mem
       (E_closure ([], T_option T_f64, E_some (E_none T_f64)))
       (Shrink.cands tf f))

let () =
  Alcotest.run "shrink"
    [
      ("m19-chains", [ QCheck_alcotest.to_alcotest qt_chain ]);
      ( "m19-guards",
        [
          Alcotest.test_case "captured let" `Quick vec_captured_let;
          Alcotest.test_case "free let" `Quick vec_free_let;
          Alcotest.test_case "loop escape" `Quick vec_loop_escape;
          Alcotest.test_case "thunk return" `Quick vec_thunk_return;
          Alcotest.test_case "await collapse" `Quick vec_await_collapse;
          Alcotest.test_case "minimal values" `Quick vec_minimal;
          Alcotest.test_case "return coercion" `Quick vec_return_coercion;
        ] );
    ]
