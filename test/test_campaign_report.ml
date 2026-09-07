(* M34 shell integration uses deterministic draws and correspondence-valid
   synthetic observations. No Rust crate or JavaScript worker is executed. *)

open Ast

let base () : Sample.t =
  { Sample.mode = Taxonomy.Read_only;
    Sample.inputs =
      [ { Sample.id = 0; Sample.ty = T_bool; Sample.init = E_lit (L_bool true) } ];
    Sample.signals = [];
    Sample.target = T_bool;
    Sample.body = E_var 0 }

let test_signature () =
  let s = base () in
  let renamed =
    { s with
      Sample.inputs =
        [ { Sample.id = 19; Sample.ty = T_bool;
            Sample.init = E_lit (L_bool false) } ];
      Sample.body = E_var 19 }
  in
  let expected =
    "v1;target{T_bool=1};body{E_var=1};input_type{T_bool=1};"
    ^ "input_init{E_lit=1,L_bool=1};signal_type{};signal_init{}"
  in
  Alcotest.(check string) "explicit canonical map" expected
    (Campaign_report.signature_of s);
  Alcotest.(check string) "literal values and identifiers normalize" expected
    (Campaign_report.signature_of renamed);
  Alcotest.(check string) "mode belongs to outer grouping key" expected
    (Campaign_report.signature_of
       { s with Sample.mode = Taxonomy.Signal_writing });
  Prelude.fold
    (fun () change ->
      Alcotest.(check bool) (fst change) false
        (String.equal expected (Campaign_report.signature_of (snd change))))
    ()
    [ ("target type", { s with Sample.target = T_unit });
      ("body constructor", { s with Sample.body = E_unary (U_not, E_var 0) });
      ("input type",
       { s with Sample.inputs =
           [ { Sample.id = 0; Sample.ty = T_string;
               Sample.init = E_lit (L_bool true) } ] });
      ("input initializer",
       { s with Sample.inputs =
           [ { Sample.id = 0; Sample.ty = T_bool;
               Sample.init = E_none T_bool } ] });
      ("input versus signal roles",
       { s with Sample.inputs = []; Sample.signals = s.Sample.inputs });
      ("binding count",
       { s with Sample.inputs = Prelude.append s.Sample.inputs s.Sample.inputs }) ];
  let nested =
    { s with Sample.body = E_binary (B_eq, E_var 0, E_var 0) }
  in
  Alcotest.(check bool) "constructor multiplicity survives" true
    (Prelude.occurs (Campaign_report.signature_of nested)
       "body{B_eq=1,E_binary=1,E_var=2}")

let row_of (i : int) (verdict : string) (s : Sample.t) : Journal.line =
  let cell = if String.equal verdict "dropped" then "" else "Vu|r0:|" in
  Pipeline.row ~i ~verdict ~r:cell ~j:cell ~f:cell s

let error_of result =
  Result.fold ~ok:(fun _ -> "accepted") ~error:Campaign_report.error_text result

let rejected (name : string) (wanted : string) result =
  Alcotest.(check string) name wanted (error_of result)

let rejected_contains (name : string) (wanted : string) result =
  let actual = error_of result in
  Alcotest.(check bool) (name ^ ": " ^ actual) true
    (Prelude.occurs actual wanted)

let test_row_identity () =
  let s = base () in
  let row = row_of 0 "agree" s in
  Alcotest.(check string) "complete original program" "accepted"
    (error_of (Campaign_report.check_sample 0 row s));
  Prelude.fold
    (fun () mutation ->
      let field = fst mutation in
      rejected field
        ("generator drift at sample 0: " ^ field
         ^ " does not match the seeded draw")
        (Campaign_report.check_sample 0 (snd mutation) s))
    ()
    [ ("index", { row with Journal.jl_i = 1 });
      ("mode", { row with Journal.jl_mode = "signal_writing" });
      ("size", { row with Journal.jl_size = row.Journal.jl_size + 1 });
      ("environment", { row with Journal.jl_env = [ "let v0: bool = false;" ] });
      ("body", { row with Journal.jl_body = "!v0" }) ];
  rejected "missing generated sample"
    "generator drift: expected 1 samples, drew 0"
    (Campaign_report.samples_of [ row ] []);
  rejected "surplus generated sample"
    "generator drift: expected 1 samples, drew 2"
    (Campaign_report.samples_of [ row ] [ s; s ])

let header (seed : int) : Journal.header =
  { Journal.jh_seed = seed; Journal.jh_batch = 10; Journal.jh_plant = "none";
    Journal.jh_topcoat = "0123456789abcdef0123456789abcdef01234567" }

let rows_of (verdict : string) (samples : Sample.t list) : Journal.line list =
  Prelude.rev
    (snd
       (Prelude.fold
          (fun acc s -> (fst acc + 1, row_of (fst acc) verdict s :: snd acc))
          (0, []) samples))

let trace_of (row : Journal.line) : Correspond.trace_line =
  let dropped = String.equal row.Journal.jl_verdict "dropped" in
  let kind = if dropped then Correspond.Kd_dropped else Correspond.Kd_paired in
  let present =
    if dropped then Correspond.Cell_absent else Correspond.Cell_present
  in
  { Correspond.tl_i = row.Journal.jl_i;
    Correspond.tl_steps =
      Prelude.map Correspond.step_name
        (Correspond.steps_of
           { Correspond.ev_kind = kind; Correspond.ev_rust = present;
             Correspond.ev_js = present; Correspond.ev_ref = present;
             Correspond.ev_head = Journal.head row.Journal.jl_verdict }) }

let checked ?(minimum = 1) (h : Journal.header) (rows : Journal.line list) =
  Campaign_report.check ~minimum h rows (Pipeline.trace_header_of h)
    (Prelude.map trace_of rows)

let test_seed_replay () =
  let samples = Pipeline.draw 64 42 in
  let rows = rows_of "agree" samples in
  Result.fold
    ~error:(fun e -> Alcotest.(check string) "valid baseline" "accepted"
        (Campaign_report.error_text e))
    ~ok:(fun v ->
      Alcotest.(check int) "all attempts survive" 64
        v.Campaign_report.v_report.Campaign.r_total;
      Alcotest.(check int) "M35 receives every source pair" 64
        (Prelude.len v.Campaign_report.v_members);
      Alcotest.(check bool) "read-only samples occur" true
        (v.Campaign_report.v_report.Campaign.r_read_only > 0);
      Alcotest.(check bool) "signal-writing samples occur" true
        (v.Campaign_report.v_report.Campaign.r_signal_writing > 0))
    (checked (header 42) rows);
  rejected_contains "another seed does not name these programs" "generator drift"
    (Campaign_report.samples_of rows (Pipeline.draw 64 43));
  rejected_contains "consistent forged headers still fail seed replay"
    "generator drift" (checked (header 43) rows);
  let changed =
    Prelude.map
      (fun row ->
        if Int.equal row.Journal.jl_i 63 then
          { row with Journal.jl_body = row.Journal.jl_body ^ " " }
        else row)
      rows
  in
  rejected "last row also requires exact program bytes"
    "generator drift at sample 63: body does not match the seeded draw"
    (checked (header 42) changed)

let test_campaign_boundaries () =
  let h = header 42 in
  let samples = Pipeline.draw 64 42 in
  let rows = rows_of "agree" samples in
  rejected "positive minimum" "minimum 0 must be at least 1"
    (checked ~minimum:0 h rows);
  rejected "real size below threshold"
    "campaign has 64 samples; minimum is 65"
    (checked ~minimum:65 h rows);
  rejected "default is 5000" "campaign has 64 samples; minimum is 5000"
    (Campaign_report.check h rows (Pipeline.trace_header_of h)
       (Prelude.map trace_of rows));
  rejected "planted results cannot become a baseline"
    "campaign baseline requires plant none, found ref:display_sign"
    (checked { h with Journal.jh_plant = "ref:display_sign" } rows);
  rejected_contains "one mode is not a mixed campaign" "campaign requires both modes"
    (checked h (rows_of "agree" (Pipeline.draw 1 42)));
  rejected "all losses do not count as success"
    "campaign contains only losses: no agree, known, or diverge result"
    (checked h (rows_of "dropped" samples));
  rejected_contains "unsupported suffix is not agreement"
    "invalid verdict \"agree:extra\""
    (checked h (rows_of "agree:extra" samples));
  rejected_contains "correspondence is checked before grouping" "correspondence"
    (Campaign_report.check ~minimum:1 h rows (Pipeline.trace_header_of h) []);
  let divergences =
    Prelude.map
      (fun row ->
        { row with Journal.jl_verdict =
            if String.equal row.Journal.jl_mode "read_only" then
              "diverge:value:odd:ref"
            else "diverge:value:two_way" })
      rows
  in
  Prelude.fold
    (fun () fixture ->
      Alcotest.(check string) (fst fixture ^ " is an adjudication") "accepted"
        (error_of (checked h (snd fixture))))
    () [ ("known", rows_of "known:I1" samples); ("diverge", divergences) ];
  let wrong_splits =
    Prelude.map
      (fun row ->
        { row with Journal.jl_verdict =
            if String.equal row.Journal.jl_mode "read_only" then
              "diverge:value:two_way"
            else "diverge:value:odd:ref" })
      rows
  in
  rejected_contains "split must match the mode's number of legs"
    "invalid verdict" (checked h wrong_splits)

let test_coverage () =
  let s = base () in
  let same_signature =
    { s with Sample.inputs =
        [ { Sample.id = 99; Sample.ty = T_bool;
            Sample.init = E_lit (L_bool false) } ]; Sample.body = E_var 99 }
  in
  let actual = Campaign_report.coverage_text [ s; same_signature ] in
  Prelude.fold
    (fun () wanted ->
      Alcotest.(check bool) wanted true (Prelude.occurs actual wanted))
    () [ "All 2 attempts contribute, including losses.";
         "m34 signatures 1 samples 2\n";
         "body.E_var 2\n"; "input_type.T_bool 2\n";
         "input_init.L_bool 2\n"; "target.T_bool 2\n" ];
  Alcotest.(check string) "coverage rendering is deterministic" actual
    (Campaign_report.coverage_text [ same_signature; s ])

let () =
  Alcotest.run "m34-campaign-report"
    [ ("constructs",
       [ Alcotest.test_case "canonical signature roles" `Quick test_signature;
         Alcotest.test_case "coverage includes every attempt" `Quick test_coverage ]);
      ("identity",
       [ Alcotest.test_case "all journal program fields" `Quick test_row_identity;
         Alcotest.test_case "seed replay checks every row" `Quick test_seed_replay ]);
      ("baseline",
       [ Alcotest.test_case "minimum, modes, losses, plant, trace and grammar"
           `Quick test_campaign_boundaries ]) ]
