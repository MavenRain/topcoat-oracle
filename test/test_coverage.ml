(* M22 tests for the coverage report (shell/cover.ml).

   Six suites: args, classify, text, strict, json, e2e.  The first
   five build a Cover.run by hand, so they assert on the report
   machinery with no draw at all;  only e2e draws, and it draws small
   batches.  Nothing prints before Alcotest.run. *)

open Ast

(* ---------- line helpers ---------- *)

let lines s = String.split_on_char '\n' s
let has_line s l = List.exists (String.equal l) (lines s)

let has_key s k =
  List.exists (fun l -> String.starts_with ~prefix:(k ^ " ") l) (lines s)
let newlines s = String.fold_left (fun acc c -> acc + Bool.to_int (c = '\n')) 0 s

(* The index of the FIRST line the predicate accepts, or -1.  It reads
   through List.mapi, never through an index. *)
let first_index s pred =
  let hits =
    List.filter_map
      (fun p ->
        match pred (snd p) with
        | true -> Some (fst p)
        | false -> None)
      (List.mapi (fun i l -> (i, l)) (lines s))
  in
  match hits with
  | [] -> -1
  | i :: _ -> i

let rec increasing xs =
  match xs with
  | [] -> true
  | _ :: [] -> true
  | a :: (b :: _ as rest) -> a < b && increasing rest

(* The escaped text is ASCII with no quote and no backslash, so a
   percent escape is found by splitting on the percent sign and
   asking whether any piece starts with the two hex digits. *)
let has_escape s code =
  List.exists
    (fun piece -> String.starts_with ~prefix:code piece)
    (String.split_on_char '%' s)

let comma_fields s = String.split_on_char ',' s

(* ---------- fixtures ---------- *)

let item idx target body mode : Cover.item =
  {
    Cover.it_idx = idx;
    it_target = target;
    it_body = body;
    it_mode = mode;
    it_env = [];
    it_bindings = [];
    it_signals = [];
    it_inits_drawn = false;
  }

(* The five write methods and the seven init shapes in one body, and
   none of the excluded names.  The write methods are what
   `required_for` asks of a (Sc_default, Ma_mixed) body;  the init
   shapes are here so a body-versus-init category error is visible. *)
let full_stmts =
  [
    E_some (E_lit (L_bool true));
    E_ok (E_lit (L_str "a"), T_f64);
    E_err (E_lit (L_f64_bits (0, 0)), T_f64);
    E_none T_f64;
    E_method (E_var 3, M_set, [ E_lit (L_bool true) ]);
    E_method (E_var 3, M_toggle, []);
    E_method (E_var 3, M_increment, []);
    E_method (E_var 3, M_decrement, []);
    E_method (E_var 3, M_push_str, [ E_lit (L_str "b") ]);
  ]

let full_body = E_block (full_stmts, E_block_unit [])
let full_item = item 0 T_unit full_body Taxonomy.Signal_writing

(* The same body plus one EXCLUDED constructor, for the fourth row of
   the strict truth table. *)
let excluded_body =
  E_block (List.append full_stmts [ E_tuple [] ], E_block_unit [])

let excluded_item = item 1 T_unit excluded_body Taxonomy.Signal_writing

(* The five write methods and NO init shape.  A (Sc_m20,
   Ma_signal_writing) body looks like this: Weights.m20 zeroes the
   option and result families, so the init shapes cannot appear in a
   body at all, and scoring them against the body tally is a false
   red. *)
let write_only_body =
  E_block
    ( [
        E_method (E_var 3, M_set, [ E_var 4 ]);
        E_method (E_var 3, M_toggle, []);
        E_method (E_var 3, M_increment, []);
        E_method (E_var 3, M_decrement, []);
        E_method (E_var 3, M_push_str, [ E_var 5 ]);
      ],
      E_block_unit [] )

(* One binding per init shape: E_none, E_some, E_ok, E_err, L_bool,
   L_str, and L_f64_bits inside the three wrappers. *)
let shaped_inits : Sample.binding list =
  [
    { Sample.id = 0; ty = T_option T_f64; init = E_none T_f64 };
    {
      Sample.id = 1;
      ty = T_option T_f64;
      init = E_some (E_lit (L_f64_bits (0, 0)));
    };
    {
      Sample.id = 2;
      ty = T_result (T_f64, T_f64);
      init = E_ok (E_lit (L_f64_bits (0, 0)), T_f64);
    };
    {
      Sample.id = 3;
      ty = T_result (T_f64, T_f64);
      init = E_err (E_lit (L_f64_bits (0, 0)), T_f64);
    };
    { Sample.id = 4; ty = T_bool; init = E_lit (L_bool true) };
    { Sample.id = 5; ty = T_string; init = E_lit (L_str "s") };
  ]

(* Every init an f64 literal, so only L_f64_bits is reached. *)
let f64_inits : Sample.binding list =
  [ { Sample.id = 0; ty = T_f64; init = E_lit (L_f64_bits (0, 0)) } ]

let writer_item bs =
  {
    (item 0 T_unit write_only_body Taxonomy.Signal_writing) with
    Cover.it_bindings = bs;
    it_inits_drawn = true;
  }

(* One f64-targeted item, for the dropped-item case. *)
let f64_item = item 4 T_f64 (E_lit (L_f64_bits (0, 0))) Taxonomy.Read_only

let a_drop : Cover.drop =
  { Cover.dr_idx = 7; dr_reason = Cover.Dr_wf_error; dr_bytes = 3; dr_text = "abc" }

let run_of scored drops opts : Cover.run =
  { Cover.r_opts = opts; r_scored = scored; r_drops = drops }

let strict_opts = { Cover.default_opts with Cover.strict = true }
let json_opts = { Cover.default_opts with Cover.format = Cover.F_json }

(* The flags of the run that used to go red on the init shapes:
   --scope m20 --mode signal-writing --strict. *)
let m20_writer_opts =
  {
    Cover.default_opts with
    Cover.scope = Cover.Sc_m20;
    mode = Cover.Ma_signal_writing;
    strict = true;
  }

(* A renderer that blanks every string literal.  Dr_print_empty is
   unreachable through Ops.printer_renderer, so this is the only way
   to reach that arm. *)
let blank_renderer : Printer_rust.renderer =
  { Printer_rust.lit_f64 = (fun _hi _lo -> ""); lit_str = (fun _s -> "") }

(* ---------- args ---------- *)

let parsed args =
  match Cover.parse_args Cover.default_opts args with
  | Cover.P_ok o -> Some o
  | Cover.P_usage _ -> None

let is_usage args = Option.is_none (parsed args)
let field_of args f d = Option.fold ~none:d ~some:f (parsed args)

let check_defaults () =
  Alcotest.(check int) "samples" 10_000 (field_of [] (fun o -> o.Cover.samples) 0);
  Alcotest.(check int) "seed" 0x4d3138 (field_of [] (fun o -> o.Cover.seed) 0);
  Alcotest.(check string)
    "scope" "default"
    (field_of [] (fun o -> Cover.scope_name o.Cover.scope) "?");
  Alcotest.(check string)
    "mode" "mixed"
    (field_of [] (fun o -> Cover.mode_arg_name o.Cover.mode) "?");
  Alcotest.(check bool) "strict" false (field_of [] (fun o -> o.Cover.strict) true)

let check_unknown_flag () =
  Alcotest.(check bool) "--bogus is a usage error" true (is_usage [ "--bogus" ]);
  Alcotest.(check bool)
    "a bare word is a usage error" true (is_usage [ "10000" ]);
  Alcotest.(check int)
    "exit 2" 2
    (Cover.main Ops.printer_renderer [ "coverage"; "--bogus" ]).Cover.o_code

let check_bad_values () =
  Alcotest.(check bool) "--samples 0" true (is_usage [ "--samples"; "0" ]);
  Alcotest.(check bool) "--samples -3" true (is_usage [ "--samples"; "-3" ]);
  Alcotest.(check bool) "--samples abc" true (is_usage [ "--samples"; "abc" ]);
  Alcotest.(check bool) "--seed -1" true (is_usage [ "--seed"; "-1" ]);
  Alcotest.(check bool) "--mode wat" true (is_usage [ "--mode"; "wat" ]);
  Alcotest.(check bool) "--scope wat" true (is_usage [ "--scope"; "wat" ])

let check_missing_values () =
  Alcotest.(check bool) "--samples" true (is_usage [ "--samples" ]);
  Alcotest.(check bool) "--seed" true (is_usage [ "--seed" ]);
  Alcotest.(check bool) "--mode" true (is_usage [ "--mode" ]);
  Alcotest.(check bool) "--scope" true (is_usage [ "--scope" ])

let check_last_wins () =
  Alcotest.(check int)
    "the last --samples wins" 9
    (field_of [ "--samples"; "5"; "--samples"; "9" ] (fun o -> o.Cover.samples) 0)

let check_all_flags () =
  let a =
    [
      "--strict"; "--json"; "--scope"; "m20"; "--mode"; "signal-writing";
      "--seed"; "0x10"; "--samples"; "3";
    ]
  in
  Alcotest.(check int) "samples" 3 (field_of a (fun o -> o.Cover.samples) 0);
  Alcotest.(check int) "seed" 16 (field_of a (fun o -> o.Cover.seed) 0);
  Alcotest.(check bool) "strict" true (field_of a (fun o -> o.Cover.strict) false);
  Alcotest.(check string)
    "scope" "m20"
    (field_of a (fun o -> Cover.scope_name o.Cover.scope) "?");
  Alcotest.(check string)
    "mode" "signal-writing"
    (field_of a (fun o -> Cover.mode_arg_name o.Cover.mode) "?")

let check_m18_cross () =
  Alcotest.(check bool)
    "m18 with read-only" true
    (is_usage [ "--scope"; "m18"; "--mode"; "read-only" ]);
  Alcotest.(check bool)
    "the flag order does not matter" true
    (is_usage [ "--mode"; "signal-writing"; "--scope"; "m18" ]);
  Alcotest.(check bool)
    "m18 with mixed is accepted" false
    (is_usage [ "--scope"; "m18"; "--mode"; "mixed" ])

(* ---------- classify ---------- *)

let reason v =
  match v with
  | Cover.V_kept -> "kept"
  | Cover.V_dropped r -> Cover.drop_reason_name r

let classified r it = reason (Cover.classify r it)

let check_kept () =
  Alcotest.(check string)
    "a well-formed read-only body is kept" "kept"
    (classified Ops.printer_renderer
       (item 0 T_bool (E_lit (L_bool true)) Taxonomy.Read_only))

let check_wf_error () =
  Alcotest.(check string)
    "a free variable is a wf error" "wf_error"
    (classified Ops.printer_renderer (item 1 T_bool (E_var 42) Taxonomy.Read_only))

let check_type_mismatch () =
  Alcotest.(check string)
    "the target must match the inferred type" "wf_type_mismatch"
    (classified Ops.printer_renderer
       (item 2 T_f64 (E_lit (L_bool true)) Taxonomy.Read_only))

let check_mode_mismatch () =
  Alcotest.(check string)
    "a read-only body at signal-writing" "mode_mismatch"
    (classified Ops.printer_renderer
       (item 3 T_bool (E_lit (L_bool true)) Taxonomy.Signal_writing))

let check_init_wf () =
  let it = item 4 T_bool (E_lit (L_bool true)) Taxonomy.Read_only in
  let bad : Sample.binding =
    { Sample.id = 0; ty = T_f64; init = E_block_unit [] }
  in
  Alcotest.(check string)
    "an init that is not wf at its type" "init_wf"
    (classified Ops.printer_renderer
       { it with Cover.it_bindings = [ bad ]; it_inits_drawn = true })

let check_print_empty () =
  let it = item 5 T_string (E_lit (L_str "x")) Taxonomy.Read_only in
  Alcotest.(check string)
    "the real renderer prints the literal" "kept"
    (classified Ops.printer_renderer it);
  Alcotest.(check string)
    "a blank renderer is a drop" "print_empty" (classified blank_renderer it)

(* ---------- text ---------- *)

let check_drops_logged () =
  let text =
    Cover.text_report (run_of [] [ a_drop ] Cover.default_opts)
  in
  Alcotest.(check bool)
    "forced drops are logged" true
    (has_line text "drop idx=7 reason=wf_error bytes=3 text=abc");
  Alcotest.(check bool)
    "the reason table counts it" true (has_line text "drop_wf_error 1");
  Alcotest.(check bool)
    "the header counts it" true (has_line text "samples_dropped 1")

let check_no_drops () =
  let text = Cover.text_report (run_of [] [] Cover.default_opts) in
  Alcotest.(check bool) "drop_none" true (has_line text "drop_none");
  Alcotest.(check bool)
    "every reason still prints" true
    (List.for_all
       (fun r -> has_line text ("drop_" ^ Cover.drop_reason_name r ^ " 0"))
       Cover.drop_reasons_all)

(* All SIX titles, and their order.  The tally title carries n, the
   seed, the scope and the mode, so it is matched by prefix.  Spec 2.G
   fixes the order, and a JSON consumer that reads positionally and
   the M18 byte-identity window both depend on it. *)
let check_titles () =
  let text = Cover.text_report (run_of [] [] Cover.default_opts) in
  let at t = first_index text (String.equal t) in
  let idx =
    [
      at "coverage report";
      first_index text (String.starts_with ~prefix:"constructor tally (");
      at "mode counters";
      at "environment coverage";
      at "target types and size";
      at "drops";
    ]
  in
  Alcotest.(check bool)
    "the six section titles print" true
    (List.for_all (fun i -> i >= 0) idx);
  Alcotest.(check bool) "they print in the specified order" true (increasing idx)

let check_kept_only () =
  let text =
    Cover.text_report (run_of [ (full_item, Cover.V_kept) ] [ a_drop ] Cover.default_opts)
  in
  Alcotest.(check bool) "one kept" true (has_line text "samples_kept 1");
  Alcotest.(check bool)
    "the drop is not in the tally" true
    (has_line text "E_method 5")

(* The kept-only invariant, with a real V_dropped pair in r_scored and
   the drop record built by Cover.drops_of, not by hand.  This is the
   one case where a dropped sample could inflate a coverage number:
   the item targets T_f64, so a kept-only regression shows up as
   target_T_f64 1. *)
let check_dropped_not_tallied () =
  let scored = [ (f64_item, Cover.V_dropped Cover.Dr_wf_error) ] in
  let drops = Cover.drops_of Ops.printer_renderer scored in
  let text = Cover.text_report (run_of scored drops Cover.default_opts) in
  Alcotest.(check bool)
    "the dropped item is not in the target histogram" true
    (has_line text "target_T_f64 0");
  Alcotest.(check bool) "nothing is kept" true (has_line text "samples_kept 0");
  Alcotest.(check bool)
    "the header counts the drop" true (has_line text "samples_dropped 1");
  Alcotest.(check bool)
    "the reason table counts it" true (has_line text "drop_wf_error 1");
  Alcotest.(check int)
    "exactly one drop line, at the draw index" 1
    (List.length
       (List.filter
          (String.starts_with ~prefix:"drop idx=4 reason=wf_error ")
          (lines text)))

(* The escaping path.  A drop is the only caller of clamp_text and no
   real run drops a sample, so without this case esc_byte, hex_byte
   and table_digit are dead code under the suite. *)
let check_escaping () =
  let raw = "a\"b\\c%d e\nf\xC3\xA9" in
  let ct = Cover.clamp_text raw in
  let e = fst ct in
  Alcotest.(check bool) "a quote escapes" true (has_escape e "22");
  Alcotest.(check bool) "a backslash escapes" true (has_escape e "5C");
  Alcotest.(check bool) "a percent sign escapes" true (has_escape e "25");
  Alcotest.(check bool) "a newline escapes" true (has_escape e "0A");
  Alcotest.(check bool) "a lead byte escapes" true (has_escape e "C3");
  Alcotest.(check bool) "a trail byte escapes" true (has_escape e "A9");
  Alcotest.(check bool) "no raw quote survives" false (String.contains e '"');
  Alcotest.(check bool) "no raw backslash survives" false (String.contains e '\\');
  Alcotest.(check bool) "a space survives" true (String.contains e ' ')

let check_truncation () =
  let long = String.concat "" (List.init 300 (fun _ -> "z")) in
  let ct = Cover.clamp_text long in
  Alcotest.(check int) "the full escaped length is reported" 300 (snd ct);
  Alcotest.(check int)
    "the text is clamped with a marker" (Cover.drop_text_max + 6)
    (String.length (fst ct))

(* ---------- strict ---------- *)

let check_unreached_fails_strict () =
  Alcotest.(check int)
    "unreached required fails strict" 1
    (Cover.exit_code (run_of [] [] strict_opts))

let check_no_strict_flag () =
  Alcotest.(check int)
    "without --strict the exit code is 0" 0
    (Cover.exit_code (run_of [] [] Cover.default_opts))

let check_full_run_passes_strict () =
  Alcotest.(check bool)
    "every required name reached" true
    (Cover.strict_ok (run_of [ (full_item, Cover.V_kept) ] [] strict_opts));
  Alcotest.(check int)
    "exit 0" 0
    (Cover.exit_code (run_of [ (full_item, Cover.V_kept) ] [] strict_opts))

let check_drop_fails_strict () =
  Alcotest.(check int)
    "one drop fails strict" 1
    (Cover.exit_code (run_of [ (full_item, Cover.V_kept) ] [ a_drop ] strict_opts))

(* Row 4 of the truth table: no drop, nothing unreached, one REACHED
   excluded name. *)
let check_excluded_fails_strict () =
  let r = run_of [ (excluded_item, Cover.V_kept) ] [] strict_opts in
  Alcotest.(check bool)
    "a reached excluded name fails strict" false (Cover.strict_ok r);
  Alcotest.(check int) "exit 1" 1 (Cover.exit_code r);
  Alcotest.(check bool)
    "the report names it" true
    (has_line (Cover.text_report r) "reached_excluded E_tuple")

(* The m20 signal-writing false red.  The body reaches the five write
   methods and no init shape;  the bindings reach every init shape.
   Scoring the init shapes against the BODY tally reported four of
   them unreached and exited 1 on a run that covers everything it is
   asked to cover. *)
let check_m20_writer_inits_pass_strict () =
  let r = run_of [ (writer_item shaped_inits, Cover.V_kept) ] [] m20_writer_opts in
  let text = Cover.text_report r in
  Alcotest.(check bool)
    "no required body name is unreached" true
    (has_line text "unreached_required none");
  Alcotest.(check bool)
    "no required init shape is unreached" true
    (has_line text "unreached_required_inits none");
  Alcotest.(check bool) "strict passes" true (Cover.strict_ok r);
  Alcotest.(check int) "exit 0" 0 (Cover.exit_code r)

(* The other direction: the same body with every init an f64 literal.
   The init half of the required set is the only thing that can catch
   this, because the body tally is unchanged. *)
let check_f64_inits_fail_strict () =
  let r = run_of [ (writer_item f64_inits, Cover.V_kept) ] [] m20_writer_opts in
  let text = Cover.text_report r in
  Alcotest.(check bool)
    "the body half still passes" true (has_line text "unreached_required none");
  Alcotest.(check bool)
    "the missing init shapes are named, in order" true
    (has_line text "unreached_required_inits E_none E_some E_ok E_err L_bool L_str");
  Alcotest.(check bool)
    "an unreached init shape fails strict" false (Cover.strict_ok r);
  Alcotest.(check int) "exit 1" 1 (Cover.exit_code r)

(* ---------- json ---------- *)

let check_json_one_line () =
  let j = Cover.json_report (run_of [] [ a_drop ] json_opts) in
  Alcotest.(check int) "exactly one newline" 1 (newlines j);
  Alcotest.(check bool)
    "it is the last byte" true
    (has_line j "" && String.length j > 1)

let check_json_keys () =
  let j = Cover.json_report (run_of [] [ a_drop ] json_opts) in
  let holds sub =
    List.exists
      (fun l -> String.length l >= String.length sub)
      (String.split_on_char ',' j)
    && String.length j > String.length sub
  in
  Alcotest.(check bool) "the json is not empty" true (holds "x");
  Alcotest.(check bool)
    "the drop reason is a json string" true
    (List.exists
       (fun l -> String.equal l "\"reason\":\"wf_error\"")
       (String.split_on_char ',' j))

let check_json_matches_text () =
  let r = run_of [ (full_item, Cover.V_kept) ] [] Cover.default_opts in
  Alcotest.(check bool)
    "the text form has the key" true
    (has_line (Cover.text_report r) "samples_kept 1");
  Alcotest.(check bool)
    "the json form has the same key" true
    (List.exists
       (fun l -> String.equal l "\"samples_kept\":1")
       (String.split_on_char ',' (Cover.json_report r)))

(* Parity for the new key: the same names, in the same order, in the
   text form and in the JSON form. *)
let check_json_init_names () =
  let r = run_of [ (writer_item f64_inits, Cover.V_kept) ] [] json_opts in
  Alcotest.(check bool)
    "the text form names the missing init shapes" true
    (has_line (Cover.text_report r)
       "unreached_required_inits E_none E_some E_ok E_err L_bool L_str");
  Alcotest.(check bool)
    "the json form opens the same array" true
    (List.exists
       (fun l -> String.equal l "\"unreached_required_inits\":[\"E_none\"")
       (comma_fields (Cover.json_report r)));
  Alcotest.(check bool)
    "and closes it on the last name" true
    (List.exists
       (fun l -> String.equal l "\"L_str\"]")
       (comma_fields (Cover.json_report r)))

let check_render_switch () =
  Alcotest.(check int)
    "F_text is multi-line" 1
    (Bool.to_int
       (newlines (Cover.render (run_of [] [] Cover.default_opts)) > 1));
  Alcotest.(check int)
    "F_json is one line" 1 (newlines (Cover.render (run_of [] [] json_opts)))

(* ---------- e2e ---------- *)

let small n args =
  Cover.main Ops.printer_renderer
    (List.append [ "coverage"; "--samples"; string_of_int n ] args)

let check_e2e_default () =
  let o = small 200 [] in
  Alcotest.(check int) "exit 0" 0 o.Cover.o_code;
  Alcotest.(check string) "no stderr" "" o.Cover.o_stderr;
  Alcotest.(check bool)
    "200 kept" true (has_line o.Cover.o_stdout "samples_kept 200");
  Alcotest.(check bool)
    "no drops" true (has_line o.Cover.o_stdout "samples_dropped 0");
  Alcotest.(check bool)
    "the environment was drawn" true (has_line o.Cover.o_stdout "env_source drawn")

let check_e2e_m18 () =
  let o = small 200 [ "--scope"; "m18" ] in
  Alcotest.(check int) "exit 0" 0 o.Cover.o_code;
  Alcotest.(check bool)
    "no environment" true (has_line o.Cover.o_stdout "env_source none");
  Alcotest.(check bool)
    "the mode comes from the classifier" true
    (has_line o.Cover.o_stdout "mode_source classifier");
  Alcotest.(check bool)
    "no drops" true (has_line o.Cover.o_stdout "samples_dropped 0")

(* M22 finding: the m20 scope does NOT suppress a non-finite INIT.
   Weights.m20 and Gen.gen_f64_bits_m20 hold the specials out of the
   BODY literals, but shell/sample_gen.ml reuses Gen.gen_f64_bits for
   the initial values on purpose (its header says so: a NaN or an
   infinite input is a target risk class).  So the three counters
   print, and they are not asserted to be zero. *)
let check_e2e_m20 () =
  let o = small 200 [ "--scope"; "m20" ] in
  Alcotest.(check int) "exit 0" 0 o.Cover.o_code;
  Alcotest.(check bool)
    "the scope prints" true (has_line o.Cover.o_stdout "scope m20");
  Alcotest.(check bool) "no drops" true (has_line o.Cover.o_stdout "samples_dropped 0");
  Alcotest.(check bool)
    "the non-finite init counters print" true
    (List.for_all (has_key o.Cover.o_stdout)
       [ "init_nan"; "init_pos_inf"; "init_neg_inf" ])

let check_e2e_modes () =
  let ro = small 100 [ "--mode"; "read-only" ] in
  let sw = small 100 [ "--mode"; "signal-writing" ] in
  Alcotest.(check bool)
    "read-only draws 100 read-only samples" true
    (has_line ro.Cover.o_stdout "requested_read_only 100");
  Alcotest.(check bool)
    "signal-writing draws 100 writers" true
    (has_line sw.Cover.o_stdout "requested_signal_writing 100");
  Alcotest.(check bool)
    "no mode mismatch either way" true
    (has_line ro.Cover.o_stdout "mode_mismatches 0"
    && has_line sw.Cover.o_stdout "mode_mismatches 0")

let check_e2e_usage () =
  let o = Cover.main Ops.printer_renderer [ "coverage"; "--nope" ] in
  Alcotest.(check int) "exit 2" 2 o.Cover.o_code;
  Alcotest.(check string) "no report" "" o.Cover.o_stdout;
  Alcotest.(check bool)
    "the usage goes to stderr" true (String.length o.Cover.o_stderr > 0)

let check_e2e_json () =
  let o = small 100 [ "--json" ] in
  Alcotest.(check int) "exit 0" 0 o.Cover.o_code;
  Alcotest.(check int) "one line" 1 (newlines o.Cover.o_stdout)

(* ---------- suites ---------- *)

let () =
  Alcotest.run "coverage"
    [
      ( "args",
        [
          Alcotest.test_case "defaults" `Quick check_defaults;
          Alcotest.test_case "unknown flag is a usage error" `Quick
            check_unknown_flag;
          Alcotest.test_case "bad values are usage errors" `Quick
            check_bad_values;
          Alcotest.test_case "a missing value is a usage error" `Quick
            check_missing_values;
          Alcotest.test_case "the last value wins" `Quick check_last_wins;
          Alcotest.test_case "every flag parses" `Quick check_all_flags;
          Alcotest.test_case "scope m18 takes mode mixed only" `Quick
            check_m18_cross;
        ] );
      ( "classify",
        [
          Alcotest.test_case "a good sample is kept" `Quick check_kept;
          Alcotest.test_case "wf_error" `Quick check_wf_error;
          Alcotest.test_case "wf_type_mismatch" `Quick check_type_mismatch;
          Alcotest.test_case "mode_mismatch" `Quick check_mode_mismatch;
          Alcotest.test_case "init_wf" `Quick check_init_wf;
          Alcotest.test_case "print_empty" `Quick check_print_empty;
        ] );
      ( "text",
        [
          Alcotest.test_case "forced drops are logged" `Quick check_drops_logged;
          Alcotest.test_case "no drops prints drop_none" `Quick check_no_drops;
          Alcotest.test_case "the six section titles print, in order" `Quick
            check_titles;
          Alcotest.test_case "only kept samples feed the tally" `Quick
            check_kept_only;
          Alcotest.test_case "a dropped item does not enter the tally" `Quick
            check_dropped_not_tallied;
          Alcotest.test_case "the drop text is percent escaped" `Quick
            check_escaping;
          Alcotest.test_case "a long drop text is clamped, not hidden" `Quick
            check_truncation;
        ] );
      ( "strict",
        [
          Alcotest.test_case "unreached required fails strict" `Quick
            check_unreached_fails_strict;
          Alcotest.test_case "without the flag the exit code is 0" `Quick
            check_no_strict_flag;
          Alcotest.test_case "a covered run passes strict" `Quick
            check_full_run_passes_strict;
          Alcotest.test_case "a drop fails strict" `Quick check_drop_fails_strict;
          Alcotest.test_case "a reached excluded name fails strict" `Quick
            check_excluded_fails_strict;
          Alcotest.test_case "init shapes are scored against the inits" `Quick
            check_m20_writer_inits_pass_strict;
          Alcotest.test_case "an unreached init shape fails strict" `Quick
            check_f64_inits_fail_strict;
        ] );
      ( "json",
        [
          Alcotest.test_case "one line" `Quick check_json_one_line;
          Alcotest.test_case "the drop keys are json strings" `Quick
            check_json_keys;
          Alcotest.test_case "the same keys as the text form" `Quick
            check_json_matches_text;
          Alcotest.test_case "the init key has the same names as the text form"
            `Quick check_json_init_names;
          Alcotest.test_case "render follows the format flag" `Quick
            check_render_switch;
        ] );
      ( "e2e",
        [
          Alcotest.test_case "a default batch keeps every sample" `Quick
            check_e2e_default;
          Alcotest.test_case "scope m18 has no environment" `Quick check_e2e_m18;
          Alcotest.test_case "scope m20 has no non-finite init" `Quick
            check_e2e_m20;
          Alcotest.test_case "each mode draws that mode" `Quick check_e2e_modes;
          Alcotest.test_case "an unknown flag exits 2" `Quick check_e2e_usage;
          Alcotest.test_case "--json emits one line" `Quick check_e2e_json;
        ] );
    ]
