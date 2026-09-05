(* M29 minimizer suite (DESIGN.md M29, M29 spec section 10).  PURE: the
   oracle is a function over samples, no leg runs and no file is
   touched, so this suite is fast and deterministic.

   Every expectation is a literal derived by hand in M29 spec section 8.
   The two walks the gate measures with real legs are the same walks
   this suite drives with a fake oracle that accepts everything, so a
   change in the candidate order breaks BOTH, and the cheap one breaks
   first. *)

let target : Differ.verdict =
  Differ.Diverge (Differ.Ch_value, Differ.Odd Differ.L_js)

let other : Differ.verdict =
  Differ.Diverge (Differ.Ch_rendered, Differ.Odd Differ.L_ref)

(* An oracle that answers the same verdict for every candidate. *)
let fixed (v : Differ.verdict) : Minimize.oracle =
  {
    Minimize.o_run =
      (fun ~round:_ cs -> List.map (fun _ -> Minimize.A_verdict v) cs);
  }

(* An oracle that answers a no-verdict for every candidate. *)
let silent : Minimize.oracle =
  {
    Minimize.o_run =
      (fun ~round:_ cs ->
        List.map (fun _ -> Minimize.A_no_verdict "no line") cs);
  }

let always : Minimize.oracle = fixed target
let never : Minimize.oracle = fixed Differ.Agree
let wrong_channel : Minimize.oracle = fixed other

(* An oracle that answers the target CHANNEL but the other odd leg.  It
   exercises the split half of the preserve test, which the wrong_channel
   oracle cannot reach because that one differs on the channel first. *)
let wrong_split : Minimize.oracle =
  fixed (Differ.Diverge (Differ.Ch_value, Differ.Odd Differ.L_ref))

let failing : Minimize.oracle =
  fixed (Differ.Leg_fail (Differ.L_js, "the js driver timed out"))

let cfg : Minimize.config = Minimize.default_config
let one : Minimize.config = { Minimize.fuel = 1 }

let walk (o : Minimize.oracle) (c : Minimize.config) (s : Sample.t) :
    Minimize.result =
  Minimize.run o c ~target s

(* The accepted index of every step, as a list, so a trace is compared
   as data and not as text. *)
let picks (r : Minimize.result) : int list =
  List.filter_map
    (fun st ->
      match st.Minimize.st_accepted with
      | Minimize.Acc_none -> None
      | Minimize.Acc_index i -> Some i)
    r.Minimize.m_trace

let sizes (r : Minimize.result) : int list =
  List.map (fun st -> st.Minimize.st_size) r.Minimize.m_trace

let cands (r : Minimize.result) : int list =
  List.map (fun st -> st.Minimize.st_cands) r.Minimize.m_trace

(* Strictly decreasing, which is the termination argument measured. *)
let rec decreasing (xs : int list) : bool =
  match xs with
  | [] -> true
  | _ :: [] -> true
  | a :: b :: rest -> a > b && decreasing (b :: rest)

let stopped_at_fixpoint (r : Minimize.result) : bool =
  match r.Minimize.m_stop with
  | Minimize.Fixpoint -> true
  | Minimize.Fuel -> false
  | Minimize.Stuck _ -> false

(* The stop reason as one word or, for Stuck, its carried reason text, so
   a check can name the reason the fake oracle planted. *)
let stop_reason (r : Minimize.result) : string =
  match r.Minimize.m_stop with
  | Minimize.Fixpoint -> "fixpoint"
  | Minimize.Fuel -> "fuel"
  | Minimize.Stuck why -> why

let mode_name_of (s : Sample.t) : string = Taxonomy.mode_name s.Sample.mode

(* A Signal_writing sample whose collapse candidate is Read_only, so the
   recomputation of the mode is visible. *)
let writer : Sample.t =
  {
    Sample.mode = Taxonomy.Signal_writing;
    Sample.inputs = [];
    Sample.signals =
      [
        {
          Sample.id = 4;
          Sample.ty = Ast.T_bool;
          Sample.init = Ast.E_lit (Ast.L_bool false);
        };
      ];
    Sample.target = Ast.T_unit;
    Sample.body = Ast.E_method (Ast.E_var 4, Ast.M_toggle, []);
  }

let wf_ok (s : Sample.t) : bool =
  Result.fold
    ~ok:(fun t -> t = s.Sample.target)
    ~error:(fun _ -> false)
    (Wf.check_top (Sample.wf_env s) s.Sample.body)

let ref_run : Minimize.result = walk always cfg M29_cases.ref_case
let js_run : Minimize.result = walk always cfg M29_cases.js_case
let none_run : Minimize.result = walk never cfg M29_cases.ref_case
let fuel_run : Minimize.result = walk always one M29_cases.ref_case
let blind_run : Minimize.result = walk silent cfg M29_cases.js_case

let checks : (string * bool) list =
  [
    ("ref start size is 6", Minimize.size_of M29_cases.ref_case = 6);
    ("js start size is 13", Minimize.size_of M29_cases.js_case = 13);
    ("ref walk enters 5 rounds", ref_run.Minimize.m_rounds = 5);
    ("ref walk offers 10 candidates", ref_run.Minimize.m_evaluated = 10);
    ("ref walk sizes are 6 4 3 2 1", sizes ref_run = [ 6; 4; 3; 2; 1 ]);
    ("ref walk counts are 4 3 2 1 0", cands ref_run = [ 4; 3; 2; 1; 0 ]);
    ( "ref walk takes the first candidate every round",
      picks ref_run = [ 0; 0; 0; 0 ] );
    ("ref walk ends at size 1", Minimize.size_of ref_run.Minimize.m_final = 1);
    ("ref walk stops at a fixpoint", stopped_at_fixpoint ref_run);
    ("ref walk shrinks strictly", decreasing (sizes ref_run));
    (* This walk runs on the accept-everything oracle, so round 0 takes
       the collapse candidate that the PLANTED js run refuses (M29 spec
       6.1).  The sizes here are 13 5 4 3 2 1.  The 13 8 6 5 4 3 of the
       hand-derived real-leg walk (M29 spec 8.3) belongs to the gate,
       which measures it with the three legs.  Deviation D2 of the M29
       part 1 report. *)
    ("js walk sizes are 13 5 4 3 2 1", sizes js_run = [ 13; 5; 4; 3; 2; 1 ]);
    ("js walk shrinks strictly", decreasing (sizes js_run));
    ("a refusing oracle stops at once", none_run.Minimize.m_rounds = 1);
    ( "a refusing oracle keeps the sample",
      Minimize.size_of none_run.Minimize.m_final = 6 );
    ("a refusing oracle reports a fixpoint", stopped_at_fixpoint none_run);
    ("a fuel of one enters one round", fuel_run.Minimize.m_rounds = 1);
    ("a fuel of one reports a fuel stop", stop_reason fuel_run = "fuel");
    ( "a fuel stop keeps the accepted candidate",
      Minimize.size_of fuel_run.Minimize.m_final = 4 );
    ( "a wrong channel is refused",
      (walk wrong_channel cfg M29_cases.js_case).Minimize.m_rounds = 1 );
    ( "a wrong odd leg is refused",
      (walk wrong_split cfg M29_cases.js_case).Minimize.m_rounds = 1 );
    ( "a leg failure is refused",
      (walk failing cfg M29_cases.js_case).Minimize.m_rounds = 1 );
    ("a no-verdict is refused", blind_run.Minimize.m_rounds = 1);
    ( "a blind round does not report a fixpoint",
      not (stopped_at_fixpoint blind_run) );
    ( "a blind round reports Stuck with the batch reason",
      stop_reason blind_run = "no line" );
    ("a blind round accepts nothing", picks blind_run = []);
    ( "a blind round keeps the sample",
      Minimize.size_of blind_run.Minimize.m_final = 13 );
    ( "a leg failure keeps the sample",
      Minimize.size_of (walk failing cfg M29_cases.js_case).Minimize.m_final
      = 13 );
    ( "the collapse candidate recomputes the mode",
      Option.fold ~none:false
        ~some:(fun s -> mode_name_of s = "read_only")
        (Prelude.nth_opt (Minimize.candidates writer) 0) );
    ( "a drop candidate is offered for an unmentioned binding",
      Prelude.len
        (Minimize.candidates
           {
             M29_cases.ref_case with
             Sample.body = Ast.E_lit (Ast.L_f64_bits (0, 0));
           })
      = 3 );
    ("the ref case is well formed", wf_ok M29_cases.ref_case);
    ("the js case is well formed", wf_ok M29_cases.js_case);
    ("the ref case mode is consistent", Sample.mode_ok M29_cases.ref_case);
    ("the js case mode is consistent", Sample.mode_ok M29_cases.js_case);
    ("both cases are listed", Prelude.len M29_cases.cases = 2);
  ]

let () =
  let bad = List.filter (fun c -> not (snd c)) checks in
  List.iter (fun c -> prerr_string ("FAIL " ^ fst c ^ "\n")) bad;
  print_string
    ("test_minimize: "
    ^ string_of_int (List.length checks - List.length bad)
    ^ "/"
    ^ string_of_int (List.length checks)
    ^ " ok\n");
  exit (if List.length bad = 0 then 0 else 1)
