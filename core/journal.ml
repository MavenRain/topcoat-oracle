(** Journal is the M31 run journal AS DATA: the header record, the sample
    record, a total JSON escape, an encoder and a decoder, the shape check of
    a whole journal and the tally the summary prints.  Nothing here opens a
    channel, reads a clock or spawns a process, so M34 and M35 read a journal
    with this module and no process at all (ruling R1). *)

(** The first line of a journal.  [jh_seed] is the seed as an INT: the file
    carries the number and the summary prints it in hex, so a reader of the
    file needs no hex reader.  [jh_plant] is [Plant.name] of the run and is
    "none" when there is no plant.  [jh_topcoat] is the 40 lowercase hex sha
    of the clone the run adjudicated against. *)
type header = {
  jh_seed : int;
  jh_batch : int;
  jh_plant : string;
  jh_topcoat : string;
}

(** One sample of the run.  [jl_i] is the index in the draw of the header's
    seed;  the pair (seed, index) is the sample identity M35 cites.
    [jl_verdict] is the BARE [Differ.verdict_text], with no mode prefix,
    because [jl_mode] is its own field.  [jl_r], [jl_j] and [jl_f] are the
    three M27 cells and are "" when the run produced none.  [jl_env] is one
    Rust let line per binding and [jl_body] is the body expression, both as
    shell/walk.ml prints them. *)
type line = {
  jl_i : int;
  jl_mode : string;
  jl_size : int;
  jl_verdict : string;
  jl_r : string;
  jl_j : string;
  jl_f : string;
  jl_env : string list;
  jl_body : string;
}

(** Every way a journal fails to decode.  Each one names the 1 based number of
    the offending line, so a red gate names the line and not just the file. *)
type error =
  | E_empty
  | E_parse of int * string
  | E_not_object of int
  | E_missing of int * string
  | E_type of int * string
  | E_version of int * int
  | E_index of int * int * int

(** [error_text e] is the one line a caller prints for a decode failure. *)
let error_text (e : error) : string =
  match e with
  | E_empty -> "the journal holds no line"
  | E_parse (n, m) -> "line " ^ Prelude.nat_to_string n ^ " is not JSON: " ^ m
  | E_not_object n ->
      "line " ^ Prelude.nat_to_string n ^ " is not a JSON object"
  | E_missing (n, k) ->
      "line " ^ Prelude.nat_to_string n ^ " has no " ^ k ^ " field"
  | E_type (n, k) ->
      "line " ^ Prelude.nat_to_string n ^ " has the wrong type in its " ^ k
      ^ " field"
  | E_version (n, v) ->
      "line " ^ Prelude.nat_to_string n ^ " is not an m31 header: its m31 "
      ^ "field is " ^ Prelude.nat_to_string v
  | E_index (n, want, got) ->
      "line " ^ Prelude.nat_to_string n ^ " carries index "
      ^ Prelude.nat_to_string got ^ " where " ^ Prelude.nat_to_string want
      ^ " was expected"

(** [escape_pairs ()] maps the seven bytes that must NOT stand raw in a
    journal line to the escape core/json.ml:186-190 decodes back to them.  It
    is a function of unit and not a top level constant: zxlint trap 2 turns a
    constant read from a helper into an undeclared identifier in the emitted
    Zig, which is why core/json.ml:130-131 spells its own caps this way. *)
let escape_pairs () =
  [
    ("\"", "\\\"");
    ("\\", "\\\\");
    ("\008", "\\b");
    ("\012", "\\f");
    ("\010", "\\n");
    ("\013", "\\r");
    ("\009", "\\t");
  ]

(** [escape_byte b] is the escape of the ONE BYTE STRING [b].  The seven bytes
    of the table become their two byte escape.  EVERY other byte of 0 to 255
    is copied verbatim, which is exactly what core/json.ml:177-183 accepts: it
    copies any byte that is not a quote and not a backslash and makes no byte
    value test at all, and core/json.ml:20-21 documents that laxness for a
    control byte.  No escape of the form backslash u is ever emitted, because
    core/json.ml:41 and :195 REJECT one as [E_unicode_escape]. *)
let escape_byte (b : string) : string =
  Option.fold ~none:b
    ~some:(fun e -> e)
    (Prelude.assoc_opt String.equal b (escape_pairs ()))

(** [escape s] escapes every byte of [s].  [Prelude.byte_at] answers [None]
    past the end, which ends the walk, so there is no length test, no
    [String.sub] and no index arithmetic outside the total accessor. *)
let escape (s : string) : string =
  let rec go (k : int) (acc : string) : string =
    Option.fold ~none:acc
      ~some:(fun b -> go (k + 1) (acc ^ escape_byte b))
      (Prelude.byte_at s k)
  in
  go 0 ""

(** [jstring s] is [s] as a JSON string, quotes included. *)
let jstring (s : string) : string = "\"" ^ escape s ^ "\""

(** [jint n] is [n] as a JSON number.  [Prelude.nat_to_string] renders a
    value of 0 or less as "0", so every caller passes 0 or more;  section 11
    lists the four numbers and the guard each one has. *)
let jint (n : int) : string = Prelude.nat_to_string n

(** [field k v] is one member of a JSON object. *)
let field (k : string) (v : string) : string = jstring k ^ ":" ^ v

(** [jobject fs] is the object of the members [fs] in the order given.  The
    order is FIXED by ruling R5, so two runs of one seed render one byte
    string. *)
let jobject (fs : string list) : string = "{" ^ Prelude.joined "," fs ^ "}"

(** [jarray vs] is the array of the values [vs] in the order given. *)
let jarray (vs : string list) : string = "[" ^ Prelude.joined "," vs ^ "]"

(** [encode_header h] is the header line, without its newline.  FIVE fields
    in THIS order: m31, seed, batch, plant, topcoat (ruling R5). *)
let encode_header (h : header) : string =
  jobject
    [
      field "m31" (jint 1);
      field "seed" (jint h.jh_seed);
      field "batch" (jint h.jh_batch);
      field "plant" (jstring h.jh_plant);
      field "topcoat" (jstring h.jh_topcoat);
    ]

(** [encode_line l] is one sample line, without its newline.  NINE fields in
    THIS order: i, mode, size, verdict, r, j, f, env, body (ruling R5). *)
let encode_line (l : line) : string =
  jobject
    [
      field "i" (jint l.jl_i);
      field "mode" (jstring l.jl_mode);
      field "size" (jint l.jl_size);
      field "verdict" (jstring l.jl_verdict);
      field "r" (jstring l.jl_r);
      field "j" (jstring l.jl_j);
      field "f" (jstring l.jl_f);
      field "env" (jarray (Prelude.map jstring l.jl_env));
      field "body" (jstring l.jl_body);
    ]

(** [as_object n v] answers the members of a JSON object.  Every constructor
    of [Json.jvalue] is named: no wildcard arm on a sum type. *)
let as_object (n : int) (v : Json.jvalue) :
    ((string * Json.jvalue) list, error) result =
  match v with
  | Json.J_obj pairs -> Ok pairs
  | Json.J_null | Json.J_true | Json.J_false | Json.J_int _ | Json.J_str _
  | Json.J_arr _ ->
      Error (E_not_object n)

(** [parse_object n text] parses one line and requires an object of it.  The
    [Json] rejection is carried into the text by its own name and offset, so
    a red gate says WHICH byte of the line broke. *)
let parse_object (n : int) (text : string) :
    ((string * Json.jvalue) list, error) result =
  Result.bind
    (Result.map_error
       (fun e ->
         E_parse
           (n, Json.error_name e ^ " at byte "
               ^ Prelude.nat_to_string (Json.error_offset e)))
       (Json.parse text))
    (as_object n)

(** [get n pairs key] answers the value of [key] or names it missing. *)
let get (n : int) (pairs : (string * Json.jvalue) list) (key : string) :
    (Json.jvalue, error) result =
  Option.fold
    ~none:(Error (E_missing (n, key)))
    ~some:(fun v -> Ok v)
    (Json.obj_get pairs key)

(** [get_int n pairs key] answers an int field. *)
let get_int (n : int) (pairs : (string * Json.jvalue) list) (key : string) :
    (int, error) result =
  Result.bind (get n pairs key) (fun v ->
      match v with
      | Json.J_int i -> Ok i
      | Json.J_null | Json.J_true | Json.J_false | Json.J_str _
      | Json.J_arr _ | Json.J_obj _ ->
          Error (E_type (n, key)))

(** [get_str n pairs key] answers a string field. *)
let get_str (n : int) (pairs : (string * Json.jvalue) list) (key : string) :
    (string, error) result =
  Result.bind (get n pairs key) (fun v ->
      match v with
      | Json.J_str s -> Ok s
      | Json.J_null | Json.J_true | Json.J_false | Json.J_int _
      | Json.J_arr _ | Json.J_obj _ ->
          Error (E_type (n, key)))

(** [get_strs n pairs key] answers an array of strings field.  A non string
    item is a type error on the WHOLE field, which is the only statement the
    caller can act on. *)
let get_strs (n : int) (pairs : (string * Json.jvalue) list) (key : string) :
    (string list, error) result =
  Result.bind (get n pairs key) (fun v ->
      match v with
      | Json.J_arr items ->
          Prelude.fold
            (fun acc it ->
              Result.bind acc (fun got ->
                  match it with
                  | Json.J_str s -> Ok (Prelude.append got (s :: []))
                  | Json.J_null | Json.J_true | Json.J_false | Json.J_int _
                  | Json.J_arr _ | Json.J_obj _ ->
                      Error (E_type (n, key))))
            (Ok []) items
      | Json.J_null | Json.J_true | Json.J_false | Json.J_int _
      | Json.J_str _ | Json.J_obj _ ->
          Error (E_type (n, key)))

(** [decode_header n text] decodes the header line.  The "m31" field must be
    exactly 1: a journal of another version is refused by NAME and never read
    as if it were this one. *)
let decode_header (n : int) (text : string) : (header, error) result =
  Result.bind (parse_object n text) (fun pairs ->
      Result.bind (get_int n pairs "m31") (fun v ->
          match () with
          | () when not (Int.equal v 1) -> Error (E_version (n, v))
          | () ->
              Result.bind (get_int n pairs "seed") (fun seed ->
                  Result.bind (get_int n pairs "batch") (fun batch ->
                      Result.bind (get_str n pairs "plant") (fun plant ->
                          Result.map
                            (fun sha ->
                              {
                                jh_seed = seed;
                                jh_batch = batch;
                                jh_plant = plant;
                                jh_topcoat = sha;
                              })
                            (get_str n pairs "topcoat"))))))

(** [decode_line n text] decodes one sample line. *)
let decode_line (n : int) (text : string) : (line, error) result =
  Result.bind (parse_object n text) (fun pairs ->
      Result.bind (get_int n pairs "i") (fun i ->
          Result.bind (get_str n pairs "mode") (fun mode ->
              Result.bind (get_int n pairs "size") (fun size ->
                  Result.bind (get_str n pairs "verdict") (fun verdict ->
                      Result.bind (get_str n pairs "r") (fun r ->
                          Result.bind (get_str n pairs "j") (fun j ->
                              Result.bind (get_str n pairs "f") (fun f ->
                                  Result.bind (get_strs n pairs "env")
                                    (fun env ->
                                      Result.map
                                        (fun body ->
                                          {
                                            jl_i = i;
                                            jl_mode = mode;
                                            jl_size = size;
                                            jl_verdict = verdict;
                                            jl_r = r;
                                            jl_j = j;
                                            jl_f = f;
                                            jl_env = env;
                                            jl_body = body;
                                          })
                                        (get_str n pairs "body"))))))))))

(** [decode_journal texts] decodes a WHOLE journal: the header first, then one
    sample line per element with the indices 0, 1, 2 and so on, contiguous and
    never repeated.  Three shapes are refused here and nowhere else: an empty
    file, a first line that is not a header (it has no "m31" field, so it is
    [E_missing (1, "m31")]), and an index that is not the one its position
    asks for.  The line numbers are 1 based and the header is line 1. *)
let decode_journal (texts : string list) : (header * line list, error) result =
  let rec go (n : int) (want : int) (acc : line list) (rest : string list) :
      (line list, error) result =
    match rest with
    | [] -> Ok (Prelude.rev acc)
    | t :: more ->
        Result.bind (decode_line n t) (fun l ->
            match () with
            | () when Int.equal l.jl_i want ->
                go (n + 1) (want + 1) (l :: acc) more
            | () -> Error (E_index (n, want, l.jl_i)))
  in
  match texts with
  | [] -> Error E_empty
  | h :: rest ->
      Result.bind (decode_header 1 h) (fun hd ->
          Result.map (fun ls -> (hd, ls)) (go 2 0 [] rest))

(** The counts the summary prints.  The first eight are the buckets, keyed by
    the head of the verdict text up to its first colon.  [t_texts] is one
    entry per DISTINCT non agree verdict text, in first appearance order until
    [sort_texts] orders it. *)
type tally = {
  t_agree : int;
  t_known : int;
  t_diverge : int;
  t_leg_fail : int;
  t_dropped : int;
  t_no_line : int;
  t_batch_fail : int;
  t_other : int;
  t_texts : (string * int) list;
}

(** [empty_tally ()] is every count at zero and no text. *)
let empty_tally () : tally =
  {
    t_agree = 0;
    t_known = 0;
    t_diverge = 0;
    t_leg_fail = 0;
    t_dropped = 0;
    t_no_line = 0;
    t_batch_fail = 0;
    t_other = 0;
    t_texts = [];
  }

(** [head t] is the verdict text up to its first colon, and the whole text
    when there is none.  "agree" heads itself;  "diverge:rendered:odd:ref"
    heads "diverge". *)
let head (t : string) : string =
  let rec go (k : int) (acc : string) : string =
    Option.fold ~none:acc
      ~some:(fun b ->
        match () with
        | () when String.equal b ":" -> acc
        | () -> go (k + 1) (acc ^ b))
      (Prelude.byte_at t k)
  in
  go 0 ""

(** [bump_head tl h] adds one to the bucket named by the head [h].  A head
    this milestone does not know counts as [t_other], and the gate requires
    other 0, so a new verdict head shows up as a RED gate and never as a
    silently dropped sample (ruling R7). *)
let bump_head (tl : tally) (h : string) : tally =
  match () with
  | () when String.equal h "agree" -> { tl with t_agree = tl.t_agree + 1 }
  | () when String.equal h "known" -> { tl with t_known = tl.t_known + 1 }
  | () when String.equal h "diverge" -> { tl with t_diverge = tl.t_diverge + 1 }
  | () when String.equal h "leg_fail" ->
      { tl with t_leg_fail = tl.t_leg_fail + 1 }
  | () when String.equal h "dropped" -> { tl with t_dropped = tl.t_dropped + 1 }
  | () when String.equal h "no_line" -> { tl with t_no_line = tl.t_no_line + 1 }
  | () when String.equal h "batch_fail" ->
      { tl with t_batch_fail = tl.t_batch_fail + 1 }
  | () -> { tl with t_other = tl.t_other + 1 }

(** [bump_text ts t] adds one to the count of the distinct text [t], keeping
    a text that is already there in its place. *)
let bump_text (ts : (string * int) list) (t : string) : (string * int) list =
  Option.fold
    ~none:(Prelude.append ts ((t, 1) :: []))
    ~some:(fun _ ->
      Prelude.map
        (fun kv ->
          match () with
          | () when String.equal (fst kv) t -> (t, snd kv + 1)
          | () -> kv)
        ts)
    (Prelude.assoc_opt String.equal t ts)

(** [tally ls] counts the decoded lines.  Every line lands in exactly one
    bucket, and every line whose verdict is not "agree" also lands in
    [t_texts], so the per text lines of the summary account for every sample
    the run did not agree on. *)
let tally (ls : line list) : tally =
  Prelude.fold
    (fun tl l ->
      let counted = bump_head tl (head l.jl_verdict) in
      match () with
      | () when String.equal l.jl_verdict "agree" -> counted
      | () -> { counted with t_texts = bump_text counted.t_texts l.jl_verdict })
    (empty_tally ()) ls

(** [order_bytes ()] is the byte order the per text lines are sorted in: the
    95 printable ASCII bytes, in ASCII order.  core/ ships no [String.compare]
    and [Prelude] exports no comparison at all, so the order is spelled here
    and is total by construction.  A byte outside the table ranks AFTER every
    byte in it and two such bytes rank EQUAL, which the stable insert below
    turns into first appearance order.  Every verdict text this repository
    produces is printable ASCII, so the tail of the order is a totality
    clause and not a behaviour anyone reads. *)
let order_bytes () =
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

(** [rank b] is the position of the one byte string [b] in [order_bytes ()],
    or 95 when it is not there. *)
let rank (b : string) : int =
  let rec go (k : int) : int =
    Option.fold ~none:95
      ~some:(fun x ->
        match () with
        | () when String.equal x b -> k
        | () -> go (k + 1))
      (Prelude.byte_at (order_bytes ()) k)
  in
  go 0

(** [before_from a b k] answers whether [a] sorts before [b], reading from
    byte [k] on.  A proper prefix sorts before its extension;  equal texts do
    not sort before each other;  two texts that first differ outside the table
    are NOT ordered and keep their insertion order. *)
let rec before_from (a : string) (b : string) (k : int) : bool =
  Option.fold
    ~none:
      (Option.fold ~none:false ~some:(fun _ -> true) (Prelude.byte_at b k))
    ~some:(fun ba ->
      Option.fold ~none:false
        ~some:(fun bb ->
          match () with
          | () when String.equal ba bb -> before_from a b (k + 1)
          | () -> rank ba < rank bb)
        (Prelude.byte_at b k))
    (Prelude.byte_at a k)

(** [before a b] answers whether [a] sorts before [b]. *)
let before (a : string) (b : string) : bool = before_from a b 0

(** [insert kv ts] puts [kv] in front of the first entry it sorts before.  An
    entry that sorts before nothing lands at the end, so folding left to right
    keeps two unordered texts in first appearance order: the sort is STABLE
    and the summary is a function of the journal alone. *)
let rec insert (kv : string * int) (ts : (string * int) list) :
    (string * int) list =
  match ts with
  | [] -> kv :: []
  | x :: rest ->
      (match () with
      | () when before (fst kv) (fst x) -> kv :: ts
      | () -> x :: insert kv rest)

(** [sort_texts ts] orders the per text entries by [before]. *)
let sort_texts (ts : (string * int) list) : (string * int) list =
  Prelude.fold (fun acc kv -> insert kv acc) [] ts

(** [count_line tl] is the bucket line of the summary. *)
let count_line (tl : tally) : string =
  "m31 agree " ^ Prelude.nat_to_string tl.t_agree ^ " known "
  ^ Prelude.nat_to_string tl.t_known ^ " diverge "
  ^ Prelude.nat_to_string tl.t_diverge ^ " leg_fail "
  ^ Prelude.nat_to_string tl.t_leg_fail ^ " dropped "
  ^ Prelude.nat_to_string tl.t_dropped ^ " no_line "
  ^ Prelude.nat_to_string tl.t_no_line ^ " batch_fail "
  ^ Prelude.nat_to_string tl.t_batch_fail ^ " other "
  ^ Prelude.nat_to_string tl.t_other ^ "\n"

(** [summary_text ~seed_hex ~path h ls] is the WHOLE stdout of a run and of a
    replay, newline terminated.  It reads NOTHING but the decoded journal
    (ruling R7), which is why the two print the same bytes by construction.
    [seed_hex] arrives from the caller because [Cover.hex_str] lives in
    shell/cover.ml:162-165 and core may not call shell;  [path] arrives from
    the caller because core names no path of its own. *)
let summary_text ~(seed_hex : string) ~(path : string) (h : header)
    (ls : line list) : string =
  let tl = tally ls in
  let k = Prelude.len ls in
  Prelude.concat
    [
      "m31 seed " ^ seed_hex ^ " samples " ^ Prelude.nat_to_string k
      ^ " batch " ^ Prelude.nat_to_string h.jh_batch ^ " plant " ^ h.jh_plant
      ^ " topcoat " ^ h.jh_topcoat ^ "\n";
      count_line tl;
      Prelude.concat
        (Prelude.map
           (fun kv ->
             "m31 " ^ fst kv ^ " " ^ Prelude.nat_to_string (snd kv) ^ "\n")
           (sort_texts tl.t_texts));
      "m31 journal " ^ path ^ " lines " ^ Prelude.nat_to_string k ^ "\n";
    ]
