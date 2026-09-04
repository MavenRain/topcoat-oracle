(* M24 rust-leg tests (DESIGN.md M24, spec section 8).  PURE ONLY: no
   process, no file and no directory.  Every case runs against string
   constants.

   The twelve seed lines are the expected table of m23_verdict.sh,
   copied byte for byte, with the two unstable payloads replaced by
   short fixed hex: js_hex is "6a73" (2 bytes, "js") and debug_hex is
   "64" (1 byte, "d").  The real payloads carry a fresh Signal uuid per
   run, so their bytes and their length are both unstable;  fixed hex
   makes every count in the expected table deterministic.

   The expected cells come from the HAND-DERIVED table of spec section
   7, not from this parser.  A cell is Obs.encode of the decoded
   observation.  Row 11 is "T|r0:|" here, because Obs.encode always
   prints the rendered channel and the signal channel;  the bare "T" of
   the printed row is Rust_leg.row's own rule and it is tested with
   Rust_leg. *)

(* ---------- the seed corpus ---------- *)

(* The twelve lines of the m23_verdict.sh expected table, byte for
   byte, with "JS" replaced by "6a73" and "DBG" by "64". *)
let seed0 = {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"rendered_hex":"312e35","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j}

let seed1 = {j|{"case":1,"outcome":"value","value":{"t":"str","hex":"613c623e2b63"},"rendered_hex":"61266c743b622667743b2b63","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j}

let seed2 = {j|{"case":2,"outcome":"value","value":{"t":"str","hex":""},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j}

let seed3 = {j|{"case":3,"outcome":"value","value":{"t":"some","v":{"t":"f64","hi":1073217536,"lo":0}},"rendered_hex":"312e35","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j}

let seed4 = {j|{"case":4,"outcome":"value","value":{"t":"none"},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j}

let seed5 = {j|{"case":5,"outcome":"panic","class":"unwrap","msg_hex":"63616c6c656420604f7074696f6e3a3a756e77726170282960206f6e206120604e6f6e65602076616c7565","js_hex":"6a73","js_form":"closure","hint":"none","signals":[]}|j}

let seed6 = {j|{"case":6,"outcome":"value","value":{"t":"f64","hi":1074003968,"lo":0},"rendered_hex":"322e35","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[{"id":3,"value":{"t":"f64","hi":1074003968,"lo":0},"debug_hex":"64"}]}|j}

let seed7 = {j|{"case":7,"outcome":"panic","class":"signal_write","msg_hex":"65787072657373696f6e7320696e2077686963682061207369676e616c206973207772697474656e20746f2063616e6e6f742062652072756e207365727665722d73696465","js_hex":"6a73","js_form":"closure","hint":"none","signals":[{"id":4,"value":{"t":"bool","v":true},"debug_hex":"64"}]}|j}

let seed8 = {j|{"case":8,"outcome":"panic","class":"expect_err","msg_hex":"6e6f70653a20226f6b22","js_hex":"6a73","js_form":"closure","hint":"expect_err","signals":[]}|j}

let seed9 = {j|{"case":9,"outcome":"panic","class":"expect","msg_hex":"626f6f6d","js_hex":"6a73","js_form":"closure","hint":"expect","signals":[]}|j}

let seed10 = {j|{"case":10,"outcome":"panic","class":"other","msg_hex":"6e6f70653a20226f6b22","js_hex":"6a73","js_form":"closure","hint":"both","signals":[]}|j}

let seed11 = {j|{"case":11,"outcome":"no_terminate","hint":"none"}|j}

let seed_lines =
  [ seed0; seed1; seed2; seed3; seed4; seed5; seed6; seed7; seed8; seed9; seed10; seed11 ]

(* ---------- show helpers, so every check is a string compare ---------- *)

let rec show_j (v : Json.jvalue) : string =
  match v with
  | Json.J_null -> "null"
  | Json.J_true -> "true"
  | Json.J_false -> "false"
  | Json.J_int n -> "i" ^ string_of_int n
  | Json.J_str s -> "s(" ^ s ^ ")"
  | Json.J_arr items -> "[" ^ String.concat "," (List.map show_j items) ^ "]"
  | Json.J_obj pairs ->
      "{"
      ^ String.concat ","
          (List.map (fun p -> fst p ^ ":" ^ show_j (snd p)) pairs)
      ^ "}"

let show_json (r : (Json.jvalue, Json.jerror) result) : string =
  Result.fold ~ok:show_j ~error:(fun e -> "err:" ^ Json.error_name e) r

let json_error_name (r : (Json.jvalue, Json.jerror) result) : string =
  Result.fold ~ok:show_j ~error:Json.error_name r

let json_error_offset (r : (Json.jvalue, Json.jerror) result) : int =
  Result.fold ~ok:(fun _ -> -1) ~error:Json.error_offset r

let string_of_jvalue (v : Json.jvalue) : string =
  match v with
  | Json.J_str s -> s
  | Json.J_null | Json.J_true | Json.J_false | Json.J_int _ | Json.J_arr _
  | Json.J_obj _ ->
      "NOT A STRING"

let werror_key (e : Wire.werror) : string =
  match e with
  | Wire.W_json _ -> ""
  | Wire.W_not_object -> ""
  | Wire.W_missing_key k -> k
  | Wire.W_extra_key k -> k
  | Wire.W_bad_shape k -> k
  | Wire.W_unknown_outcome s -> s
  | Wire.W_unknown_tag s -> s
  | Wire.W_unknown_class s -> s
  | Wire.W_unknown_hint s -> s
  | Wire.W_unknown_js_form s -> s
  | Wire.W_range (k, _n) -> k
  | Wire.W_odd_hex k -> k
  | Wire.W_bad_hex k -> k

let show_werror (e : Wire.werror) : string =
  Wire.werror_name e ^ " " ^ werror_key e

(* The cell of the printed row: Obs.encode of the decoded
   observation. *)
let show_cell (line : string) : string =
  Result.fold
    ~ok:(fun d -> Obs.encode d.Wire.d_obs)
    ~error:(fun e -> "err:" ^ show_werror e)
    (Wire.decode_line line)

(* The four trailing columns of the printed row. *)
let show_tail (line : string) : string =
  Result.fold
    ~ok:(fun d ->
      Wire.js_form_wire d.Wire.d_js_form
      ^ " "
      ^ Wire.hint_wire d.Wire.d_hint
      ^ " "
      ^ (match d.Wire.d_js_consistent with true -> "1" | false -> "0")
      ^ " "
      ^ string_of_int (String.length d.Wire.d_js))
    ~error:(fun e -> "err:" ^ show_werror e)
    (Wire.decode_line line)

let show_case (line : string) : string =
  Result.fold
    ~ok:(fun d -> string_of_int d.Wire.d_case)
    ~error:(fun e -> "err:" ^ show_werror e)
    (Wire.decode_line line)

let show_debug (line : string) : string =
  Result.fold
    ~ok:(fun d ->
      String.concat ","
        (List.map
           (fun p -> string_of_int (fst p) ^ "=" ^ snd p)
           d.Wire.d_debug))
    ~error:(fun e -> "err:" ^ show_werror e)
    (Wire.decode_line line)

let show_decode_error (line : string) : string =
  Result.fold
    ~ok:(fun d -> "ok:" ^ string_of_int d.Wire.d_case)
    ~error:show_werror
    (Wire.decode_line line)

let show_next (line : string) : string =
  Result.fold
    ~ok:string_of_int
    ~error:(fun e -> "err:" ^ Wire.werror_name e)
    (Wire.next_from line)

(* A repeated byte, built without a loop keyword. *)
let rec repeat (n : int) (s : string) (acc : string) : string =
  match () with () when n <= 0 -> acc | () -> repeat (n - 1) s (acc ^ s)

(* ---------- 1.  json positives ---------- *)

let json_positive_cases =
  [
    ("{}", "{}");
    ("[]", "[]");
    ({j|{"a":1}|j}, "{a:i1}");
    ("[1,2,3]", "[i1,i2,i3]");
    ({j|{"a":{"b":[true,false,null]}}|j}, "{a:{b:[true,false,null]}}");
    ("0", "i0");
    ("999999999999999999", "i999999999999999999");
    ("  [ 1 , 2 ]  ", "[i1,i2]");
  ]

let check_json_positives () =
  Alcotest.(check (list string))
    "json positives"
    (List.map snd json_positive_cases)
    (List.map (fun p -> show_json (Json.parse (fst p))) json_positive_cases);
  (* The eight simple escapes, decoded to their bytes. *)
  Alcotest.(check string)
    "the eight simple escapes" "\"\\/\b\012\n\r\t"
    (Result.fold ~ok:string_of_jvalue
       ~error:(fun e -> "err:" ^ Json.error_name e)
       (Json.parse {j|"\"\\\/\b\f\n\r\t"|j}));
  (* One full seed line parses, and the nine keys arrive in wire
     order. *)
  Alcotest.(check (list string))
    "seed line 0 keys"
    [
      "case"; "outcome"; "value"; "rendered_hex"; "js_consistent"; "js_hex";
      "js_form"; "hint"; "signals";
    ]
    (Result.fold
       ~ok:(fun v ->
         match v with
         | Json.J_obj pairs -> Json.obj_keys pairs
         | Json.J_null | Json.J_true | Json.J_false | Json.J_int _
         | Json.J_str _ | Json.J_arr _ ->
             [ "NOT AN OBJECT" ])
       ~error:(fun e -> [ "err:" ^ Json.error_name e ])
       (Json.parse seed0))

(* ---------- 2.  json negatives ---------- *)

let json_negative_cases =
  [
    ("{} x", "trailing");
    ({j|{"a":1,"a":2}|j}, "dup_key");
    ({j|"\q"|j}, "bad_escape");
    (* The spec's table cell for this row reads "A": the \u escape it
       names was resolved before the spec was written.  The input the
       row means is the escape itself, which the reader rejects. *)
    ({j|"\u0041"|j}, "unicode_escape");
    ("-1", "minus");
    ("1234567890123456789", "too_many_digits");
    ({j|"abc|j}, "unterminated");
    ("1.5", "fraction");
    ("1e3", "exponent");
    ("01", "leading_zero");
    ("nul", "unexpected");
    (repeat 65 "[" "", "depth");
  ]

let check_json_negatives () =
  Alcotest.(check (list string))
    "json negatives"
    (List.map snd json_negative_cases)
    (List.map
       (fun p -> json_error_name (Json.parse (fst p)))
       json_negative_cases);
  (* The offset is part of the contract, not decoration: the trailing
     byte of "{} x" is at index 3. *)
  Alcotest.(check int)
    "trailing offset" 3
    (json_error_offset (Json.parse "{} x"));
  Alcotest.(check int)
    "unterminated offset is the opening quote" 0
    (json_error_offset (Json.parse {j|"abc|j}))

(* ---------- 3.  wire on all twelve seed lines ---------- *)

(* Spec section 7.5, cell column.  Hand-derived from the wire, never
   regenerated from this parser. *)
let expected_cells =
  [
    {cell|Vf1073217536:0;|r3:1.5||cell};
    {cell|Vs6:a<b>+c|r12:a&lt;b&gt;+c||cell};
    {cell|Vs0:|r0:||cell};
    {cell|VSf1073217536:0;|r3:1.5||cell};
    {cell|Vn|r0:||cell};
    {cell|Punwrap:43:called `Option::unwrap()` on a `None` value|r0:||cell};
    {cell|Vf1074003968:0;|r3:2.5|g3:f1074003968:0;|cell};
    {cell|Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g4:b1|cell};
    {cell|Pexpect_err:10:nope: "ok"|r0:||cell};
    {cell|Pexpect:4:boom|r0:||cell};
    {cell|Pother:10:nope: "ok"|r0:||cell};
    (* Obs.encode prints the rendered and signal channels on every
       outcome.  Rust_leg.row prints the bare "T" instead, per R9 and
       ruling Q3, and that is tested beside Rust_leg. *)
    {cell|T|r0:||cell};
  ]

(* Spec section 7.4, with the js byte count of the fixed hex: 2 bytes
   on every line that carries js_hex, 0 on the no-terminate line. *)
let expected_tails =
  [
    "direct none 1 2";
    "direct none 1 2";
    "direct none 1 2";
    "direct none 1 2";
    "direct none 1 2";
    "closure none 1 2";
    "direct none 1 2";
    "closure none 1 2";
    "closure expect_err 1 2";
    "closure expect 1 2";
    "closure both 1 2";
    "absent none 1 0";
  ]

let check_seed_cells () =
  Alcotest.(check (list string))
    "seed cells against the hand table" expected_cells
    (List.map show_cell seed_lines)

let check_seed_tails () =
  Alcotest.(check (list string))
    "seed trailing columns" expected_tails
    (List.map show_tail seed_lines);
  Alcotest.(check (list string))
    "seed case indices"
    [ "0"; "1"; "2"; "3"; "4"; "5"; "6"; "7"; "8"; "9"; "10"; "11" ]
    (List.map show_case seed_lines);
  (* The Debug text rides beside the observation, in wire order, and
     never inside it. *)
  Alcotest.(check (list string))
    "seed debug channel"
    [ ""; ""; ""; ""; ""; ""; "3=d"; "4=d"; ""; ""; ""; "" ]
    (List.map show_debug seed_lines)

(* ---------- 3b.  the six Value tags the seed vector never carries ---------- *)

let tag_cases =
  [
    ( {j|{"case":0,"outcome":"value","value":{"t":"unit"},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      {cell|Vu|r0:||cell} );
    ( {j|{"case":0,"outcome":"value","value":{"t":"closure"},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      {cell|Vc|r0:||cell} );
    ( {j|{"case":0,"outcome":"value","value":{"t":"bool","v":false},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      {cell|Vb0|r0:||cell} );
    ( {j|{"case":0,"outcome":"value","value":{"t":"tuple","vs":[{"t":"unit"},{"t":"bool","v":false}]},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      {cell|Vt2:ub0|r0:||cell} );
    ( {j|{"case":0,"outcome":"value","value":{"t":"ok","v":{"t":"unit"}},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      {cell|VOu|r0:||cell} );
    ( {j|{"case":0,"outcome":"value","value":{"t":"err","v":{"t":"unit"}},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      {cell|VEu|r0:||cell} );
  ]

let check_tag_coverage () =
  Alcotest.(check (list string))
    "every Value tag decodes to its hand-derived cell"
    (List.map snd tag_cases)
    (List.map (fun p -> show_cell (fst p)) tag_cases)

(* ---------- 4.  wire negatives ---------- *)

let wire_negative_cases =
  [
    ( {j|{"case":0,"outcome":"value","value":{"t":"weird"},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      "unknown_tag weird" );
    ( {j|{"case":0,"outcome":"value","value":{"t":"none"},"js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      "missing_key rendered_hex" );
    ( {j|{"case":0,"outcome":"value","value":{"t":"none"},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[],"extra":1}|j},
      "extra_key extra" );
    ( {j|{"case":9,"outcome":"panic","class":"expect","msg_hex":"abc","js_hex":"6a73","js_form":"closure","hint":"expect","signals":[]}|j},
      "odd_hex msg_hex" );
    ( {j|{"case":9,"outcome":"panic","class":"expect","msg_hex":"AB","js_hex":"6a73","js_form":"closure","hint":"expect","signals":[]}|j},
      "bad_hex msg_hex" );
    ( {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":4294967296,"lo":0},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      "range hi" );
    ( {j|{"case":9,"outcome":"panic","class":"unwrap_or","msg_hex":"626f6f6d","js_hex":"6a73","js_form":"closure","hint":"expect","signals":[]}|j},
      "unknown_class unwrap_or" );
    ( {j|{"case":9,"outcome":"panic","class":"expect","msg_hex":"626f6f6d","js_hex":"6a73","js_form":"closure","hint":"maybe","signals":[]}|j},
      "unknown_hint maybe" );
    ( {j|{"case":9,"outcome":"panic","class":"expect","msg_hex":"626f6f6d","js_hex":"6a73","js_form":"inline","hint":"expect","signals":[]}|j},
      "unknown_js_form inline" );
    ( {j|{"case":0,"outcome":"crash","hint":"none"}|j}, "unknown_outcome crash" );
    ({j|[1,2]|j}, "not_object ");
    ({j|{"case":0,|j}, "json ");
    ( {j|{"case":"0","outcome":"no_terminate","hint":"none"}|j},
      "bad_shape case" );
    ( {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      "missing_key lo" );
    ( {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":0,"lo":4294967296},"rendered_hex":"","js_consistent":true,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j},
      "range lo" );
  ]

let check_wire_negatives () =
  Alcotest.(check (list string))
    "wire negatives"
    (List.map snd wire_negative_cases)
    (List.map
       (fun p -> show_decode_error (fst p))
       wire_negative_cases)

(* ---------- 5.  js_consistent false ---------- *)

let inconsistent_line =
  {j|{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"rendered_hex":"312e35","js_consistent":false,"js_hex":"6a73","js_form":"direct","hint":"none","signals":[]}|j}

let check_js_consistent_false () =
  Alcotest.(check bool)
    "js_consistent false decodes as false" false
    (Result.fold
       ~ok:(fun d -> d.Wire.d_js_consistent)
       ~error:(fun _ -> true)
       (Wire.decode_line inconsistent_line));
  Alcotest.(check string)
    "the js_consistent column prints 0" "direct none 0 2"
    (show_tail inconsistent_line)

(* ---------- 6.  the byte table ---------- *)

let check_byte_table () =
  Alcotest.(check int) "all_bytes length" 256 (String.length Wire.all_bytes);
  Alcotest.(check (option string))
    "byte 0x61 is a" (Some "a")
    (Prelude.byte_at Wire.all_bytes 0x61);
  Alcotest.(check (option string))
    "byte 0 is NUL" (Some "\000")
    (Prelude.byte_at Wire.all_bytes 0);
  Alcotest.(check (option string))
    "byte 255 is the last one" (Some "\255")
    (Prelude.byte_at Wire.all_bytes 255);
  Alcotest.(check (option string))
    "index 256 is out of range" None
    (Prelude.byte_at Wire.all_bytes 256);
  Alcotest.(check (option string))
    "a negative index is out of range" None
    (Prelude.byte_at Wire.all_bytes (-1))

(* ---------- 7.  hex payloads ---------- *)

let hex_cases =
  [
    ("", "");
    ("612e35", "a.5");
    ("626f6f6d", "boom");
    ("00ff", "\000\255");
  ]

let check_hex () =
  Alcotest.(check (list string))
    "hex payloads decode"
    (List.map snd hex_cases)
    (List.map
       (fun p ->
         Result.fold ~ok:(fun s -> s)
           ~error:(fun e -> "err:" ^ show_werror e)
           (Wire.hex_bytes "hex" (fst p)))
       hex_cases);
  Alcotest.(check string)
    "an odd payload is named" "odd_hex k"
    (Result.fold ~ok:(fun s -> s) ~error:show_werror (Wire.hex_bytes "k" "abc"));
  Alcotest.(check string)
    "an uppercase digit is named" "bad_hex k"
    (Result.fold ~ok:(fun s -> s) ~error:show_werror (Wire.hex_bytes "k" "AB"))

(* ---------- 8.  the resume index ---------- *)

let check_resume_index () =
  Alcotest.(check string) "next_from the last seed line" "12" (show_next seed11);
  Alcotest.(check string) "next_from the first seed line" "1" (show_next seed0);
  Alcotest.(check string)
    "next_from an empty line is a named error" "err:json" (show_next "")

(* ---------- 9.  the hint round trip ---------- *)

let driver_hints =
  [ Driver.H_none; Driver.H_expect; Driver.H_expect_err; Driver.H_both ]

let check_hint_round_trip () =
  Alcotest.(check (list string))
    "hint round trip"
    (List.map Driver.hint_wire driver_hints)
    (List.map
       (fun h ->
         Result.fold ~ok:Wire.hint_wire
           ~error:(fun e -> "err:" ^ Wire.werror_name e)
           (Wire.parse_hint (Driver.hint_wire h)))
       driver_hints);
  Alcotest.(check (list string))
    "js_form round trip"
    [ "direct"; "closure"; "absent" ]
    (List.map
       (fun w ->
         Result.fold ~ok:Wire.js_form_wire
           ~error:(fun e -> "err:" ^ Wire.werror_name e)
           (Wire.parse_js_form w))
       [ "direct"; "closure"; "absent" ]);
  Alcotest.(check (list string))
    "panic class round trip"
    [ "unwrap"; "expect"; "unwrap_err"; "expect_err"; "signal_write"; "other" ]
    (List.map
       (fun w ->
         Result.fold ~ok:Obs.encode_panic_class
           ~error:(fun e -> "err:" ^ Wire.werror_name e)
           (Wire.parse_class w))
       [ "unwrap"; "expect"; "unwrap_err"; "expect_err"; "signal_write"; "other" ])

(* ---------- 10.  the printed row (spec 7.5 with the fixed counts) ---------- *)

(* Spec section 7.5, byte for byte, with the masked js byte count
   replaced by the count of the fixed hex: 2 on every line that carries
   js_hex, 0 on the no-terminate line.  Hand-derived, never regenerated
   from this parser. *)
let expected_rows =
  [
    {row|0 Vf1073217536:0;|r3:1.5| direct none 1 2|row};
    {row|1 Vs6:a<b>+c|r12:a&lt;b&gt;+c| direct none 1 2|row};
    {row|2 Vs0:|r0:| direct none 1 2|row};
    {row|3 VSf1073217536:0;|r3:1.5| direct none 1 2|row};
    {row|4 Vn|r0:| direct none 1 2|row};
    {row|5 Punwrap:43:called `Option::unwrap()` on a `None` value|r0:| closure none 1 2|row};
    {row|6 Vf1074003968:0;|r3:2.5|g3:f1074003968:0; direct none 1 2|row};
    {row|7 Psignal_write:69:expressions in which a signal is written to cannot be run server-side|r0:|g4:b1 closure none 1 2|row};
    {row|8 Pexpect_err:10:nope: "ok"|r0:| closure expect_err 1 2|row};
    {row|9 Pexpect:4:boom|r0:| closure expect 1 2|row};
    {row|10 Pother:10:nope: "ok"|r0:| closure both 1 2|row};
    (* Ruling Q3: the no-terminate row prints the bare letter T, so the
       verdict can read $2 and find it on that row alone. *)
    {row|11 T absent none 1 0|row};
  ]

let show_row (line : string) : string =
  Result.fold ~ok:Rust_leg.row
    ~error:(fun e -> "err:" ^ show_werror e)
    (Wire.decode_line line)

let decoded_seeds : Wire.decoded list =
  List.filter_map (fun l -> Result.to_option (Wire.decode_line l)) seed_lines

let check_rows () =
  Alcotest.(check int) "every seed line decodes" 12 (List.length decoded_seeds);
  Alcotest.(check (list string))
    "printed rows against the hand-derived table" expected_rows
    (List.map show_row seed_lines);
  (* The js_consistent column of the printed row follows the wire. *)
  Alcotest.(check string)
    "an inconsistent line prints 0 in the fifth field"
    "0 Vf1073217536:0;|r3:1.5| direct none 0 2"
    (show_row inconsistent_line)

(* ---------- 11.  the resume index over a report ---------- *)

let show_resume (text : string) : string =
  Result.fold ~ok:string_of_int ~error:Rust_leg.error_text
    (Rust_leg.resume_index text)

let check_rust_leg_resume () =
  Alcotest.(check string)
    "the index over a three-line report" "12"
    (show_resume (seed9 ^ "\n" ^ seed10 ^ "\n" ^ seed11 ^ "\n"));
  Alcotest.(check string)
    "a report with no trailing line feed still resumes" "11"
    (show_resume (seed9 ^ "\n" ^ seed10));
  Alcotest.(check string)
    "an empty report is a named decode error"
    "line 0 does not decode: json" (show_resume "");
  Alcotest.(check string)
    "the error names the last non-empty line, not the line count"
    "line 1 does not decode: json" (show_resume "bad\n\n\n");
  Alcotest.(check (list string))
    "the line split drops the trailing empty piece" [ "a"; "b" ]
    (Rust_leg.split_lines "a\nb\n");
  Alcotest.(check (list string))
    "a text with no trailing line feed keeps its last piece" [ "a"; "b" ]
    (Rust_leg.split_lines "a\nb")

(* ---------- 12.  the cargo argv ---------- *)

(* The target dir of m23_gate.sh, so the list below is that script's
   drawn-batch argv byte for byte. *)
let m23_config =
  {
    (Rust_leg.default_config ~root:"") with
    Rust_leg.target_dir = "research/probes-rs/exprmac/target";
  }

let m23_argv =
  [
    "cargo"; "+nightly-2026-06-22"; "run"; "--quiet"; "--manifest-path";
    "_emit/m23/Cargo.toml"; "--target-dir";
    "research/probes-rs/exprmac/target"; "-j"; "2"; "--"; "--timeout-ms";
    "2000";
  ]

let check_cargo_argv () =
  Alcotest.(check (list string))
    "the drawn-batch argv of m23_gate.sh" m23_argv
    (Rust_leg.cargo_argv m23_config ~manifest:"_emit/m23/Cargo.toml" ~from:None);
  Alcotest.(check (list string))
    "a resume appends --from"
    (List.append m23_argv [ "--from"; "7" ])
    (Rust_leg.cargo_argv m23_config ~manifest:"_emit/m23/Cargo.toml"
       ~from:(Some 7))

(* ---------- 13.  renderability ---------- *)

let show_rendered (rs : Rust_leg.rendered_state) : string =
  match rs with
  | Rust_leg.Rs_absent -> "absent"
  | Rust_leg.Rs_empty -> "empty"
  | Rust_leg.Rs_text t -> "text:" ^ t

let rendered_at (i : int) : string =
  Option.fold ~none:"no sample"
    ~some:(fun s ->
      Option.fold ~none:"no line"
        ~some:(fun d -> show_rendered (Rust_leg.rendered_of s d))
        (Prelude.nth_opt decoded_seeds i))
    (Prelude.nth_opt Driver.seed_cases i)

(* Spec 4.7: case 0 renders 1.5, cases 2 and 4 render empty and are
   still renderable targets, case 7 has an unrenderable target and case
   11 never reached a render channel at all. *)
let check_renderability () =
  Alcotest.(check int)
    "every seed line decodes, so the positional pairing holds"
    (List.length seed_lines) (List.length decoded_seeds);
  Alcotest.(check (list string))
    "the five renderability cases"
    [ "text:1.5"; "empty"; "empty"; "absent"; "absent" ]
    (List.map rendered_at [ 0; 2; 4; 7; 11 ])

(* ---------- 14.  the kept-sample pairing and the summary ---------- *)

let seed_report (lines : Wire.decoded list) : Rust_leg.report =
  {
    Rust_leg.p_lines = lines;
    p_kept = 12;
    p_dropped = [];
    p_resumes = 1;
    p_exits = [ 3; 0 ];
    p_exit = 0;
    p_inconsistent = [];
  }

let show_pair (rep : Rust_leg.report) : string =
  Result.fold
    ~ok:(fun ps ->
      String.concat ","
        (List.map (fun p -> string_of_int (snd p).Wire.d_case) ps))
    ~error:Rust_leg.error_text
    (Rust_leg.pair Driver.seed_cases rep)

let check_pairing () =
  Alcotest.(check int)
    "every seed sample is kept" 12
    (List.length (Rust_leg.kept_samples Driver.seed_cases));
  Alcotest.(check string)
    "the pairing is by position" "0,1,2,3,4,5,6,7,8,9,10,11"
    (show_pair (seed_report decoded_seeds));
  Alcotest.(check string)
    "a short report is a named count error"
    "the run kept 12 samples and wrote 11 lines"
    (show_pair (seed_report (List.filteri (fun i _ -> i < 11) decoded_seeds)))

(* Ruling Q7: this exact line is what m24_verdict.sh asserts whole. *)
let check_summary () =
  Alcotest.(check string)
    "the run summary line"
    "m24 seeds: kept 12 lines 12 resumes 1 exits 3,0 inconsistent 0"
    (Rust_leg.summary (seed_report decoded_seeds));
  Alcotest.(check string)
    "an inconsistent run names its cases"
    "m24 seeds: js_consistent false on cases 3,7"
    (Rust_leg.inconsistent_text
       { (seed_report decoded_seeds) with Rust_leg.p_inconsistent = [ 3; 7 ] })

let () =
  Alcotest.run "rust_leg"
    [
      ( "m24",
        [
          Alcotest.test_case "json positives" `Quick check_json_positives;
          Alcotest.test_case "json negatives" `Quick check_json_negatives;
          Alcotest.test_case "seed cells" `Quick check_seed_cells;
          Alcotest.test_case "seed trailing columns" `Quick check_seed_tails;
          Alcotest.test_case "wire negatives" `Quick check_wire_negatives;
          Alcotest.test_case "value tag coverage" `Quick check_tag_coverage;
          Alcotest.test_case "js_consistent false" `Quick
            check_js_consistent_false;
          Alcotest.test_case "the byte table" `Quick check_byte_table;
          Alcotest.test_case "hex payloads" `Quick check_hex;
          Alcotest.test_case "the resume index" `Quick check_resume_index;
          Alcotest.test_case "hint round trip" `Quick check_hint_round_trip;
          Alcotest.test_case "printed rows" `Quick check_rows;
          Alcotest.test_case "the resume index over a report" `Quick
            check_rust_leg_resume;
          Alcotest.test_case "the cargo argv" `Quick check_cargo_argv;
          Alcotest.test_case "renderability" `Quick check_renderability;
          Alcotest.test_case "the kept-sample pairing" `Quick check_pairing;
          Alcotest.test_case "the run summary" `Quick check_summary;
        ] );
    ]
