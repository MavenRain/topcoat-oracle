(* M27 unit vectors for core/differ.ml (M27 spec section 8).  Pure: no
   process, no file and no directory.  The stanza in test/dune lists
   oracle_core and NOT oracle_shell, which is itself a proof that the
   differ never reached into the shell.

   Every expectation below is a LITERAL.  Nothing is computed by the
   code under test and no expectation is derived from Obs.encode.  The
   twelve seed vectors are transcribed by hand from the 36-line M26
   table, every f64 as its two halves and every message as its bytes.

   These vectors are the DESIGN GATE.  The printed 48-line table cannot
   see All_three, the signals rule or the non-party absence, and only
   these vectors can. *)

open Prelude
open Differ

(* ---------- helpers ---------- *)

let obs (o : Obs.outcome) (r : string) (sg : (int * Obs.value) list) :
    Obs.observation =
  { Obs.outcome = o; rendered = r; signals = sg }

let p (o : Obs.outcome) (r : string) (sg : (int * Obs.value) list) : cell =
  Present (obs o r sg)

let cs3 (r : cell) (j : cell) (f : cell) : cells =
  { rust = r; js = j; reference = f }

let ro : Taxonomy.mode = Taxonomy.Read_only
let sw : Taxonomy.mode = Taxonomy.Signal_writing

let vt (m : Taxonomy.mode) (ks : known list) (cs : cells) : string =
  verdict_text (verdict m ks cs)

(* A local testable, so the tags are compared without a helper from the
   module under test. *)
let tag_t : tag Alcotest.testable =
  Alcotest.testable
    (fun ppf t -> match t with Tag s -> Format.fprintf ppf "Tag %s" s)
    (fun a b -> match a with Tag x -> ( match b with Tag y -> String.equal x y))

(* A plain unit value cell, used wherever a vector needs a party that
   agrees on every channel. *)
let any : cell = p (Obs.O_value Obs.V_unit) "" []

(* ---------- group 1: the twelve seed vectors ---------- *)

let case0_cells =
  let c = p (Obs.O_value (Obs.V_f64_bits (1073217536, 0))) "1.5" [] in
  cs3 c c c

let case1_cells =
  let r = p (Obs.O_value (Obs.V_str "a<b>+c")) "a&lt;b&gt;+c" [] in
  let j = p (Obs.O_value (Obs.V_str "a<b>+c")) "a<b>+c" [] in
  cs3 r j j

let case2_cells =
  let c = p (Obs.O_value (Obs.V_str "")) "" [] in
  cs3 c c c

let case3_cells =
  let c =
    p (Obs.O_value (Obs.V_some (Obs.V_f64_bits (1073217536, 0)))) "1.5" []
  in
  cs3 c c c

let case4_cells =
  let c = p (Obs.O_value Obs.V_none) "" [] in
  cs3 c c c

(* 43 bytes against 42: Option::unwrap() is one byte longer than
   Option.unwrap().  Nothing here recomputes those lengths. *)
let case5_cells =
  let r =
    p
      (Obs.O_panic
         (Obs.P_unwrap, "called `Option::unwrap()` on a `None` value"))
      "" []
  in
  let j =
    p
      (Obs.O_panic (Obs.P_other, "called `Option.unwrap()` on a `None` value"))
      "" []
  in
  cs3 r j r

let case6_cells =
  let c =
    p
      (Obs.O_value (Obs.V_f64_bits (1074003968, 0)))
      "2.5"
      [ (3, Obs.V_f64_bits (1074003968, 0)) ]
  in
  cs3 c c c

let case7_cells =
  let r =
    p
      (Obs.O_panic
         ( Obs.P_signal_write,
           "expressions in which a signal is written to cannot be run \
            server-side" ))
      ""
      [ (4, Obs.V_bool true) ]
  in
  let j = p (Obs.O_value Obs.V_unit) "" [ (4, Obs.V_bool false) ] in
  cs3 r j j

(* nope: "ok" is ten bytes with the two quote bytes, nope: ok is eight
   without them. *)
let case8_cells =
  let r = p (Obs.O_panic (Obs.P_expect_err, "nope: \"ok\"")) "" [] in
  let j = p (Obs.O_panic (Obs.P_expect_err, "nope: ok")) "" [] in
  cs3 r j r

let case9_cells =
  let c = p (Obs.O_panic (Obs.P_expect, "boom")) "" [] in
  cs3 c c c

let case10_cells =
  let r = p (Obs.O_panic (Obs.P_other, "nope: \"ok\"")) "" [] in
  let j = p (Obs.O_panic (Obs.P_other, "nope: ok")) "" [] in
  let f = p (Obs.O_panic (Obs.P_expect_err, "nope: \"ok\"")) "" [] in
  cs3 r j f

let case11_cells =
  let c = p Obs.O_no_terminate "" [] in
  cs3 c (Absent "skipped:no_js") c

let test_seed_with_known_seed () =
  Alcotest.(check string) "case 0" "agree" (vt ro (known_seed ()) case0_cells);
  Alcotest.(check string)
    "case 1" "diverge:rendered:odd:rust"
    (vt ro (known_seed ()) case1_cells);
  Alcotest.(check string) "case 2" "agree" (vt ro (known_seed ()) case2_cells);
  Alcotest.(check string) "case 3" "agree" (vt ro (known_seed ()) case3_cells);
  Alcotest.(check string) "case 4" "agree" (vt ro (known_seed ()) case4_cells);
  Alcotest.(check string)
    "case 5" "diverge:class:odd:js"
    (vt ro (known_seed ()) case5_cells);
  Alcotest.(check string) "case 6" "agree" (vt ro (known_seed ()) case6_cells);
  Alcotest.(check string) "case 7" "agree" (vt sw (known_seed ()) case7_cells);
  Alcotest.(check string)
    "case 8" "diverge:message:odd:js"
    (vt ro (known_seed ()) case8_cells);
  Alcotest.(check string) "case 9" "agree" (vt ro (known_seed ()) case9_cells);
  Alcotest.(check string)
    "case 10" "diverge:message:odd:js"
    (vt ro (known_seed ()) case10_cells);
  Alcotest.(check string)
    "case 11" "leg_fail:js:skipped:no_js"
    (vt ro (known_seed ()) case11_cells)

let test_seed_with_no_allowlist () =
  Alcotest.(check string) "case 0" "agree" (vt ro [] case0_cells);
  Alcotest.(check string)
    "case 1" "diverge:rendered:odd:rust" (vt ro [] case1_cells);
  Alcotest.(check string) "case 2" "agree" (vt ro [] case2_cells);
  Alcotest.(check string) "case 3" "agree" (vt ro [] case3_cells);
  Alcotest.(check string) "case 4" "agree" (vt ro [] case4_cells);
  Alcotest.(check string)
    "case 5" "diverge:class:odd:js" (vt ro [] case5_cells);
  Alcotest.(check string) "case 6" "agree" (vt ro [] case6_cells);
  Alcotest.(check string) "case 7" "agree" (vt sw [] case7_cells);
  Alcotest.(check string)
    "case 8" "diverge:message:odd:js" (vt ro [] case8_cells);
  Alcotest.(check string) "case 9" "agree" (vt ro [] case9_cells);
  Alcotest.(check string)
    "case 10" "diverge:class:odd:ref" (vt ro [] case10_cells);
  Alcotest.(check string)
    "case 11" "leg_fail:js:skipped:no_js" (vt ro [] case11_cells)

(* The eleven cases that are NOT case 10, written out as eleven literal
   expectations rather than as a loop over the block above. *)
let test_seed_eleven_unchanged () =
  Alcotest.(check (list string))
    "eleven with known_seed ()"
    [
      "agree";
      "diverge:rendered:odd:rust";
      "agree";
      "agree";
      "agree";
      "diverge:class:odd:js";
      "agree";
      "agree";
      "diverge:message:odd:js";
      "agree";
      "leg_fail:js:skipped:no_js";
    ]
    [
      vt ro (known_seed ()) case0_cells;
      vt ro (known_seed ()) case1_cells;
      vt ro (known_seed ()) case2_cells;
      vt ro (known_seed ()) case3_cells;
      vt ro (known_seed ()) case4_cells;
      vt ro (known_seed ()) case5_cells;
      vt ro (known_seed ()) case6_cells;
      vt sw (known_seed ()) case7_cells;
      vt ro (known_seed ()) case8_cells;
      vt ro (known_seed ()) case9_cells;
      vt ro (known_seed ()) case11_cells;
    ];
  Alcotest.(check (list string))
    "eleven with []"
    [
      "agree";
      "diverge:rendered:odd:rust";
      "agree";
      "agree";
      "agree";
      "diverge:class:odd:js";
      "agree";
      "agree";
      "diverge:message:odd:js";
      "agree";
      "leg_fail:js:skipped:no_js";
    ]
    [
      vt ro [] case0_cells;
      vt ro [] case1_cells;
      vt ro [] case2_cells;
      vt ro [] case3_cells;
      vt ro [] case4_cells;
      vt ro [] case5_cells;
      vt ro [] case6_cells;
      vt sw [] case7_cells;
      vt ro [] case8_cells;
      vt ro [] case9_cells;
      vt ro [] case11_cells;
    ]

let test_seed_excused () =
  Alcotest.(check (list tag_t))
    "case 10 excuses I1" [ Tag "I1" ]
    (excused ro (known_seed ()) case10_cells);
  Alcotest.(check (list tag_t))
    "case 0 excuses nothing" [] (excused ro (known_seed ()) case0_cells);
  Alcotest.(check (list tag_t))
    "case 1 excuses nothing" [] (excused ro (known_seed ()) case1_cells);
  Alcotest.(check (list tag_t))
    "case 2 excuses nothing" [] (excused ro (known_seed ()) case2_cells);
  Alcotest.(check (list tag_t))
    "case 3 excuses nothing" [] (excused ro (known_seed ()) case3_cells);
  Alcotest.(check (list tag_t))
    "case 4 excuses nothing" [] (excused ro (known_seed ()) case4_cells);
  Alcotest.(check (list tag_t))
    "case 5 excuses nothing" [] (excused ro (known_seed ()) case5_cells);
  Alcotest.(check (list tag_t))
    "case 6 excuses nothing" [] (excused ro (known_seed ()) case6_cells);
  Alcotest.(check (list tag_t))
    "case 7 excuses nothing" [] (excused sw (known_seed ()) case7_cells);
  Alcotest.(check (list tag_t))
    "case 8 excuses nothing" [] (excused ro (known_seed ()) case8_cells);
  Alcotest.(check (list tag_t))
    "case 9 excuses nothing" [] (excused ro (known_seed ()) case9_cells);
  Alcotest.(check (list tag_t))
    "case 11 excuses nothing" [] (excused ro (known_seed ()) case11_cells)

let test_seed_excused_no_allowlist () =
  Alcotest.(check (list tag_t)) "case 0" [] (excused ro [] case0_cells);
  Alcotest.(check (list tag_t)) "case 1" [] (excused ro [] case1_cells);
  Alcotest.(check (list tag_t)) "case 2" [] (excused ro [] case2_cells);
  Alcotest.(check (list tag_t)) "case 3" [] (excused ro [] case3_cells);
  Alcotest.(check (list tag_t)) "case 4" [] (excused ro [] case4_cells);
  Alcotest.(check (list tag_t)) "case 5" [] (excused ro [] case5_cells);
  Alcotest.(check (list tag_t)) "case 6" [] (excused ro [] case6_cells);
  Alcotest.(check (list tag_t)) "case 7" [] (excused sw [] case7_cells);
  Alcotest.(check (list tag_t)) "case 8" [] (excused ro [] case8_cells);
  Alcotest.(check (list tag_t)) "case 9" [] (excused ro [] case9_cells);
  Alcotest.(check (list tag_t)) "case 10" [] (excused ro [] case10_cells);
  Alcotest.(check (list tag_t)) "case 11" [] (excused ro [] case11_cells)

(* ---------- group 2: one vector per channel, one per split ---------- *)

let test_one_vector_per_channel () =
  Alcotest.(check string)
    "outcome" "diverge:outcome:odd:ref"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_value Obs.V_unit) "" [])
          (p (Obs.O_value Obs.V_unit) "" [])
          (p Obs.O_no_terminate "" [])));
  Alcotest.(check string)
    "class" "diverge:class:odd:js"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_panic (Obs.P_unwrap, "m")) "" [])
          (p (Obs.O_panic (Obs.P_expect, "m")) "" [])
          (p (Obs.O_panic (Obs.P_unwrap, "m")) "" [])));
  Alcotest.(check string)
    "message" "diverge:message:odd:ref"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_panic (Obs.P_expect, "a")) "" [])
          (p (Obs.O_panic (Obs.P_expect, "a")) "" [])
          (p (Obs.O_panic (Obs.P_expect, "b")) "" [])));
  (* The outcome kinds agree, the class and the message channels are
     vacuous and the rendered strings are equal, so only the value
     channel can fire. *)
  Alcotest.(check string)
    "value" "diverge:value:odd:ref"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_value (Obs.V_bool true)) "" [])
          (p (Obs.O_value (Obs.V_bool true)) "" [])
          (p (Obs.O_value (Obs.V_bool false)) "" [])));
  Alcotest.(check string)
    "rendered" "diverge:rendered:odd:js"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_value Obs.V_unit) "x" [])
          (p (Obs.O_value Obs.V_unit) "y" [])
          (p (Obs.O_value Obs.V_unit) "x" [])));
  Alcotest.(check string)
    "signals" "diverge:signals:odd:ref"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_value Obs.V_unit) "" [ (1, Obs.V_bool true) ])
          (p (Obs.O_value Obs.V_unit) "" [ (1, Obs.V_bool true) ])
          (p (Obs.O_value Obs.V_unit) "" [ (1, Obs.V_bool false) ])))

let rendered_cells (r : string) (j : string) (f : string) : cells =
  cs3
    (p (Obs.O_value Obs.V_unit) r [])
    (p (Obs.O_value Obs.V_unit) j [])
    (p (Obs.O_value Obs.V_unit) f [])

let test_one_vector_per_split () =
  Alcotest.(check string)
    "odd rust" "diverge:rendered:odd:rust"
    (vt ro (known_seed ()) (rendered_cells "a" "b" "b"));
  Alcotest.(check string)
    "odd js" "diverge:rendered:odd:js"
    (vt ro (known_seed ()) (rendered_cells "a" "b" "a"));
  Alcotest.(check string)
    "odd ref" "diverge:rendered:odd:ref"
    (vt ro (known_seed ()) (rendered_cells "a" "a" "b"));
  Alcotest.(check string)
    "all three" "diverge:rendered:all"
    (vt ro (known_seed ()) (rendered_cells "a" "b" "c"));
  (* The rust rendered text is a third string that matches neither
     party.  If the rust cell were ever a party the split would be
     All_three, so this vector is a second guard on the two-way rule. *)
  Alcotest.(check string)
    "two way" "diverge:rendered:two_way"
    (vt sw (known_seed ()) (rendered_cells "zzz" "a" "b"))

(* ---------- group 3: vacuity ---------- *)

let test_vacuity () =
  Alcotest.(check string)
    "kind mismatch reports the outcome only" "diverge:outcome:odd:rust"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_panic (Obs.P_unwrap, "m")) "" [])
          (p (Obs.O_value (Obs.V_bool true)) "" [])
          (p (Obs.O_value (Obs.V_bool true)) "" [])));
  (* The walk stops at the first unexcused channel and does not report
     the last one. *)
  Alcotest.(check string)
    "outcome before rendered" "diverge:outcome:odd:rust"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_panic (Obs.P_unwrap, "m")) "x" [])
          (p (Obs.O_value (Obs.V_bool true)) "y" [])
          (p (Obs.O_value (Obs.V_bool true)) "y" [])));
  (* Class, message and value are None for all three parties, so a
     vacuous channel is agreement and never a divergence. *)
  Alcotest.(check string)
    "three no-terminate cells agree" "agree"
    (vt ro (known_seed ())
       (cs3
          (p Obs.O_no_terminate "" [])
          (p Obs.O_no_terminate "" [])
          (p Obs.O_no_terminate "" [])));
  Alcotest.(check string)
    "the positive control" "agree"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_value (Obs.V_bool true)) "" [])
          (p (Obs.O_value (Obs.V_bool true)) "" [])
          (p (Obs.O_value (Obs.V_bool true)) "" [])))

(* ---------- group 4: signals by id ---------- *)

let signal_cells (r : (int * Obs.value) list) (j : (int * Obs.value) list)
    (f : (int * Obs.value) list) : cells =
  cs3
    (p (Obs.O_value Obs.V_unit) "" r)
    (p (Obs.O_value Obs.V_unit) "" j)
    (p (Obs.O_value Obs.V_unit) "" f)

let test_signals_by_id () =
  Alcotest.(check string)
    "another order" "agree"
    (vt ro (known_seed ())
       (signal_cells
          [ (1, Obs.V_bool true); (2, Obs.V_none) ]
          [ (2, Obs.V_none); (1, Obs.V_bool true) ]
          [ (1, Obs.V_bool true); (2, Obs.V_none) ]));
  Alcotest.(check string)
    "an extra id" "diverge:signals:odd:js"
    (vt ro (known_seed ())
       (signal_cells
          [ (1, Obs.V_unit) ]
          [ (1, Obs.V_unit); (3, Obs.V_unit) ]
          [ (1, Obs.V_unit) ]));
  Alcotest.(check string)
    "a changed value" "diverge:signals:odd:ref"
    (vt ro (known_seed ())
       (signal_cells
          [ (1, Obs.V_bool true) ]
          [ (1, Obs.V_bool true) ]
          [ (1, Obs.V_bool false) ]));
  Alcotest.(check string)
    "empty against non-empty" "diverge:signals:odd:rust"
    (vt ro (known_seed ())
       (signal_cells [] [ (1, Obs.V_unit) ] [ (1, Obs.V_unit) ]));
  (* A one-way subset check with a length test would call these two
     lists equal. *)
  Alcotest.(check string)
    "the both-ways subset guard" "diverge:signals:odd:js"
    (vt ro (known_seed ())
       (signal_cells
          [ (1, Obs.V_unit); (1, Obs.V_unit) ]
          [ (1, Obs.V_unit); (2, Obs.V_unit) ]
          [ (1, Obs.V_unit); (1, Obs.V_unit) ]))

(* ---------- group 5: Leg_fail ---------- *)

let test_leg_fail () =
  Alcotest.(check string)
    "rust before js" "leg_fail:rust:read:eof"
    (vt ro (known_seed ())
       (cs3 (Absent "read:eof") (Absent "skipped:no_js") any));
  Alcotest.(check string)
    "js before reference" "leg_fail:js:lossy:rendered_utf16_hex"
    (vt ro (known_seed ())
       (cs3 any (Absent "lossy:rendered_utf16_hex") (Absent "stuck")));
  Alcotest.(check string)
    "reference alone" "leg_fail:ref:stuck:init"
    (vt ro (known_seed ()) (cs3 any any (Absent "stuck:init")));
  (* A rust Absent on a Signal_writing sample is not a Leg_fail,
     because that cell is not a party. *)
  Alcotest.(check string)
    "non-party absence" "agree"
    (vt sw (known_seed ()) (cs3 (Absent "read:eof") any any));
  Alcotest.(check string)
    "party absence, two-way" "leg_fail:js:skipped:no_js"
    (vt sw (known_seed ()) (cs3 any (Absent "skipped:no_js") any));
  (* The reason text travels through unparsed, colons included. *)
  Alcotest.(check string)
    "reason carried verbatim" "leg_fail:js:js_error:5:Error:3:bad"
    (vt ro (known_seed ()) (cs3 any (Absent "js_error:5:Error:3:bad") any))

(* ---------- group 6: Known ---------- *)

(* Case 10's cells with all three messages set to nope: "ok", so only
   the class channel diverges. *)
let sole_excused_cells (r : string) (j : string) (f : string) : cells =
  cs3
    (p (Obs.O_panic (Obs.P_other, "nope: \"ok\"")) r [])
    (p (Obs.O_panic (Obs.P_other, "nope: \"ok\"")) j [])
    (p (Obs.O_panic (Obs.P_expect_err, "nope: \"ok\"")) f [])

let test_known () =
  Alcotest.(check string)
    "case 10 with known_seed ()" "diverge:message:odd:js"
    (vt ro (known_seed ()) case10_cells);
  Alcotest.(check (list tag_t))
    "case 10 excused with known_seed ()" [ Tag "I1" ]
    (excused ro (known_seed ()) case10_cells);
  Alcotest.(check string)
    "case 10 with []" "diverge:class:odd:ref" (vt ro [] case10_cells);
  Alcotest.(check (list tag_t))
    "case 10 excused with []" [] (excused ro [] case10_cells);
  Alcotest.(check string)
    "the sole excused divergence" "known:I1"
    (vt ro (known_seed ()) (sole_excused_cells "" "" ""));
  Alcotest.(check string)
    "the sole excused divergence with []" "diverge:class:odd:ref"
    (vt ro [] (sole_excused_cells "" "" ""));
  (* i1 wants Odd L_ref and this split is Odd L_rust. *)
  Alcotest.(check string)
    "the wrong split" "diverge:class:odd:rust"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_panic (Obs.P_other, "m")) "" [])
          (p (Obs.O_panic (Obs.P_expect_err, "m")) "" [])
          (p (Obs.O_panic (Obs.P_expect_err, "m")) "" [])));
  (* The split is Odd L_ref but the other two are not P_other. *)
  Alcotest.(check string)
    "the wrong classes" "diverge:class:odd:ref"
    (vt ro (known_seed ())
       (cs3
          (p (Obs.O_panic (Obs.P_expect, "m")) "" [])
          (p (Obs.O_panic (Obs.P_expect, "m")) "" [])
          (p (Obs.O_panic (Obs.P_expect_err, "m")) "" [])));
  (* An excused channel followed by an unexcused one.  A Known entry
     never masks a later channel. *)
  Alcotest.(check string)
    "an excused channel then an unexcused one" "diverge:rendered:odd:js"
    (vt ro (known_seed ()) (sole_excused_cells "x" "y" "x"));
  Alcotest.(check (list tag_t))
    "and the class channel was excused" [ Tag "I1" ]
    (excused ro (known_seed ()) (sole_excused_cells "x" "y" "x"))

(* ---------- group 7: the encoders ---------- *)

(* Pairwise distinctness, with a local fold and String.equal only. *)
let distinct (xs : string list) : bool =
  fold (fun ok x -> ok && len (List.filter (String.equal x) xs) = 1) true xs

let test_encoders () =
  Alcotest.(check string) "agree" "agree" (verdict_text Agree);
  Alcotest.(check string)
    "diverge" "diverge:rendered:odd:rust"
    (verdict_text (Diverge (Ch_rendered, Odd L_rust)));
  Alcotest.(check string) "known" "known:I1" (verdict_text (Known (Tag "I1")));
  Alcotest.(check string)
    "leg fail" "leg_fail:js:skipped:no_js"
    (verdict_text (Leg_fail (L_js, "skipped:no_js")));
  Alcotest.(check (list string))
    "channel names"
    [ "outcome"; "class"; "message"; "value"; "rendered"; "signals" ]
    [
      channel_name Ch_outcome;
      channel_name Ch_class;
      channel_name Ch_message;
      channel_name Ch_value;
      channel_name Ch_rendered;
      channel_name Ch_signals;
    ];
  Alcotest.(check (list string))
    "leg names" [ "rust"; "js"; "ref" ]
    [ leg_name L_rust; leg_name L_js; leg_name L_ref ];
  Alcotest.(check (list string))
    "split texts"
    [ "odd:rust"; "odd:js"; "odd:ref"; "all"; "two_way" ]
    [
      split_text (Odd L_rust);
      split_text (Odd L_js);
      split_text (Odd L_ref);
      split_text All_three;
      split_text Two_way;
    ]

let test_encoders_distinct () =
  Alcotest.(check bool)
    "six channel names" true
    (distinct
       [ "outcome"; "class"; "message"; "value"; "rendered"; "signals" ]);
  Alcotest.(check bool) "three leg names" true
    (distinct [ "rust"; "js"; "ref" ]);
  Alcotest.(check bool)
    "five split texts" true
    (distinct [ "odd:rust"; "odd:js"; "odd:ref"; "all"; "two_way" ]);
  (* The property the V column needs. *)
  Alcotest.(check bool)
    "the fourteen together" true
    (distinct
       [
         "outcome";
         "class";
         "message";
         "value";
         "rendered";
         "signals";
         "rust";
         "js";
         "ref";
         "odd:rust";
         "odd:js";
         "odd:ref";
         "all";
         "two_way";
       ])

let () =
  Alcotest.run "differ"
    [
      ( "seed-vectors",
        [
          Alcotest.test_case "twelve cases with known_seed ()" `Quick
            test_seed_with_known_seed;
          Alcotest.test_case "twelve cases with []" `Quick
            test_seed_with_no_allowlist;
          Alcotest.test_case "eleven unchanged between the lists" `Quick
            test_seed_eleven_unchanged;
          Alcotest.test_case "excused with known_seed ()" `Quick
            test_seed_excused;
          Alcotest.test_case "excused with []" `Quick
            test_seed_excused_no_allowlist;
        ] );
      ( "channels-and-splits",
        [
          Alcotest.test_case "one vector per channel" `Quick
            test_one_vector_per_channel;
          Alcotest.test_case "one vector per split" `Quick
            test_one_vector_per_split;
        ] );
      ("vacuity", [ Alcotest.test_case "vacuous channels" `Quick test_vacuity ]);
      ( "signals",
        [ Alcotest.test_case "signals by id" `Quick test_signals_by_id ] );
      ("leg-fail", [ Alcotest.test_case "absent cells" `Quick test_leg_fail ]);
      ("known", [ Alcotest.test_case "the I1 entry" `Quick test_known ]);
      ( "encoders",
        [
          Alcotest.test_case "verdict text" `Quick test_encoders;
          Alcotest.test_case "pairwise distinct" `Quick test_encoders_distinct;
        ] );
    ]
