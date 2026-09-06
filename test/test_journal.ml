(** test_journal: the M31 journal codec.  Seven tests, no framework, one line
    per test and a non zero exit on any red, after test/test_repro.ml. *)

(** [say name ok] prints one result line and answers [ok].  The line is the
    only report a reader gets for a single test, so it carries the name. *)
let say name ok =
  print_string ((if ok then "ok " else "FAIL ") ^ name ^ "\n");
  ok

(** [a_line body] is a sample line with [body] in its body field. *)
let a_line (body : string) : Journal.line =
  {
    Journal.jl_i = 0;
    Journal.jl_mode = "read_only";
    Journal.jl_size = 3;
    Journal.jl_verdict = "agree";
    Journal.jl_r = "o|r1:0|";
    Journal.jl_j = "o|r1:0|";
    Journal.jl_f = "o|r1:0|";
    Journal.jl_env = [ "let a = 1;"; "let b = \"q\\\"q\";" ];
    Journal.jl_body = body;
  }

(** [round_trip body] decodes the encoding of [a_line body] and answers
    whether the body survived. *)
let round_trip (body : string) : bool =
  Result.fold ~error:(fun _ -> false)
    ~ok:(fun (l : Journal.line) -> String.equal l.Journal.jl_body body)
    (Journal.decode_line 2 (Journal.encode_line (a_line body)))

(** [byte_table ()] is the 256 bytes 0 to 255 in order, as one string.  It is
    a function of unit and not a constant, after core/json.ml:130-131.  The
    table exists because the house rules of the build brief forbid every
    exception source, and [Char.chr] raises on an argument outside 0 to 255,
    so the byte is READ from here through the total accessor instead. *)
let byte_table () =
  Prelude.concat
    [
      "\000\001\002\003\004\005\006\007\008\009\010\011\012\013\014\015\016\017\018\019\020\021\022\023\024\025\026\027\028\029\030\031";
      "\032\033\034\035\036\037\038\039\040\041\042\043\044\045\046\047\048\049\050\051\052\053\054\055\056\057\058\059\060\061\062\063";
      "\064\065\066\067\068\069\070\071\072\073\074\075\076\077\078\079\080\081\082\083\084\085\086\087\088\089\090\091\092\093\094\095";
      "\096\097\098\099\100\101\102\103\104\105\106\107\108\109\110\111\112\113\114\115\116\117\118\119\120\121\122\123\124\125\126\127";
      "\128\129\130\131\132\133\134\135\136\137\138\139\140\141\142\143\144\145\146\147\148\149\150\151\152\153\154\155\156\157\158\159";
      "\160\161\162\163\164\165\166\167\168\169\170\171\172\173\174\175\176\177\178\179\180\181\182\183\184\185\186\187\188\189\190\191";
      "\192\193\194\195\196\197\198\199\200\201\202\203\204\205\206\207\208\209\210\211\212\213\214\215\216\217\218\219\220\221\222\223";
      "\224\225\226\227\228\229\230\231\232\233\234\235\236\237\238\239\240\241\242\243\244\245\246\247\248\249\250\251\252\253\254\255";
    ]

(** [byte_string k] is the one byte string of the byte [k], for 0 <= k <= 255,
    and "" outside that range.  [Prelude.byte_at] is total, so no argument
    can fail here. *)
let byte_string (k : int) : string =
  Option.fold ~none:"" ~some:(fun b -> b) (Prelude.byte_at (byte_table ()) k)

(** [all_bytes_round_trip ()] answers whether every one of the 256 bytes
    survives encode then decode, inside a body.  It is a recursion and not a
    loop. *)
let all_bytes_round_trip () : bool =
  let rec go (k : int) : bool =
    match () with
    | () when k > 255 -> true
    | () when round_trip (byte_string k) -> go (k + 1)
    | () -> false
  in
  go 0

(** [a_header ()] is the header of the gate's own straight run: the M31 seed,
    the batch of 100, no plant and the pinned clone sha. *)
let a_header () : Journal.header =
  {
    Journal.jh_seed = 5059377;
    Journal.jh_batch = 100;
    Journal.jh_plant = "none";
    Journal.jh_topcoat = "51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a";
  }

(** [verdict_line i v] is [a_line "a"] at index [i] with the verdict [v], so
    a test states only the two fields it is about. *)
let verdict_line (i : int) (v : string) : Journal.line =
  { (a_line "a") with Journal.jl_i = i; Journal.jl_verdict = v }

(** The summary of test 6, derived by hand.  The per text lines are sorted by
    section 3.7: "batch_fail" heads before "diverge" on the byte b against d,
    and "diverge:rendered" heads before "diverge:value" on the byte r against
    v.  A line whose verdict is "agree" is counted in the bucket line only. *)
let summary_want =
  "m31 seed 0x4d3331 samples 4 batch 100 plant none topcoat \
   51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a\n\
   m31 agree 1 known 0 diverge 2 leg_fail 0 dropped 0 no_line 0 batch_fail 1 \
   other 0\n\
   m31 batch_fail:the js driver exited 1 1\n\
   m31 diverge:rendered:odd:ref 1\n\
   m31 diverge:value:odd:js 1\n\
   m31 journal j.jsonl lines 4\n"

(** 1  a body of the four bytes that must be escaped, plus a high byte. *)
let t_escape () =
  say "escape round trip"
    (round_trip "q\"q\\q\nq\tq\255q")

(** 2  the header round trips through its own decoder. *)
let t_header () =
  say "header round trip"
    (Result.fold ~error:(fun _ -> false)
       ~ok:(fun (h : Journal.header) ->
         Int.equal h.Journal.jh_seed 5059377
         && String.equal h.Journal.jh_plant "none")
       (Journal.decode_header 1 (Journal.encode_header (a_header ()))))

(** 3  a gap in the indices is refused. *)
let t_gap () =
  say "gap refused"
    (Result.fold ~ok:(fun _ -> false)
       ~error:(fun _ -> true)
       (Journal.decode_journal
          [
            Journal.encode_header (a_header ());
            Journal.encode_line (verdict_line 0 "agree");
            Journal.encode_line (verdict_line 2 "agree");
          ]))

(** 4  a repeated index is refused. *)
let t_repeat () =
  say "repeat refused"
    (Result.fold ~ok:(fun _ -> false)
       ~error:(fun _ -> true)
       (Journal.decode_journal
          [
            Journal.encode_header (a_header ());
            Journal.encode_line (verdict_line 0 "agree");
            Journal.encode_line (verdict_line 0 "agree");
          ]))

(** 5  a first line that is not a header is refused. *)
let t_header_first () =
  say "header first"
    (Result.fold ~ok:(fun _ -> false)
       ~error:(fun _ -> true)
       (Journal.decode_journal
          [ Journal.encode_line (verdict_line 0 "agree") ]))

(** 6  the summary of a hand built journal is hand derived. *)
let t_summary () =
  say "summary text"
    (String.equal
       (Journal.summary_text ~seed_hex:"0x4d3331" ~path:"j.jsonl"
          (a_header ())
          [
            verdict_line 0 "agree";
            verdict_line 1 "diverge:value:odd:js";
            verdict_line 2 "diverge:rendered:odd:ref";
            verdict_line 3 "batch_fail:the js driver exited 1";
          ])
       summary_want)

(** 7  every byte of 0 .. 255 survives the codec. *)
let t_all_bytes () = say "all 256 bytes" (all_bytes_round_trip ())

(** The entry point.  It runs the seven tests, prints the count line the gate
    reads and exits non zero on any failure, after test/test_repro.ml:107-121.
    There is no counter and no ref: the answers ARE the list. *)
let () =
  let all =
    [
      t_escape (); t_header (); t_gap (); t_repeat (); t_header_first ();
      t_summary (); t_all_bytes ();
    ]
  in
  print_string
    ("test_journal: "
    ^ string_of_int (Prelude.fold (fun n b -> if b then n + 1 else n) 0 all)
    ^ "/" ^ string_of_int (Prelude.len all) ^ "\n");
  exit (if Prelude.fold (fun a b -> a && b) true all then 0 else 1)
