(* M28 plant suite (DESIGN.md M28, spec section 10.1).  The suite is
   PURE:  no process, no file and no directory.  Every expectation below
   is a literal, and nothing here is computed by the code under test.

   Four groups.  Group 1 pins the two spellings and every rejection of
   the parser.  Group 2 pins that exactly one field of Interp.ops moves,
   with one assertion per field, so a leak names the field that leaked.
   Group 3 runs the reference leg over the twelve seeds under the clean
   config and under the planted config.  Group 4 pins the node argument
   vector under each plant.

   These vectors are the unit half of the M28 design gate.  The three
   hand-derived tables of spec section 9 cannot see the twenty untouched
   op fields, the rejections of the parser or the shape of the argv, and
   only this suite can. *)

(* ---------- group 1: the name and the parser ---------- *)

let check_names () =
  Alcotest.(check string) "none" "none" (Plant.name Plant.No_plant);
  Alcotest.(check string) "the ref plant" "ref:display_sign"
    (Plant.name (Plant.Ref Plant.Rp_display_sign));
  Alcotest.(check string) "the js plant" "js:signal_get_plus_one"
    (Plant.name (Plant.Js Plant.Jp_signal_get_plus_one))

let show (p : Plant.t option) : string =
  Option.fold ~none:"<none>" ~some:Plant.name p

let check_round_trip () =
  Alcotest.(check string) "ref round trip" "ref:display_sign"
    (show (Plant.of_string "ref:display_sign"));
  Alcotest.(check string) "js round trip" "js:signal_get_plus_one"
    (show (Plant.of_string "js:signal_get_plus_one"))

(* "none" and "" are rejected because no spelling may select the
   unplanted run.  "js:display_sign" is rejected because the two tables
   are separate:  a ref plant name under the js: prefix is not a js
   plant.  "display_sign" with no prefix is rejected because the prefix
   carries the leg. *)
let check_rejections () =
  List.iter
    (fun s ->
      Alcotest.(check string) ("rejected: " ^ s) "<none>"
        (show (Plant.of_string s)))
    [ "none"; ""; "ref:"; "ref:nope"; "js:display_sign"; "display_sign" ]

(* ---------- group 2: one field and only one field ---------- *)

let planted = Plant.ref_ops Plant.Rp_display_sign
let base = Ops.interp_ops

(* Physical equality is the test for the twenty untouched fields,
   because a record update copies the closures.  The list carries one
   entry per field of Interp.ops (core/interp.ml:28-50) except
   f_display, which the plant replaces. *)
let same_fields =
  [
    ("f_add", planted.Interp.f_add == base.Interp.f_add);
    ("f_sub", planted.Interp.f_sub == base.Interp.f_sub);
    ("f_mul", planted.Interp.f_mul == base.Interp.f_mul);
    ("f_div", planted.Interp.f_div == base.Interp.f_div);
    ("f_neg", planted.Interp.f_neg == base.Interp.f_neg);
    ("f_eq", planted.Interp.f_eq == base.Interp.f_eq);
    ("f_lt", planted.Interp.f_lt == base.Interp.f_lt);
    ("f_le", planted.Interp.f_le == base.Interp.f_le);
    ("f_gt", planted.Interp.f_gt == base.Interp.f_gt);
    ("f_ge", planted.Interp.f_ge == base.Interp.f_ge);
    ("f_of_int", planted.Interp.f_of_int == base.Interp.f_of_int);
    ("f_debug", planted.Interp.f_debug == base.Interp.f_debug);
    ("str_cmp", planted.Interp.str_cmp == base.Interp.str_cmp);
    ("str_debug", planted.Interp.str_debug == base.Interp.str_debug);
    ("str_trim", planted.Interp.str_trim == base.Interp.str_trim);
    ("str_trim_start", planted.Interp.str_trim_start == base.Interp.str_trim_start);
    ("str_trim_end", planted.Interp.str_trim_end == base.Interp.str_trim_end);
    ( "str_starts_with",
      planted.Interp.str_starts_with == base.Interp.str_starts_with );
    ("str_ends_with", planted.Interp.str_ends_with == base.Interp.str_ends_with);
    ("str_contains", planted.Interp.str_contains == base.Interp.str_contains);
  ]

let check_untouched_fields () =
  List.iter
    (fun (n, ok) -> Alcotest.(check bool) ("untouched: " ^ n) true ok)
    same_fields

(* The replaced field is checked by behaviour and not by identity.  The
   last line pins the TRANSFORM rather than the outcome:  a plant that
   always prepended a minus sign passes the first three and fails this
   one. *)
let check_display_field () =
  Alcotest.(check string) "the base renders 1.5" "1.5"
    (base.Interp.f_display 1073217536 0);
  Alcotest.(check string) "the plant renders -1.5" "-1.5"
    (planted.Interp.f_display 1073217536 0);
  Alcotest.(check string) "the plant renders -2.5" "-2.5"
    (planted.Interp.f_display 1074003968 0);
  Alcotest.(check string) "the plant is self-inverse" "1.5"
    (planted.Interp.f_display 3220701184 0)

(* ---------- group 3: the leg under the two configs ---------- *)

let planted_config =
  {
    Ref_leg.default_config with
    Ref_leg.ops = Plant.ref_ops Plant.Rp_display_sign;
  }

let encoded (cfg : Ref_leg.config) (s : Sample.t) : string =
  Obs.encode (Ref_leg.observe cfg s)

let at (n : int) : Sample.t option = List.nth_opt Driver.seed_cases n

(* The clean config is built through Plant.ops No_plant and never from
   Ops.interp_ops directly, so a plant that leaks into the unplanted
   path fails this group.  Tooth T3 of spec section 13 is that leak,
   and it must be caught by the unit suite as well as by check 4 of the
   gate, so that neither one is load bearing alone. *)
let clean_config : Ref_leg.config =
  { Ref_leg.default_config with Ref_leg.ops = Plant.ops Plant.No_plant }

let case_texts (n : int) : (string * string) option =
  Option.map
    (fun s -> (encoded clean_config s, encoded planted_config s))
    (at n)

(* Option.fold ~none: is EAGER, so the none arm is one total call that
   builds a sentinel.  A missing seed then fails the literal check by
   name instead of passing quietly. *)
let missing (n : int) : string = "<missing case " ^ string_of_int n ^ ">"

let clean_text (n : int) : string =
  Option.fold ~none:(missing n) ~some:(fun (clean, _) -> clean) (case_texts n)

let plant_text (n : int) : string =
  Option.fold ~none:(missing n) ~some:(fun (_, plant) -> plant) (case_texts n)

let check_moved () =
  List.iter
    (fun (n, want) ->
      Alcotest.(check string) ("clean " ^ string_of_int n) want (clean_text n);
      Alcotest.(check bool)
        ("moved " ^ string_of_int n)
        false
        (String.equal (clean_text n) (plant_text n)))
    [
      (0, "Vf1073217536:0;|r3:1.5|");
      (3, "VSf1073217536:0;|r3:1.5|");
      (6, "Vf1074003968:0;|r3:2.5|g3:f1074003968:0;");
    ]

(* The planted text is pinned here as a literal, so the suite and the
   gate heredoc of spec section 9 are derived twice and independently. *)
let check_moved_text () =
  List.iter
    (fun (n, want) ->
      Alcotest.(check string) ("planted " ^ string_of_int n) want (plant_text n))
    [
      (0, "Vf1073217536:0;|r4:-1.5|");
      (3, "VSf1073217536:0;|r4:-1.5|");
      (6, "Vf1074003968:0;|r4:-2.5|g3:f1074003968:0;");
    ]

let check_held () =
  List.iter
    (fun n ->
      Alcotest.(check bool)
        ("present " ^ string_of_int n)
        false
        (String.equal (clean_text n) (missing n));
      Alcotest.(check string)
        ("held " ^ string_of_int n)
        (clean_text n) (plant_text n))
    [ 1; 2; 4; 5; 7; 8; 9; 10; 11 ]

(* ---------- group 4: the js argv ---------- *)

let planted_js =
  {
    (Js_leg.default_config ~root:"/r") with
    Js_leg.plant = Plant.Js Plant.Jp_signal_get_plus_one;
  }

let check_planted_argv () =
  Alcotest.(check (list string))
    "the planted node argv"
    (Js_leg.argv (Js_leg.default_config ~root:"/r") ~rust:"/in.jsonl"
       ~out:"/out.jsonl"
    @ [ "--plant"; "signal_get_plus_one" ])
    (Js_leg.argv planted_js ~rust:"/in.jsonl" ~out:"/out.jsonl")

(* The isolation property in unit form:  a reference plant adds nothing
   to the child process's argument vector. *)
let check_ref_argv () =
  Alcotest.(check (list string))
    "a ref plant adds nothing to the node argv"
    (Js_leg.argv (Js_leg.default_config ~root:"/r") ~rust:"/in.jsonl"
       ~out:"/out.jsonl")
    (Js_leg.argv
       {
         (Js_leg.default_config ~root:"/r") with
         Js_leg.plant = Plant.Ref Plant.Rp_display_sign;
       }
       ~rust:"/in.jsonl" ~out:"/out.jsonl")

let () =
  Alcotest.run "plant"
    [
      ( "names",
        [
          Alcotest.test_case "spellings" `Quick check_names;
          Alcotest.test_case "round trip" `Quick check_round_trip;
          Alcotest.test_case "rejections" `Quick check_rejections;
        ] );
      ( "ops",
        [
          Alcotest.test_case "twenty untouched fields" `Quick
            check_untouched_fields;
          Alcotest.test_case "the display field" `Quick check_display_field;
        ] );
      ( "ref leg",
        [
          Alcotest.test_case "three seeds move" `Quick check_moved;
          Alcotest.test_case "the planted text" `Quick check_moved_text;
          Alcotest.test_case "nine seeds hold" `Quick check_held;
        ] );
      ( "js argv",
        [
          Alcotest.test_case "a js plant appends" `Quick check_planted_argv;
          Alcotest.test_case "a ref plant appends nothing" `Quick
            check_ref_argv;
        ] );
    ]
