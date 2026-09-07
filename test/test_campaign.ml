(** M34 aggregation vectors use explicit normalized signatures, independent
    of the generator.  Shell integration separately checks AST regeneration. *)

let row (i : int) (mode : string) (verdict : string) (size : int)
    (body : string) : Journal.line =
  { Journal.jl_i = i; Journal.jl_mode = mode; Journal.jl_size = size;
    Journal.jl_verdict = verdict; Journal.jl_r = ""; Journal.jl_j = "";
    Journal.jl_f = ""; Journal.jl_env = []; Journal.jl_body = body }

let with_report rows signatures inspect =
  Result.fold
    ~error:(fun e ->
      Alcotest.(check string) "analysis succeeds" "success"
        (Campaign.error_text e))
    ~ok:inspect (Campaign.analyze rows signatures)

let rejected rows signatures expected =
  Alcotest.(check string) "precise rejection" expected
    (Result.fold ~ok:(fun _ -> "accepted") ~error:Campaign.error_text
       (Campaign.analyze rows signatures))

let test_grouping () =
  let rows =
    [ row 0 "read_only" "diverge:value:odd:js" 8 "a + 1";
      row 1 "read_only" "known:I1" 8 "a + 1";
      row 2 "read_only" "diverge:value:odd:js" 2 "renamed + 999";
      row 3 "read_only" "diverge:rendered:odd:js" 8 "a + 1";
      row 4 "signal_writing" "diverge:value:two_way" 8 "a + 1";
      row 5 "read_only" "diverge:value:odd:js" 8 "a - 1";
      row 6 "read_only" "agree" 8 "a + 1";
      row 7 "read_only" "diverge:value:odd:js" 4 "other + 2" ]
  in
  with_report rows [ "add"; "add"; "add"; "add"; "add"; "sub"; "add"; "add" ]
    (fun r ->
      Alcotest.(check int) "all attempts" 8 r.Campaign.r_total;
      Alcotest.(check int) "read-only attempts" 7 r.Campaign.r_read_only;
      Alcotest.(check int) "signal-writing attempts" 1 r.Campaign.r_signal_writing;
      Alcotest.(check int) "Known counted but excluded from candidates" 1
        r.Campaign.r_tally.Journal.t_known;
      Alcotest.(check int) "raw divergences" 6 r.Campaign.r_tally.Journal.t_diverge;
      Alcotest.(check (list int)) "first-appearance representatives"
        [ 0; 3; 4; 5 ]
        (Prelude.map (fun g -> g.Campaign.g_first) r.Campaign.r_groups);
      Alcotest.(check (list (list int))) "all indices survive in encounter order"
        [ [ 0; 2; 7 ]; [ 3 ]; [ 4 ]; [ 5 ] ]
        (Prelude.map (fun g -> g.Campaign.g_indices) r.Campaign.r_groups);
      Alcotest.(check (list int)) "group sizes" [ 3; 1; 1; 1 ]
        (Prelude.map (fun g -> g.Campaign.g_count) r.Campaign.r_groups);
      Alcotest.(check (list int)) "minimum does not change representative"
        [ 2; 8; 8; 8 ]
        (Prelude.map (fun g -> g.Campaign.g_min_size) r.Campaign.r_groups);
      Alcotest.(check (list string)) "construct differences remain separate"
        [ "add"; "add"; "add"; "sub" ]
        (Prelude.map (fun g -> g.Campaign.g_signature) r.Campaign.r_groups))

let test_losses () =
  let verdicts =
    [ "agree"; "known:FUTURE:tag"; "diverge:value:odd:ref";
      "leg_fail:js:signal_arity"; "dropped"; "no_line";
      "batch_fail:driver: exited 1"; "leg_fail:js:signal_arity";
      "batch_fail:driver: exited 1" ]
  in
  let indexed =
    snd
      (Prelude.fold
         (fun acc verdict ->
           let i = fst acc in
           let mode = if Int.equal (i land 1) 0 then "read_only" else "signal_writing" in
           (i + 1, Prelude.append (snd acc) [ row i mode verdict 1 "1" ]))
         (0, []) verdicts)
  in
  with_report indexed (Prelude.map (fun _ -> "literal") verdicts)
    (fun r ->
      let t = r.Campaign.r_tally in
      Alcotest.(check (list int)) "every raw bucket is counted"
        [ 1; 1; 1; 2; 1; 1; 2; 0 ]
        [ t.Journal.t_agree; t.Journal.t_known; t.Journal.t_diverge;
          t.Journal.t_leg_fail; t.Journal.t_dropped; t.Journal.t_no_line;
          t.Journal.t_batch_fail; t.Journal.t_other ];
      Alcotest.(check int) "complete adjudications" 3 (Campaign.adjudicated r);
      Alcotest.(check int) "losses are explicit" 6 (Campaign.losses r);
      Alcotest.(check int) "attempts partition exactly" r.Campaign.r_total
        (Campaign.adjudicated r + Campaign.losses r);
      Alcotest.(check (list (pair string int))) "all full verdict texts retained"
        [ ("batch_fail:driver: exited 1", 2); ("diverge:value:odd:ref", 1);
          ("dropped", 1); ("known:FUTURE:tag", 1);
          ("leg_fail:js:signal_arity", 2); ("no_line", 1) ]
        (Journal.sort_texts t.Journal.t_texts))

let test_alignment () =
  let first = row 0 "read_only" "agree" 1 "1" in
  rejected [ first ] [] "expected 1 construct signatures, got 0";
  rejected [] [ "literal" ] "expected 0 construct signatures, got 1";
  rejected [ first ] [ "literal"; "extra" ]
    "expected 1 construct signatures, got 2";
  rejected [ { first with Journal.jl_i = 1 } ] [ "literal" ]
    "row at position 0 does not carry its expected contiguous sample index";
  rejected [ first; first ] [ "literal"; "literal" ]
    "row at position 1 does not carry its expected contiguous sample index";
  rejected [ first; { first with Journal.jl_i = 2 } ] [ "literal"; "literal" ]
    "row at position 1 does not carry its expected contiguous sample index";
  rejected [ { first with Journal.jl_mode = "readonly" } ] [ "literal" ]
    "sample 0 has an unknown mode \"readonly\"";
  rejected [ { first with Journal.jl_size = -1 } ] [ "literal" ]
    "sample 0 has a negative size";
  rejected [ first ] [ "" ] "sample 0 has an empty construct signature"

let test_grammar () =
  let invalid =
    [ "agree:extra"; "dropped:extra"; "no_line:extra"; "known"; "known:";
      "batch_fail"; "batch_fail:"; "leg_fail:js:"; "leg_fail:browser:missing";
      "diverge"; "diverge:value"; "diverge:unknown:all";
      "diverge:value:odd:browser"; "diverge:value:odd:js:extra";
      "diverge:value:all:extra"; "diverge:value:two_way:extra" ]
  in
  Prelude.fold
    (fun () verdict ->
      rejected [ row 0 "read_only" verdict 1 "1" ] [ "literal" ]
        ("sample 0 has an invalid verdict " ^ Journal.jstring verdict))
    () invalid;
  rejected [ row 0 "read_only" "future:verdict" 1 "1" ] [ "literal" ]
    "sample 0 has an unknown verdict head \"future\"";
  Prelude.fold
    (fun () channel ->
      Prelude.fold
        (fun () split ->
          let verdict = Differ.verdict_text (Differ.Diverge (channel, split)) in
          let mode =
            match split with
            | Differ.Two_way -> "signal_writing"
            | Differ.Odd _ | Differ.All_three -> "read_only"
          in
          with_report [ row 0 mode verdict 1 "1" ] [ "literal" ]
            (fun r -> Alcotest.(check int) verdict 1
                r.Campaign.r_tally.Journal.t_diverge))
        () [ Differ.Odd Differ.L_rust; Differ.Odd Differ.L_js;
             Differ.Odd Differ.L_ref; Differ.All_three; Differ.Two_way ])
    () (Differ.channels ());
  Prelude.fold
    (fun () vector ->
      rejected [ row 0 (fst vector) (snd vector) 1 "1" ] [ "literal" ]
        ("sample 0 has an invalid verdict " ^ Journal.jstring (snd vector)))
    () [ ("read_only", "diverge:value:two_way");
         ("signal_writing", "diverge:value:odd:js");
         ("signal_writing", "diverge:value:odd:ref");
         ("signal_writing", "diverge:value:odd:rust");
         ("signal_writing", "diverge:value:all") ];
  Prelude.fold
    (fun () leg ->
      let verdict = Differ.verdict_text (Differ.Leg_fail (leg, "reason:details")) in
      with_report [ row 0 "read_only" verdict 1 "1" ] [ "literal" ]
        (fun r -> Alcotest.(check int) verdict 1 r.Campaign.r_tally.Journal.t_leg_fail))
    () [ Differ.L_rust; Differ.L_js; Differ.L_ref ]

let header () : Journal.header =
  { Journal.jh_seed = 42; Journal.jh_batch = 100; Journal.jh_plant = "none";
    Journal.jh_topcoat = "51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a" }

let test_markdown () =
  let rows =
    [ row 0 "read_only" "diverge:value:odd:js" 1 "1";
      row 1 "signal_writing" "leg_fail:js:bad|<script>&`\nnext" 1 "1" ]
  in
  with_report rows [ "a|<b>&`\n"; "literal" ] (fun r ->
      let rendered = Campaign.markdown (header ()) r in
      Alcotest.(check string) "repeat rendering is identical" rendered
        (Campaign.markdown (header ()) r);
      Prelude.fold
        (fun () wanted -> Alcotest.(check bool) wanted true
            (Prelude.occurs rendered wanted))
        () [ "m34 samples 2 read_only 1 signal_writing 1\n";
             "m34 adjudicated 1 losses 1\n";
             "m34 groups 1 members 1\n";
             "<code>42&#58;0</code>";
             "<code>a&#124;&lt;b&gt;&amp;&#96;&#10;</code>";
             "<code>leg&#95;fail&#58;js&#58;bad&#124;&lt;script&gt;&amp;&#96;&#10;next</code>" ];
      Alcotest.(check bool) "reason cannot create HTML" false
        (Prelude.occurs rendered "<script>"))

(** These inputs previously became images, links and formatted text inside
    inline HTML code tags when consumed by a GFM renderer. *)
let test_code_markup () =
  Prelude.fold
    (fun () vector ->
      Alcotest.(check string) (fst vector) (snd vector)
        (Campaign.code (fst vector)))
    ()
    [ ("![x](https://example.invalid/x.png)",
       "<code>&#33;&#91;x&#93;(https&#58;//example&#46;invalid/x&#46;png)</code>");
      ("[click](https://example.invalid)",
       "<code>&#91;click&#93;(https&#58;//example&#46;invalid)</code>");
      ("**strong** _em_ ~~strike~~ \\[link]",
       "<code>&#42;&#42;strong&#42;&#42; &#95;em&#95; &#126;&#126;strike&#126;&#126; &#92;&#91;link&#93;</code>");
      ("https://example.invalid www.example.invalid a@example.invalid",
       "<code>https&#58;//example&#46;invalid www&#46;example&#46;invalid a&#64;example&#46;invalid</code>") ]

let test_empty () =
  with_report [] [] (fun r ->
      Alcotest.(check int) "no attempts" 0 r.Campaign.r_total;
      Alcotest.(check int) "no candidates" 0 (Prelude.len r.Campaign.r_groups);
      Alcotest.(check int) "no adjudications" 0 (Campaign.adjudicated r);
      Alcotest.(check bool) "explicit empty group message" true
        (Prelude.occurs (Campaign.markdown (header ()) r)
           "No unexcused divergence groups."))

let () =
  Alcotest.run "m34-campaign"
    [ ("grouping", [ Alcotest.test_case "normalized keys preserve evidence" `Quick test_grouping ]);
      ("accounting", [ Alcotest.test_case "every loss and Known tag" `Quick test_losses ]);
      ("validation", [ Alcotest.test_case "aligned complete inputs" `Quick test_alignment;
                       Alcotest.test_case "verdict grammar" `Quick test_grammar ]);
      ("render", [ Alcotest.test_case "stable and escaped" `Quick test_markdown;
                   Alcotest.test_case "Markdown stays literal" `Quick test_code_markup;
                   Alcotest.test_case "empty analysis" `Quick test_empty ]) ]
