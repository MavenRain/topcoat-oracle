(* Model gate. Evaluates the property table against the coupled system
   and the uncoupled negative control, plus the R0 pin-drift guard
   (our reachable closure must equal the kernel carrier). Exit 1 on
   any mismatch. *)

module T = Topos
module C = Ctlk

let build coupling =
  C.system_of Stdlib.compare (Frame.post coupling) State.init Frame.agents
    Frame.view

let holds_valid sys f = T.holds_everywhere sys.C.space (C.eval sys Props.den f)

let holds_sat sys f =
  let sub = C.eval sys Props.den f in
  List.exists sub sys.C.space.T.carrier

let check_entry label sys expect e failures =
  let got =
    match e.Props.kind with
    | Props.Valid -> holds_valid sys e.Props.form
    | Props.Satisfiable -> holds_sat sys e.Props.form
  in
  let ok = Bool.equal got expect in
  let tag = if ok then "PASS" else "FAIL" in
  print_endline
    (Printf.sprintf "%s  [%-9s] %s: got %b, expected %b" tag label
       e.Props.name got expect);
  failures + Bool.to_int (not ok)

let () =
  let sys_c = build Frame.Coupled in
  let sys_u = build Frame.Uncoupled in
  let mine =
    C.reachable Stdlib.compare (Frame.post Frame.Coupled) State.init
  in
  let kernel = sys_c.C.space.T.carrier in
  let sorted l = List.sort Stdlib.compare l in
  let reach_agree = Stdlib.compare (sorted mine) (sorted kernel) = 0 in
  print_endline
    (Printf.sprintf "R0 pin-drift reachable agree: %b (worlds: coupled %d, uncoupled %d)"
       reach_agree
       (T.size sys_c.C.space)
       (T.size sys_u.C.space));
  let failures0 = Bool.to_int (not reach_agree) in
  let failures =
    List.fold_left
      (fun acc e ->
        let acc = check_entry "coupled" sys_c e.Props.expect_coupled e acc in
        check_entry "uncoupled" sys_u e.Props.expect_uncoupled e acc)
      failures0 Props.table
  in
  (match failures with
   | 0 -> print_endline "MODEL GREEN (negative-control expectations included)"
   | n -> print_endline (Printf.sprintf "MODEL FAILURES: %d" n));
  exit (min failures 1)
