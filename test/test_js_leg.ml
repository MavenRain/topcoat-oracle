(* M26 js-leg tests (DESIGN.md M26, spec section 9.1).  PURE ONLY: no
   process, no file and no directory.  Every case runs against string
   constants.

   The corpus is the twelve m25 expected lines of spec 0.8, copied byte
   for byte from m25_verdict.sh:117-130.  They carry no uuid, so nothing
   needs masking here.

   The expected cells are the J column of the HAND-DERIVED table of spec
   section 8.5, not the output of this decoder.  Case 5 says
   Pother:42:called `Option.unwrap()` on a `None` value and case 8 says
   Pexpect_err:8:nope: ok;  both are pinned divergences (D1 and D4) and
   neither is smoothed here. *)

(* ---------- the seed corpus ---------- *)

let seed0 = {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"rendered_hex":"312e35","js_form":"direct","hint":"none","signals":[]}|j}

let seed1 = {j|{"case":1,"outcome":"value","value":{"t":"str","hex":"613c623e2b63"},"rendered_hex":"613c623e2b63","js_form":"direct","hint":"none","signals":[]}|j}

let seed2 = {j|{"case":2,"outcome":"value","value":{"t":"str","hex":""},"rendered_hex":"","js_form":"direct","hint":"none","signals":[]}|j}

let seed3 = {j|{"case":3,"outcome":"value","value":{"t":"some","v":{"t":"f64","hi":1073217536,"lo":0}},"rendered_hex":"312e35","js_form":"direct","hint":"none","signals":[]}|j}

let seed4 = {j|{"case":4,"outcome":"value","value":{"t":"none"},"rendered_hex":"","js_form":"direct","hint":"none","signals":[]}|j}

let seed5 = {j|{"case":5,"outcome":"panic","class":"other","msg_hex":"63616c6c656420604f7074696f6e2e756e77726170282960206f6e206120604e6f6e65602076616c7565","js_form":"closure","hint":"none","signals":[]}|j}

let seed6 = {j|{"case":6,"outcome":"value","value":{"t":"f64","hi":1074003968,"lo":0},"rendered_hex":"322e35","js_form":"direct","hint":"none","signals":[{"id":3,"value":{"t":"f64","hi":1074003968,"lo":0}}]}|j}

let seed7 = {j|{"case":7,"outcome":"value","value":{"t":"unit"},"rendered_hex":"","js_form":"closure","hint":"none","signals":[{"id":4,"value":{"t":"bool","v":false}}]}|j}

let seed8 = {j|{"case":8,"outcome":"panic","class":"expect_err","msg_hex":"6e6f70653a206f6b","js_form":"closure","hint":"expect_err","signals":[]}|j}

let seed9 = {j|{"case":9,"outcome":"panic","class":"expect","msg_hex":"626f6f6d","js_form":"closure","hint":"expect","signals":[]}|j}

let seed10 = {j|{"case":10,"outcome":"panic","class":"other","msg_hex":"6e6f70653a206f6b","js_form":"closure","hint":"both","signals":[]}|j}

let seed11 = {j|{"case":11,"outcome":"skipped","reason":"no_js"}|j}

let seed_lines =
  [ seed0; seed1; seed2; seed3; seed4; seed5; seed6; seed7; seed8; seed9;
    seed10; seed11 ]

(* The J column of spec 8.5, in case order. *)
let j_cells =
  [
    {j|Vf1073217536:0;|r3:1.5||j};
    {j|Vs6:a<b>+c|r6:a<b>+c||j};
    {j|Vs0:|r0:||j};
    {j|VSf1073217536:0;|r3:1.5||j};
    {j|Vn|r0:||j};
    {j|Pother:42:called `Option.unwrap()` on a `None` value|r0:||j};
    {j|Vf1074003968:0;|r3:2.5|g3:f1074003968:0;|j};
    {j|Vu|r0:|g4:b0|j};
    {j|Pexpect_err:8:nope: ok|r0:||j};
    {j|Pexpect:4:boom|r0:||j};
    {j|Pother:8:nope: ok|r0:||j};
    {j|skipped:no_js|j};
  ]

(* ---------- show helpers, so every check is a string compare ---------- *)

let werror_arg (w : Wire.werror) : string =
  match w with
  | Wire.W_json e -> Json.error_name e
  | Wire.W_not_object -> ""
  | Wire.W_missing_key k
  | Wire.W_extra_key k
  | Wire.W_bad_shape k
  | Wire.W_unknown_outcome k
  | Wire.W_unknown_tag k
  | Wire.W_unknown_class k
  | Wire.W_unknown_hint k
  | Wire.W_unknown_js_form k
  | Wire.W_odd_hex k
  | Wire.W_bad_hex k ->
      k
  | Wire.W_range (k, n) -> k ^ ":" ^ string_of_int n

let show_err (e : Wire_js.wjerror) : string =
  match e with
  | Wire_js.Wj_wire w -> "wire:" ^ Wire.werror_name w ^ ":" ^ werror_arg w
  | Wire_js.Wj_unknown_outcome s -> "unknown_outcome:" ^ s
  | Wire_js.Wj_unknown_reason s -> "unknown_reason:" ^ s
  | Wire_js.Wj_signal_shape s -> "signal_shape:" ^ s
  | Wire_js.Wj_bad_case n -> "bad_case:" ^ string_of_int n

let show (line : string) : string =
  Result.fold ~ok:Js_leg.cell
    ~error:(fun e -> "err:" ^ show_err e)
    (Wire_js.decode_line line)

(* ---------- group 1: the twelve positives ---------- *)

let rec check_pairs (i : int) (cells : string list) (lines : string list) : unit
    =
  match cells with
  | [] -> ()
  | c :: crest -> (
      match lines with
      | [] ->
          Alcotest.(check string) "the corpus is short" c "<missing line>"
      | l :: lrest ->
          Alcotest.(check string) ("case " ^ string_of_int i) c (show l);
          check_pairs (i + 1) crest lrest)

let check_seed_cells () = check_pairs 0 j_cells seed_lines

(* ---------- group 2: the key sets ---------- *)

let no_rendered = {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"js_form":"direct","hint":"none","signals":[]}|j}

let with_js_hex = {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"rendered_hex":"312e35","js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j}

let with_js_consistent = {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"rendered_hex":"312e35","js_consistent":true,"js_form":"direct","hint":"none","signals":[]}|j}

let weird_outcome = {j|{"case":0,"outcome":"weird","value":{"t":"unit"},"rendered_hex":"","js_form":"direct","hint":"none","signals":[]}|j}

let bad_class = {j|{"case":9,"outcome":"panic","class":"boom","msg_hex":"626f6f6d","js_form":"closure","hint":"expect","signals":[]}|j}

let bad_hint = {j|{"case":0,"outcome":"value","value":{"t":"unit"},"rendered_hex":"","js_form":"direct","hint":"maybe","signals":[]}|j}

let bad_reason = {j|{"case":11,"outcome":"skipped","reason":"whatever"}|j}

let check_key_sets () =
  Alcotest.(check string)
    "a missing rendered_hex" "err:wire:missing_key:rendered_hex"
    (show no_rendered);
  Alcotest.(check string)
    "js_hex is a Rust-side key" "err:wire:extra_key:js_hex" (show with_js_hex);
  Alcotest.(check string)
    "js_consistent is a Rust-side key" "err:wire:extra_key:js_consistent"
    (show with_js_consistent);
  Alcotest.(check string)
    "an unknown outcome" "err:unknown_outcome:weird" (show weird_outcome);
  Alcotest.(check string)
    "an unknown class" "err:wire:unknown_class:boom" (show bad_class);
  Alcotest.(check string)
    "an unknown hint" "err:wire:unknown_hint:maybe" (show bad_hint);
  Alcotest.(check string)
    "an unknown reason" "err:unknown_reason:whatever" (show bad_reason)

(* ---------- group 3: the signals shape ---------- *)

let two_key = {j|{"case":7,"outcome":"value","value":{"t":"unit"},"rendered_hex":"","js_form":"closure","hint":"none","signals":[{"id":4,"value":{"t":"bool","v":false}}]}|j}

let three_key = {j|{"case":7,"outcome":"value","value":{"t":"unit"},"rendered_hex":"","js_form":"closure","hint":"none","signals":[{"id":4,"value":{"t":"bool","v":false},"debug_hex":"64"}]}|j}

let array_entry = {j|{"case":7,"outcome":"value","value":{"t":"unit"},"rendered_hex":"","js_form":"closure","hint":"none","signals":[[4,false]]}|j}

let check_signals () =
  Alcotest.(check string)
    "a two-key signal entry" {j|Vu|r0:|g4:b0|j} (show two_key);
  Alcotest.(check string)
    "a three-key entry is the Rust shape" "err:wire:extra_key:debug_hex"
    (show three_key);
  Alcotest.(check string)
    "a signal entry that is an array" "err:signal_shape:signals"
    (show array_entry)

(* ---------- group 4: hex ---------- *)

let odd_hex = {j|{"case":9,"outcome":"panic","class":"expect","msg_hex":"abc","js_form":"closure","hint":"expect","signals":[]}|j}

let upper_hex = {j|{"case":9,"outcome":"panic","class":"expect","msg_hex":"6E","js_form":"closure","hint":"expect","signals":[]}|j}

let check_hex () =
  Alcotest.(check string)
    "an odd hex run" "err:wire:odd_hex:msg_hex" (show odd_hex);
  Alcotest.(check string)
    "an uppercase hex digit" "err:wire:bad_hex:msg_hex" (show upper_hex);
  Alcotest.(check string)
    "an empty hex payload" {j|Vs0:|r0:||j} (show seed2)

(* ---------- group 5: lossy, at three depths ---------- *)

let lossy_top = {j|{"case":1,"outcome":"value","value":{"t":"str","hex":"613c623e2b63"},"rendered_utf16_hex":"d800","lossy":true,"js_form":"direct","hint":"none","signals":[]}|j}

let lossy_one = {j|{"case":1,"outcome":"value","value":{"t":"str","utf16_hex":"d800","lossy":true},"rendered_hex":"","js_form":"direct","hint":"none","signals":[]}|j}

let lossy_two = {j|{"case":1,"outcome":"value","value":{"t":"tuple","vs":[{"t":"str","utf16_hex":"d800","lossy":true}]},"rendered_hex":"","js_form":"direct","hint":"none","signals":[]}|j}

let check_lossy () =
  Alcotest.(check string)
    "a lossy rendered channel" "lossy:rendered_utf16_hex" (show lossy_top);
  Alcotest.(check string)
    "a lossy string at depth one" "lossy:utf16_hex" (show lossy_one);
  Alcotest.(check string)
    "a lossy string at depth two" "lossy:utf16_hex" (show lossy_two)

(* ---------- group 6: the other outcomes ---------- *)

let js_error_line = {j|{"case":3,"outcome":"js_error","name_hex":"547970654572726f72","msg_hex":"6f6f7073","js_form":"direct","hint":"none","signals":[]}|j}

let driver_error_line = {j|{"case":0,"outcome":"driver_error","error":"spawn","detail_hex":"6f6f7073"}|j}

let no_terminate_line = {j|{"case":11,"outcome":"no_terminate","hint":"none"}|j}

let check_other_outcomes () =
  Alcotest.(check string)
    "a js_error line" "js_error:9:TypeError:4:oops" (show js_error_line);
  Alcotest.(check string)
    "a driver_error line" "driver_error:spawn" (show driver_error_line);
  Alcotest.(check string) "a skipped line" "skipped:no_js" (show seed11);
  Alcotest.(check string)
    "a no_terminate line" {j|T|r0:||j} (show no_terminate_line)

(* ---------- group 7: the argv ---------- *)

let check_argv () =
  Alcotest.(check (list string))
    "the node argv"
    [
      "node"; "--experimental-transform-types"; "--import";
      "/r/driver-js/loader.mjs"; "/r/driver-js/driver.mjs"; "--in";
      "/in.jsonl"; "--out"; "/out.jsonl"; "--clone"; "/r/../topcoat";
      "--timeout-ms"; "2000"; "--startup-timeout-ms"; "30000";
    ]
    (Js_leg.argv (Js_leg.default_config ~root:"/r") ~rust:"/in.jsonl"
       ~out:"/out.jsonl")

(* ---------- group 8: the row printer, one cell of each kind ---------- *)

let check_cells () =
  Alcotest.(check string)
    "an observation cell" {j|Vf1073217536:0;|r3:1.5||j} (show seed0);
  Alcotest.(check string) "a skipped cell" "skipped:no_js" (show seed11);
  Alcotest.(check string)
    "a js_error cell" "js_error:9:TypeError:4:oops" (show js_error_line);
  Alcotest.(check string)
    "a driver_error cell" "driver_error:spawn" (show driver_error_line);
  Alcotest.(check string) "a lossy cell" "lossy:utf16_hex" (show lossy_one)

let () =
  Alcotest.run "js_leg"
    [
      ( "m26",
        [
          Alcotest.test_case "the twelve J cells" `Quick check_seed_cells;
          Alcotest.test_case "the key sets" `Quick check_key_sets;
          Alcotest.test_case "the signals shape" `Quick check_signals;
          Alcotest.test_case "hex payloads" `Quick check_hex;
          Alcotest.test_case "lossy at three depths" `Quick check_lossy;
          Alcotest.test_case "the other outcomes" `Quick check_other_outcomes;
          Alcotest.test_case "the node argv" `Quick check_argv;
          Alcotest.test_case "the printed cells" `Quick check_cells;
        ] );
    ]
