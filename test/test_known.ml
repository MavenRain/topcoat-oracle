(* M33 unit vectors for core/known.ml.  Pure: no process, no file and no
   directory.  The stanza in test/dune lists oracle_core and alcotest only,
   which is itself a proof that the allowlist never reaches into the shell.

   Every expectation is a LITERAL.  Nothing is computed by the code under
   test, and the messages are transcribed from the corpus rows of the M33
   spec section 10.4. *)

open Prelude
open Differ

(** Keep observation channels explicit so a vector isolates the intended difference. *)
let obs (o : Obs.outcome) (r : string) (sg : (int * Obs.value) list) :
    Obs.observation =
  { Obs.outcome = o; rendered = r; signals = sg }

(** Build present panic cells so these vectors reach the channel comparison. *)
let panic (q : Obs.panic_class) (m : string) (r : string) : cell =
  Present (obs (Obs.O_panic (q, m)) r [])

(** Name all three parties so each fixture makes the corroborating cells visible. *)
let cs3 (r : cell) (j : cell) (f : cell) : cells = { rust = r; js = j; reference = f }

(** Keep the three-party mode explicit in every read-only expectation. *)
let ro : Taxonomy.mode = Taxonomy.Read_only

(** Exercise the two-party comparison while retaining the reference evidence. *)
let sw : Taxonomy.mode = Taxonomy.Signal_writing

(** Compare the public verdict spelling so a control also checks its reported channel. *)
let vt (m : Taxonomy.mode) (ks : known list) (cs : cells) : string =
  verdict_text (verdict m ks cs)

(** Compare tag payloads directly so an excused-tag failure names the differing tag. *)
let tag_t : tag Alcotest.testable =
  Alcotest.testable
    (fun ppf t -> match t with Tag s -> Format.fprintf ppf "Tag %s" s)
    (fun a b -> match a with Tag x -> (match b with Tag y -> String.equal x y))

(* The two texts of the I2 shape, byte for byte: the Rust spelling with two
   colons and the surrogate spelling with a dot. *)
let colon_none = "called `Option::unwrap()` on a `None` value"

(** Preserve the surrogate spelling so the masking control keeps a real message difference. *)
let dotted_none = "called `Option.unwrap()` on a `None` value"

(* ---------- I1: the reference evaluated the left operand first ---------- *)

(** Hold every other channel equal so I1 alone determines the positive verdict. *)
let i1_cells = cs3 (panic Obs.P_other "m" "") (panic Obs.P_other "m" "")
    (panic Obs.P_expect_err "m" "")

(** Give the reference its own panic text, which is the shape the allowlist
    entry excuses: the class channel is excused and the message channel of
    the same row is reported instead. *)
let i1_msg_cells = cs3 (panic Obs.P_other "left" "")
    (panic Obs.P_other "left" "") (panic Obs.P_expect_err "right" "")

(** Leave a rendered difference after the I1 excuse to test that the walk continues. *)
let i1_masking_cells = cs3 (panic Obs.P_other "m" "x")
    (panic Obs.P_other "m" "y") (panic Obs.P_expect_err "m" "x")

(** Separate reference-versus-rust from reference-versus-js.  The reference
    text equals the RUST text and only the js text moves, so the no-masking
    conjunct of core/known.ml:137-138 must refuse the row.  A conjunct that
    compared the reference with the js cell would excuse it, so this vector
    names the party the comparison reads. *)
let i1_js_msg_cells = cs3 (panic Obs.P_other "left" "")
    (panic Obs.P_other "right" "") (panic Obs.P_expect_err "left" "")

(** Pin I1 in both allowlist states and require a later difference to remain
    visible.  Under [allow ()] the entry can never produce a bare known:I1:
    it fires only when the reference message differs, so the row always
    reports that message divergence. *)
let test_i1 () =
  Alcotest.(check string)
    "I1 positive, the message channel is reported" "diverge:message:odd:ref"
    (vt ro (Known.allow ()) i1_msg_cells);
  Alcotest.(check (list tag_t))
    "I1 excused on the class channel alone" [ Tag "I1" ]
    (excused ro (Known.allow ()) i1_msg_cells);
  Alcotest.(check string)
    "I1 refuses a row whose reference message equals the rust message"
    "diverge:class:odd:ref" (vt ro (Known.allow ()) i1_cells);
  Alcotest.(check (list tag_t))
    "I1 excuses nothing on that row" [] (excused ro (Known.allow ()) i1_cells);
  Alcotest.(check string)
    "the frozen seed list keeps the M26 predicate" "known:I1"
    (vt ro (Known.seed ()) i1_cells);
  Alcotest.(check string)
    "I1 negative, no allowlist" "diverge:class:odd:ref" (vt ro [] i1_cells);
  Alcotest.(check string)
    "I1 does not mask a later channel" "diverge:rendered:odd:js"
    (vt ro (Known.seed ()) i1_masking_cells);
  Alcotest.(check (list tag_t))
    "I1 still excused on the masking vector" [ Tag "I1" ]
    (excused ro (Known.seed ()) i1_masking_cells);
  Alcotest.(check string)
    "I1 reads the rust message, not the js message"
    "diverge:class:odd:ref" (vt ro (Known.allow ()) i1_js_msg_cells);
  Alcotest.(check (list tag_t))
    "I1 excuses nothing when only the js message moves" []
    (excused ro (Known.allow ()) i1_js_msg_cells)

(* ---------- I2: the js prefix miss, both splits ---------- *)

(* odd:js with ONE message shared by all three: the class is the only
   divergent channel.  This is a NEGATIVE.  Identical message bytes under
   two class names is a drift between driver-rs/harness.rs and its js
   port, so I2 must refuse it and the row must keep its class verdict. *)
let i2_odd_cells = cs3 (panic Obs.P_unwrap colon_none "")
    (panic Obs.P_other colon_none "") (panic Obs.P_unwrap colon_none "")

(* The same refusal on the two-party split. *)
let i2_two_way_same_message_cells = cs3 (panic Obs.P_unwrap colon_none "")
    (panic Obs.P_expect colon_none "") (panic Obs.P_unwrap colon_none "")

(* two_way with an Absent rust cell.  Signal_writing does not read rust
   (core/differ.ml:36-38), so the excuse must not be a function of it. *)
let i2_absent_rust_cells = cs3 (Absent "no rust capture")
    (panic Obs.P_expect dotted_none "") (panic Obs.P_unwrap colon_none "")

(* An I2-shaped triple in which RUST is the odd party.  I2 declares
   odd:js and two_way only, so this row keeps its class verdict. *)
let i2_odd_rust_cells = cs3 (panic Obs.P_other dotted_none "")
    (panic Obs.P_unwrap colon_none "") (panic Obs.P_unwrap colon_none "")

(* All three classes differ, so the split is all.  I2 declares no such
   split. *)
let i2_all_three_cells = cs3 (panic Obs.P_unwrap colon_none "")
    (panic Obs.P_other dotted_none "") (panic Obs.P_expect_err "other text" "")

(* Every class agrees and only the rendered channel differs, so no entry
   may fire at all. *)
let rendered_only_cells = cs3 (panic Obs.P_other "m" "x")
    (panic Obs.P_other "m" "y") (panic Obs.P_other "m" "x")

(* odd:js with the surrogate text: corpus row i=425. *)
let i2_odd_masking_cells = cs3 (panic Obs.P_unwrap colon_none "")
    (panic Obs.P_other dotted_none "") (panic Obs.P_unwrap colon_none "")

(* two_way: corpus row i=0. *)
let i2_two_way_cells = cs3 (panic Obs.P_unwrap colon_none "")
    (panic Obs.P_expect dotted_none "") (panic Obs.P_unwrap colon_none "")

(* two_way in which rust disagrees with the reference.  rust is not a
   compared party here, so the excuse stands on the reference alone. *)
let i2_uncorroborated_cells = cs3 (panic Obs.P_other colon_none "")
    (panic Obs.P_other dotted_none "") (panic Obs.P_unwrap colon_none "")

(* The js fell back and the messages differ, but NEITHER compared party
   names an unwrap-family class.  Read as three parties the split is
   odd:js and core/known.ml:187 refuses it; read as two parties the split
   is two_way and core/known.ml:190 refuses it.  Dropping either
   corroboration conjunct excuses these rows, so both vectors are
   mutation kills for those conjuncts. *)
let i2_uncorroborated_class_cells = cs3 (panic Obs.P_other "x" "")
    (panic Obs.P_expect "y" "") (panic Obs.P_other "x" "")

(* Corpus row i=329: rust and js agree, the reference is the odd party.  M33
   excuses nothing here (M33 spec 10.4). *)
let unexcused_329_cells = cs3 (panic Obs.P_other "abc" "")
    (panic Obs.P_other "abc" "") (panic Obs.P_expect "abc" "")

(* The i=329 shape with a reference message of its own.  Under Read_only the
   split is odd:ref, so I1 is the only entry that can reach the row, and its
   message conjunct no longer refuses it.  The CLASS conjunct
   (core/known.ml:160) is then the one arm left: I1 names expect_err and this
   reference names expect, so the row keeps its class verdict.  A predicate
   widened to the whole expect family, which ruling Q2 forbids, excuses it. *)
let unexcused_expect_cells = cs3 (panic Obs.P_other "a" "")
    (panic Obs.P_other "a" "") (panic Obs.P_expect "b" "")

(** Require both I2 splits, corroboration and preservation of the remaining differences. *)
let test_i2 () =
  Alcotest.(check string)
    "I2 refuses a row whose js message equals the reference"
    "diverge:class:odd:js"
    (vt ro (Known.allow ()) i2_odd_cells);
  Alcotest.(check (list tag_t))
    "I2 excuses nothing on that row" [] (excused ro (Known.allow ()) i2_odd_cells);
  Alcotest.(check string)
    "the same refusal on two_way" "diverge:class:two_way"
    (vt sw (Known.allow ()) i2_two_way_same_message_cells);
  Alcotest.(check string)
    "I2 negative, the seed list" "diverge:class:odd:js"
    (vt ro (Known.seed ()) i2_odd_cells);
  Alcotest.(check string)
    "I2 negative, no allowlist" "diverge:class:odd:js" (vt ro [] i2_odd_cells);
  Alcotest.(check string)
    "I2 positive, odd:js, row i=425" "diverge:message:odd:js"
    (vt ro (Known.allow ()) i2_odd_masking_cells);
  Alcotest.(check (list tag_t))
    "I2 excused on the class channel alone" [ Tag "I2" ]
    (excused ro (Known.allow ()) i2_odd_masking_cells);
  Alcotest.(check string)
    "I2 positive, two_way, row i=0" "diverge:message:two_way"
    (vt sw (Known.allow ()) i2_two_way_cells);
  Alcotest.(check string)
    "I2 two_way negative" "diverge:class:two_way"
    (vt sw (Known.seed ()) i2_two_way_cells);
  Alcotest.(check string)
    "I2 does not read the rust cell on two_way" "diverge:message:two_way"
    (vt sw (Known.allow ()) i2_uncorroborated_cells);
  Alcotest.(check string)
    "an Absent rust cell does not delete the two_way excuse"
    "diverge:message:two_way"
    (vt sw (Known.allow ()) i2_absent_rust_cells);
  Alcotest.(check string)
    "I2 does not fire on odd:rust" "diverge:class:odd:rust"
    (vt ro (Known.allow ()) i2_odd_rust_cells);
  Alcotest.(check string)
    "I2 does not fire on the all split" "diverge:class:all"
    (vt ro (Known.allow ()) i2_all_three_cells);
  Alcotest.(check string)
    "no entry fires on a rendered-only difference" "diverge:rendered:odd:js"
    (vt ro (Known.allow ()) rendered_only_cells);
  Alcotest.(check string)
    "I2 refuses odd:js when neither compared party names an unwrap class"
    "diverge:class:odd:js"
    (vt ro (Known.allow ()) i2_uncorroborated_class_cells);
  Alcotest.(check string)
    "I2 refuses two_way when the reference names no unwrap class"
    "diverge:class:two_way"
    (vt sw (Known.allow ()) i2_uncorroborated_class_cells);
  Alcotest.(check string)
    "row i=329 keeps its class verdict" "diverge:class:two_way"
    (vt sw (Known.allow ()) unexcused_329_cells);
  Alcotest.(check string)
    "row i=329 read as three parties is odd:ref and still unexcused"
    "diverge:class:odd:ref" (vt ro (Known.allow ()) unexcused_329_cells);
  Alcotest.(check (list tag_t))
    "no entry excuses row i=329 on three parties" []
    (excused ro (Known.allow ()) unexcused_329_cells);
  Alcotest.(check string)
    "a reference expect class is not an expect_err class"
    "diverge:class:odd:ref" (vt ro (Known.allow ()) unexcused_expect_cells);
  Alcotest.(check (list tag_t))
    "no entry excuses the reference expect row" []
    (excused ro (Known.allow ()) unexcused_expect_cells)

(* ---------- the lists and the render ---------- *)

(** The render is searched with the ONE shared matcher, Prelude.occurs,
    which is also the matcher bin/m33.ml uses on a citation quote.  The
    test therefore exercises the CLI matcher and not a copy of it. *)
let occurs (hay : string) (nee : string) : bool = Prelude.occurs hay nee

(** Pin the list sizes, the tag order and the DECLARED fields, so an
    accidental allowlist change is visible.  The declared channel and splits
    are the fence core/known.ml:318 applies, and test_entry_fence derives its
    expectation from those same two fields, so both sides of that check move
    together when a declaration widens.  These two rows are the LITERALS that
    do not move: they are the pairs KNOWN.md renders. *)
let test_lists () =
  Alcotest.(check int) "two entries" 2 (len (Known.allow ()));
  Alcotest.(check int) "one seed entry" 1 (len (Known.seed ()));
  Alcotest.(check int) "eleven cite rows" 11 (len (Known.cite_rows ()));
  Alcotest.(check (list string))
    "the tags, in order" [ "I1"; "I2" ]
    (map (fun e -> tag_text e.Known.e_tag) (Known.entries ()));
  Alcotest.(check (list string))
    "the declared channels, in order" [ "class"; "class" ]
    (map (fun e -> channel_name e.Known.e_channel) (Known.entries ()));
  Alcotest.(check (list string))
    "the declared splits, in order"
    [ "odd:ref"; "odd:js two_way" ]
    (map
       (fun e -> joined " " (map split_text e.Known.e_splits))
       (Known.entries ()))

(* Every range is a range, and none is wider than twelve lines: a wide range
   makes the m33 cite quote check vacuous.  A very short quote makes it
   vacuous the other way, so every quote is at least twelve bytes, which is
   the bound bin/m33.ml:89 rejects below.  The shortest shipped quote is
   the sixteen byte "reason":"no_js". *)
let test_cites () =
  Alcotest.(check bool)
    "every range is short and every quote is long enough" true
    (fold
       (fun ok row ->
         let c = snd row in
         ok && c.Known.c_lo >= 1
         && c.Known.c_lo <= c.Known.c_hi
         && c.Known.c_hi - c.Known.c_lo <= 11
         && String.length c.Known.c_quote >= 12)
       true (Known.cite_rows ()))

(** Require each cited row to have its own block in the generated review document. *)
let test_render () =
  Alcotest.(check bool)
    "the render opens with the title" true
    (occurs (Known.render ()) "# Known divergences\n");
  Alcotest.(check bool)
    "the render carries the three headings" true
    (fold
       (fun ok h -> ok && occurs (Known.render ()) h)
       true
       [
         "\n## Entries\n";
         "\n## Documented, not excused today\n";
         "\n## Not on the allowlist\n";
       ]);
  Alcotest.(check bool)
    "every row has a block of its own" true
    (fold
       (fun ok row -> ok && occurs (Known.render ()) ("\n### " ^ fst row ^ "\n"))
       true (Known.cite_rows ()))

(* A closure that excuses EVERYTHING.  It stands in for an entry whose
   predicate was broadened past the channel and the splits KNOWN.md
   renders. *)
let broad_known () : known = { tag = Tag "BROAD"; applies = (fun _ _ _ -> true) }

(* One probe per (channel, split) pair the entries can name, plus one the
   entries never name.  Each probe carries the channel and the split its
   cells diverge on and the verdict a list that excuses nothing gives, so
   the expectation for a fenced closure is a function of the entry's own
   declared fields. *)
let probes () : (channel * split * Taxonomy.mode * cells * string) list =
  [
    (Ch_class, Odd L_ref, ro, i1_cells, "diverge:class:odd:ref");
    (Ch_class, Odd L_js, ro, i2_odd_cells, "diverge:class:odd:js");
    ( Ch_class, Two_way, sw, i2_two_way_same_message_cells,
      "diverge:class:two_way" );
    (Ch_rendered, Odd L_js, ro, rendered_only_cells, "diverge:rendered:odd:js");
  ]

(** Answer whether an entry declares this (channel, split) pair, with the
    same injective equalities core/known.ml uses. *)
let declares (e : Known.entry) (ch : channel) (s : split) : bool =
  channel_eq ch e.Known.e_channel
  && fold (fun acc s0 -> acc || split_eq s s0) false e.Known.e_splits

(** Pin the fence over the REAL entries: give each shipped entry a closure
    that excuses everything and require the entry's own declared channel and
    splits to hold it to exactly the pairs KNOWN.md renders. *)
let test_entry_fence () =
  fold
    (fun () e ->
      fold
        (fun () probe ->
          let ch, s, m, cs, unexcused = probe in
          let broad = Known.fence { e with Known.e_known = broad_known () } in
          let want = if declares e ch s then "known:BROAD" else unexcused in
          Alcotest.(check string)
            (tag_text e.Known.e_tag ^ " fenced on " ^ channel_name ch ^ " "
           ^ split_text s)
            want (vt m [ broad ] cs))
        () (probes ()))
    () (Known.entries ())

(** Require the declared channel and splits to fence the closure, so the
    rendered description of an entry cannot overstate what it excuses. *)
let test_declared () =
  Alcotest.(check string)
    "the declared channel and split still fire" "known:BROAD"
    (vt ro [ Known.declared Ch_class [ Odd L_ref ] (broad_known ()) ] i1_cells);
  Alcotest.(check string)
    "a split outside the declared list cannot fire" "diverge:class:odd:js"
    (vt ro
       [ Known.declared Ch_class [ Odd L_ref ] (broad_known ()) ]
       i2_odd_cells);
  Alcotest.(check string)
    "a channel outside the declared one cannot fire" "diverge:rendered:odd:js"
    (vt ro
       [ Known.declared Ch_class [ Odd L_ref ] (broad_known ()) ]
       rendered_only_cells);
  Alcotest.(check string)
    "the same closure unfenced would excuse that row" "known:BROAD"
    (vt ro [ broad_known () ] rendered_only_cells);
  test_entry_fence ()

(** Register all six controls so the normal test alias exercises the allowlist. *)
let () =
  Alcotest.run "m33-known"
    [
      ("i1", [ Alcotest.test_case "the I1 entry" `Quick test_i1 ]);
      ("i2", [ Alcotest.test_case "the I2 entry" `Quick test_i2 ]);
      ( "declared",
        [ Alcotest.test_case "the declared fields fence the closure" `Quick
            test_declared ] );
      ("lists", [ Alcotest.test_case "allow, seed and cite rows" `Quick test_lists ]);
      ("cites", [ Alcotest.test_case "every range is short" `Quick test_cites ]);
      ("render", [ Alcotest.test_case "the document shape" `Quick test_render ]);
    ]
