(* M26 reference-leg tests (DESIGN.md M26, spec section 9.2).  PURE
   ONLY: no process, no file and no directory.  Every case runs against
   string constants and against Driver.seed_cases, which is a value.

   The expected cells are the F column of the HAND-DERIVED table of spec
   section 8.5, not the output of this leg.  Case 1 renders a<b>+c, six
   bytes, because the reference models Rust Display with no html
   escaping;  the rust leg prints the escaped twelve bytes.  That is
   divergence D2 and it is an OUTPUT of this milestone.  Case 10 names
   the panic class expect_err where both legs say other;  that is interp
   finding I1 and nothing here smooths it. *)

(* ---------- group 1: the twelve F cells ---------- *)

let f_cells =
  [
    {j|Vf1073217536:0;|r3:1.5||j};
    {j|Vs6:a<b>+c|r6:a<b>+c||j};
    {j|Vs0:|r0:||j};
    {j|VSf1073217536:0;|r3:1.5||j};
    {j|Vn|r0:||j};
    {j|Punwrap:43:called `Option::unwrap()` on a `None` value|r0:||j};
    {j|Vf1074003968:0;|r3:2.5|g3:f1074003968:0;|j};
    {j|Vu|r0:|g4:b0|j};
    {j|Pexpect_err:10:nope: "ok"|r0:||j};
    {j|Pexpect:4:boom|r0:||j};
    {j|Pexpect_err:10:nope: "ok"|r0:||j};
    {j|T|r0:||j};
  ]

let rec check_cells (i : int) (cells : string list) (cases : Sample.t list) :
    unit =
  match cells with
  | [] -> ()
  | c :: crest -> (
      match cases with
      | [] ->
          Alcotest.(check string) "the seed corpus is short" c "<missing case>"
      | s :: srest ->
          Alcotest.(check string)
            ("case " ^ string_of_int i)
            c
            (Obs.encode (Ref_leg.observe Ref_leg.default_config s));
          check_cells (i + 1) crest srest)

let check_seed_cells () = check_cells 0 f_cells Driver.seed_cases

(* ---------- group 2: the render rules ---------- *)

(* One value of each Obs.value variant.  The a<b>+c row is the one that
   pins the "no html escaping" rule of spec 4.3. *)
let render_rows =
  [
    (Obs.V_f64_bits (1073217536, 0), "1.5");
    (Obs.V_str "a<b>+c", "a<b>+c");
    (Obs.V_str "", "");
    (Obs.V_bool true, "true");
    (Obs.V_bool false, "false");
    (Obs.V_unit, "");
    (Obs.V_some (Obs.V_f64_bits (1073217536, 0)), "1.5");
    (Obs.V_none, "");
    (Obs.V_tuple [ Obs.V_unit ], "");
    (Obs.V_ok Obs.V_unit, "");
    (Obs.V_err Obs.V_unit, "");
    (Obs.V_closure, "");
  ]

let check_render () =
  List.iteri
    (fun i row ->
      Alcotest.(check string)
        ("render row " ^ string_of_int i)
        (snd row)
        (Ref_leg.rendered_of_value (fst row)))
    render_rows

(* ---------- group 3: the outcome rules ---------- *)

let check_outcomes () =
  Alcotest.(check string)
    "a panic renders the empty string" ""
    (Ref_leg.rendered_of_outcome Ref_leg.default_config
       (Obs.O_panic (Obs.P_unwrap, "boom")));
  Alcotest.(check string)
    "a no-terminate renders the empty string" ""
    (Ref_leg.rendered_of_outcome Ref_leg.default_config Obs.O_no_terminate)

(* ---------- group 4: fuel ---------- *)

(* Seed case 0 binds one input, so eval returns C_fuel at :214, the
   binding pass gives None (:720-724) and run_sample takes its ~none arm
   (:765).  A sample with no bindings at all would give T|r0:| instead;
   the corpus supports the stuck:init spelling, so that is what is
   pinned here. *)
let check_fuel () =
  Alcotest.(check string)
    "fuel 0 on case 0" {j|Pother:10:stuck:init|r0:||j}
    (Option.fold ~none:"<missing case>"
       ~some:(fun s -> Obs.encode (Ref_leg.observe { Ref_leg.fuel = 0 } s))
       (Prelude.nth_opt Driver.seed_cases 0))

(* ---------- group 5: the hints ---------- *)

(* The fourth column of the twelve M24 rows, m24_verdict.sh:66-77. *)
let hint_wires =
  [
    "none"; "none"; "none"; "none"; "none"; "none"; "none"; "none"; "expect_err";
    "expect"; "both"; "none";
  ]

let rec check_hint_list (i : int) (wires : string list)
    (cases : Sample.t list) : unit =
  match wires with
  | [] -> ()
  | w :: wrest -> (
      match cases with
      | [] ->
          Alcotest.(check string) "the seed corpus is short" w "<missing case>"
      | s :: srest ->
          Alcotest.(check string)
            ("hint of case " ^ string_of_int i)
            w
            (Driver.hint_wire (Ref_leg.hint s));
          check_hint_list (i + 1) wrest srest)

let check_hints () = check_hint_list 0 hint_wires Driver.seed_cases

let () =
  Alcotest.run "ref_leg"
    [
      ( "m26",
        [
          Alcotest.test_case "the twelve F cells" `Quick check_seed_cells;
          Alcotest.test_case "the render rules" `Quick check_render;
          Alcotest.test_case "the outcome rules" `Quick check_outcomes;
          Alcotest.test_case "fuel zero" `Quick check_fuel;
          Alcotest.test_case "the hints" `Quick check_hints;
        ] );
    ]
