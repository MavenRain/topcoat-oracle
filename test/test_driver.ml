(* M23 driver-emitter tests (DESIGN.md M23, spec section 7).  All ten
   cases run over the PURE builders of shell/driver.ml: no cargo, no
   files, no process.  m23_gate.sh pins what rustc and the runtime do;
   these pin the text that goes into the crate, so a respacing or an
   off-by-one in dispatch turns dune runtest red before a single rustc
   invocation. *)

open Ast

(* ---------- total text helpers ---------- *)

let chars (s : string) : char list = List.of_seq (String.to_seq s)

let rec is_prefix (n : char list) (h : char list) : bool =
  match n with
  | [] -> true
  | c :: n_rest -> (
      match h with
      | [] -> false
      | d :: h_rest -> Char.equal c d && is_prefix n_rest h_rest)

let rec scan (n : char list) (h : char list) (acc : int) : int =
  match h with
  | [] -> acc
  | _ :: h_rest ->
      scan n h_rest (acc + match is_prefix n h with true -> 1 | false -> 0)

let count_occurrences (hay : string) (needle : string) : int =
  scan (chars needle) (chars hay) 0

(* ---------- 1.  rust_ty ---------- *)

let ty_cases_ok =
  [
    (T_f64, "f64");
    (T_bool, "bool");
    (T_string, "String");
    (T_unit, "()");
    (T_option T_f64, "Option<f64>");
    (T_option (T_option T_string), "Option<Option<String>>");
    (T_result (T_f64, T_string), "Result<f64, String>");
    (T_result (T_string, T_f64), "Result<String, f64>");
  ]

let ty_cases_none =
  [
    T_tuple [ T_f64; T_bool ];
    T_fn ([ T_f64 ], T_bool);
    T_async_fn ([], T_unit);
    T_future T_f64;
    T_signal T_f64;
    T_option (T_tuple []);
  ]

let check_rust_ty () =
  Alcotest.(check (list (option string)))
    "rust_ty spellings"
    (List.map (fun p -> Some (snd p)) ty_cases_ok)
    (List.map (fun p -> Driver.rust_ty (fst p)) ty_cases_ok);
  Alcotest.(check (list (option string)))
    "no Rust spelling outside the m20 shape"
    (List.map (fun _t -> None) ty_cases_none)
    (List.map Driver.rust_ty ty_cases_none)

(* ---------- 2.  String inits carry String::from ---------- *)

(* The M21 review fix.  Printer_rust renders a string literal as a bare
   Rust literal, which is a &str;  a String-typed mirror local needs
   String::from(..) at every literal leaf. *)
let check_string_init () =
  Alcotest.(check (option string))
    "String init"
    (Some ("String::from(" ^ Strops.debug "a\"b" ^ ")"))
    (Driver.init_rust T_string (E_lit (L_str "a\"b")));
  Alcotest.(check (option string))
    "Option<String> init" (Some "Some(String::from(\"x\"))")
    (Driver.init_rust (T_option T_string) (E_some (E_lit (L_str "x"))));
  Alcotest.(check (option string))
    "Result<String, f64> init" (Some "Ok(String::from(\"ok\"))")
    (Driver.init_rust
       (T_result (T_string, T_f64))
       (E_ok (E_lit (L_str "ok"), T_f64)))

(* ---------- 3.  f64 inits go through from_bits ---------- *)

let check_f64_init () =
  Alcotest.(check (list (option string)))
    "f64 bit patterns survive bit for bit"
    [
      Some "f64::from_bits(0x7ff8000000000001u64)";
      Some "f64::from_bits(0x8000000000000000u64)";
      Some "f64::from_bits(0x0000000000000001u64)";
      Some "f64::from_bits(0x3ff8000000000000u64)";
    ]
    (List.map
       (fun p -> Driver.init_rust T_f64 (E_lit (L_f64_bits (fst p, snd p))))
       [
         (0x7ff80000, 0x00000001);
         (0x80000000, 0x00000000);
         (0x00000000, 0x00000001);
         (0x3ff80000, 0x00000000);
       ])

(* ---------- 4.  an open init has no Rust text, and drops loudly ---------- *)

let open_sample =
  {
    Sample.mode = Taxonomy.Read_only;
    inputs = [ { Sample.id = 0; ty = T_f64; init = E_var 0 } ];
    signals = [];
    target = T_f64;
    body = E_var 0;
  }

let check_open_init () =
  Alcotest.(check (list (option string)))
    "open init shapes" [ None; None; None ]
    [
      Driver.init_rust T_f64 (E_var 0);
      Driver.init_rust T_f64 (E_binary (B_add, E_var 0, E_var 0));
      Driver.init_rust T_string (E_method (E_var 2, M_clone, []));
    ];
  Alcotest.(check (option string))
    "the sample leaves no case function" None
    (Driver.case_fn 0 open_sample);
  let b = Driver.build [ open_sample ] in
  Alcotest.(check int) "nothing kept" 0 b.Driver.kept;
  Alcotest.(check (list string))
    "the drop is named" [ "init_rust" ]
    (List.map Driver.drop_reason_name b.Driver.drops)

(* ---------- 5.  may_panic ---------- *)

let panicky_meths =
  [
    M_unwrap; M_expect; M_unwrap_err; M_expect_err; M_set; M_toggle;
    M_increment; M_decrement; M_push_str;
  ]

let check_may_panic () =
  Alcotest.(check (list bool))
    "unwrap, expect and the five writers"
    (List.map (fun _m -> true) panicky_meths)
    (List.map
       (fun m -> Driver.may_panic (E_method (E_var 8, m, [])))
       panicky_meths);
  Alcotest.(check bool) "f64 arithmetic never panics" false
    (Driver.may_panic
       (E_binary (B_add, E_method (E_var 0, M_clone, []), E_var 0)))

(* ---------- 6.  renderable ---------- *)

let check_renderable () =
  Alcotest.(check (list bool))
    "NodeViewParts membership"
    [ true; true; true; true; false; false; false ]
    (List.map Driver.renderable
       [
         T_f64; T_bool; T_string; T_option T_f64; T_unit;
         T_result (T_f64, T_string); T_option T_unit;
       ])

(* ---------- 7.  the emitted bytes of seed case 0 ---------- *)

let expected_case_0 =
  Prelude.concat
    (Prelude.map
       (fun l -> l ^ "\n")
       [
         "fn case_0000() -> harness::Observed {";
         "    let v0_init: f64 = f64::from_bits(0x3ff8000000000000u64);";
         "    let signals: Vec<harness::SigInit> = Vec::new();";
         "    let inner = harness::catch_value(harness::Hint::None, || {";
         "            let cx = Cx::default();";
         "            let v0: f64 = v0_init.clone();";
         "            let sig_debug: Vec<String> = Vec::new();";
         "            let (evaluated, js) = \
          expr!(v0).into_evaluated_and_js();";
         "            let js_bytes = js.render(&cx).into_bytes();";
         "            let observed = harness::observed_rendered(&cx, \
          evaluated);";
         "            harness::Triple { value: observed.0, rendered: \
          observed.1, js: js_bytes, sig_debug }";
         "    });";
         "    harness::assemble(inner, None, signals, harness::Hint::None)";
         "}";
       ])

let check_case_fn () =
  Alcotest.(check (option string))
    "seed case 0 text"
    (Some expected_case_0)
    (Option.fold ~none:None
       ~some:(fun s -> Driver.case_fn 0 s)
       (Prelude.nth_opt Driver.seed_cases 0))

(* ---------- 8.  the crate text and the spans ---------- *)

let spans_ok (spans : (int * int * int) list) (total : int) : bool =
  fst
    (List.fold_left
       (fun acc sp ->
         let next = fst (snd acc) in
         let prev = snd (snd acc) in
         let idx = match sp with i, _, _ -> i in
         let first = match sp with _, a, _ -> a in
         let last = match sp with _, _, z -> z in
         ( fst acc && idx = next && first > prev && last >= first
           && last <= total,
           (next + 1, last) ))
       (true, (0, 0))
       spans)

(* The dispatch table is positional: row i must call case_i.  A rotated
   table still emits n rows and still type checks, so only the ORDER
   catches it here;  the seed value channel catches it in the gate. *)
let case_rows (lines : string list) : string list =
  List.filter (fun l -> Strops.contains l "harness::Case { run: case_") lines

let rows_in_order (rows : string list) : bool =
  fst
    (List.fold_left
       (fun acc row ->
         ( fst acc
           && Strops.contains row
                ("harness::Case { run: "
                ^ Driver.case_name (snd acc)
                ^ ", "),
           snd acc + 1 ))
       (true, 0) rows)

let check_main_rs () =
  let n = Prelude.len Driver.seed_cases in
  let b = Driver.build Driver.seed_cases in
  let text = Driver.main_rs Driver.seed_cases in
  Alcotest.(check int) "one case function per sample" n
    (count_occurrences text "() -> harness::Observed {");
  Alcotest.(check int) "one dispatch row per sample" n
    (count_occurrences text "harness::Case { run: case_");
  Alcotest.(check bool) "the CASES array is sized at the kept count" true
    (Strops.contains text
       ("const CASES: [harness::Case; " ^ Prelude.nat_to_string n ^ "] = ["));
  Alcotest.(check int) "one span per kept case" n
    (Prelude.len b.Driver.spans);
  Alcotest.(check bool) "spans increase and stay inside the file" true
    (spans_ok (Prelude.rev b.Driver.spans) (Prelude.len b.Driver.lines));
  Alcotest.(check bool) "the dispatch rows are in emission order" true
    (rows_in_order (case_rows b.Driver.lines))

(* ---------- 9.  the seed vector itself ---------- *)

let is_while (e : expr) : bool =
  match e with
  | E_while (_, _) -> true
  | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
  | E_none _ | E_ok _ | E_err _ | E_call _ | E_method _ | E_field _
  | E_index _ | E_let _ | E_block _ | E_block_unit _ | E_if _ | E_if_else _
  | E_loop _ | E_break | E_continue | E_return_unit | E_return _
  | E_closure _ | E_async_closure _ | E_await _ ->
      false

let seed_hint (i : int) : string =
  Option.fold ~none:"missing"
    ~some:(fun (s : Sample.t) ->
      Driver.hint_wire (Driver.hint_of s.Sample.body))
    (Prelude.nth_opt Driver.seed_cases i)

let check_seed_shape () =
  Alcotest.(check int) "twelve seed cases" 12 (Prelude.len Driver.seed_cases);
  Alcotest.(check bool) "case 11 is the non-terminating while" true
    (Option.fold ~none:false
       ~some:(fun (s : Sample.t) -> is_while s.Sample.body)
       (Prelude.nth_opt Driver.seed_cases 11));
  Alcotest.(check (list string))
    "the hint channel fires on cases 8, 9 and 10"
    [
      "none"; "none"; "none"; "none"; "none"; "none"; "none"; "none";
      "expect_err"; "expect"; "both"; "none";
    ]
    (List.map seed_hint [ 0; 1; 2; 3; 4; 5; 6; 7; 8; 9; 10; 11 ])

(* ---------- 10.  a drawn batch, the gate's own stream ---------- *)

let drawn =
  QCheck.Gen.generate ~n:200
    ~rand:(Random.State.make [| 0x4d3233 |])
    (Sample_gen.gen_sample true Weights.m20)

let kept_names (b : Driver.built) : string list =
  Prelude.map
    (fun sp -> "case_" ^ Emit.pad4 (match sp with i, _, _ -> i))
    b.Driver.spans

let check_batch () =
  let b = Driver.build drawn in
  Alcotest.(check int) "kept plus dropped is the whole draw" 200
    (b.Driver.kept + Prelude.len b.Driver.drops);
  let text = Driver.main_rs drawn in
  Alcotest.(check int) "one dispatch row per kept case" b.Driver.kept
    (count_occurrences text "harness::Case { run: case_");
  Alcotest.(check (list string))
    "every kept case reaches CASES" []
    (List.filter
       (fun name ->
         not (Strops.contains text ("harness::Case { run: " ^ name ^ ",")))
       (kept_names b))

let () =
  Alcotest.run "driver"
    [
      ( "m23",
        [
          Alcotest.test_case "rust_ty spellings" `Quick check_rust_ty;
          Alcotest.test_case "String inits use String::from" `Quick
            check_string_init;
          Alcotest.test_case "f64 inits use from_bits" `Quick check_f64_init;
          Alcotest.test_case "open inits drop with a reason" `Quick
            check_open_init;
          Alcotest.test_case "may_panic" `Quick check_may_panic;
          Alcotest.test_case "renderable" `Quick check_renderable;
          Alcotest.test_case "seed case 0 bytes" `Quick check_case_fn;
          Alcotest.test_case "crate shape and spans" `Quick check_main_rs;
          Alcotest.test_case "seed vector shape" `Quick check_seed_shape;
          Alcotest.test_case "200-sample drawn batch" `Quick check_batch;
        ] );
    ]
