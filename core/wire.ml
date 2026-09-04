(* M24 wire decoder (DESIGN.md M24, spec section 3.4 and 3.5).  One
   JSONL line from driver-rs/harness.rs becomes a fully built
   Obs.observation plus the wire extras that have no home in it.

   The decoder is strict.  The key set per outcome is EXACT, so a
   missing key, an extra key or a wrong shape is a named error that
   carries the key.  Key ORDER is free, because the reader keeps JSON
   semantics.  Nothing is coerced, nothing is repaired and nothing
   wraps.

   The wire extras (the js bytes, js_form, js_consistent and the
   per-signal Debug text) ride BESIDE the observation in the decoded
   record.  They are never folded into Obs.observation, which keeps
   exactly the three fields core/obs.ml declares.

   Bounds this module owns:
   - hi and lo are each in [0, 4294967295], one 32-bit half.
     4294967296 is W_range ("hi", n).
   - a hex payload has an even length and only the bytes 0-9 a-f.  An
     odd length is W_odd_hex, any other byte is W_bad_hex.  An EMPTY
     hex payload is legal and decodes to the empty byte string: seed
     cases 2 and 4 carry one. *)

open Prelude

type js_form = Jf_direct | Jf_closure | Jf_absent
type hint = Hw_none | Hw_expect | Hw_expect_err | Hw_both

let hint_wire h =
  match h with
  | Hw_none -> "none"
  | Hw_expect -> "expect"
  | Hw_expect_err -> "expect_err"
  | Hw_both -> "both"

let js_form_wire f =
  match f with
  | Jf_direct -> "direct"
  | Jf_closure -> "closure"
  | Jf_absent -> "absent"

type decoded = {
  d_case : int;
  d_hint : hint;
  d_obs : Obs.observation;
  d_js : string; (* decoded js bytes, "" when the line carries none *)
  d_js_form : js_form;
  d_js_consistent : bool;
  d_debug : (int * string) list; (* signal id, decoded Debug bytes *)
}

type werror =
  | W_json of Json.jerror
  | W_not_object
  | W_missing_key of string
  | W_extra_key of string
  | W_bad_shape of string (* the key whose JSON shape is wrong *)
  | W_unknown_outcome of string
  | W_unknown_tag of string (* the value object's "t" *)
  | W_unknown_class of string
  | W_unknown_hint of string
  | W_unknown_js_form of string
  | W_range of string * int (* key, the out-of-range integer *)
  | W_odd_hex of string (* key *)
  | W_bad_hex of string (* key *)

let werror_name w =
  match w with
  | W_json _ -> "json"
  | W_not_object -> "not_object"
  | W_missing_key _ -> "missing_key"
  | W_extra_key _ -> "extra_key"
  | W_bad_shape _ -> "bad_shape"
  | W_unknown_outcome _ -> "unknown_outcome"
  | W_unknown_tag _ -> "unknown_tag"
  | W_unknown_class _ -> "unknown_class"
  | W_unknown_hint _ -> "unknown_hint"
  | W_unknown_js_form _ -> "unknown_js_form"
  | W_range _ -> "range"
  | W_odd_hex _ -> "odd_hex"
  | W_bad_hex _ -> "bad_hex"

(* The 256 single bytes, in order, so byte_at (byte_table ()) n is the
   byte whose value is n.  Char.chr raises, so this table is how a
   decoded hex pair becomes a byte.  The length invariant is asserted
   by a unit test, not by an assert.

   It is a function, not a constant: zxlint trap2 rejects a helper that
   reads a top-level constant, and one table read by both the exported
   name and the decoder beats two copies that can drift. *)
let byte_table () =
  "\000\001\002\003\004\005\006\007\008\009\010\011\012\013\014\015"
  ^ "\016\017\018\019\020\021\022\023\024\025\026\027\028\029\030\031"
  ^ "\032\033\034\035\036\037\038\039\040\041\042\043\044\045\046\047"
  ^ "\048\049\050\051\052\053\054\055\056\057\058\059\060\061\062\063"
  ^ "\064\065\066\067\068\069\070\071\072\073\074\075\076\077\078\079"
  ^ "\080\081\082\083\084\085\086\087\088\089\090\091\092\093\094\095"
  ^ "\096\097\098\099\100\101\102\103\104\105\106\107\108\109\110\111"
  ^ "\112\113\114\115\116\117\118\119\120\121\122\123\124\125\126\127"
  ^ "\128\129\130\131\132\133\134\135\136\137\138\139\140\141\142\143"
  ^ "\144\145\146\147\148\149\150\151\152\153\154\155\156\157\158\159"
  ^ "\160\161\162\163\164\165\166\167\168\169\170\171\172\173\174\175"
  ^ "\176\177\178\179\180\181\182\183\184\185\186\187\188\189\190\191"
  ^ "\192\193\194\195\196\197\198\199\200\201\202\203\204\205\206\207"
  ^ "\208\209\210\211\212\213\214\215\216\217\218\219\220\221\222\223"
  ^ "\224\225\226\227\228\229\230\231\232\233\234\235\236\237\238\239"
  ^ "\240\241\242\243\244\245\246\247\248\249\250\251\252\253\254\255"

(* The exported name the unit test pins. *)
let all_bytes = byte_table ()

let byte_or_empty s i = Option.fold ~none:"" ~some:(fun b -> b) (byte_at s i)

(* A hex digit is found by a String.equal scan over the sixteen
   one-byte strings, so nothing assumes a character set.  An uppercase
   digit is absent from the table on purpose: the writer emits
   lowercase and drift is reported, never repaired. *)
let hex_val b =
  let hex_table =
    [
      ("0", 0); ("1", 1); ("2", 2); ("3", 3); ("4", 4); ("5", 5);
      ("6", 6); ("7", 7); ("8", 8); ("9", 9); ("a", 10); ("b", 11);
      ("c", 12); ("d", 13); ("e", 14); ("f", 15);
    ]
  in
  Option.fold ~none:(-1) ~some:(fun v -> v) (assoc_opt String.equal b hex_table)

(* A byte from a number, through the table.  n is always in [0, 255]
   here, because it is 16 * high nibble + low nibble.  The helper calls
   byte_table () and does not read all_bytes, because zxlint trap2
   rejects a top-level constant read from a helper: ZxCaml emits a
   top-level constant for the entrypoint only.  The two are the same
   256 bytes, and the unit test pins all_bytes against them. *)
let byte_of_int n =
  Option.fold ~none:"" ~some:(fun b -> b) (byte_at (byte_table ()) n)

let rec hex_go key s i acc =
  match () with
  | () when i >= String.length s -> Ok acc
  | () when i + 1 >= String.length s -> Error (W_odd_hex key)
  | () ->
      let h = hex_val (byte_or_empty s i) in
      let l = hex_val (byte_or_empty s (i + 1)) in
      (match () with
      | () when h < 0 || l < 0 -> Error (W_bad_hex key)
      | () -> hex_go key s (i + 2) (acc ^ byte_of_int ((h * 16) + l)))

(* key is carried so a red gate names the payload that was wrong. *)
let hex_bytes key s = hex_go key s 0 ""

let parse_hint s =
  match () with
  | () when String.equal s "none" -> Ok Hw_none
  | () when String.equal s "expect" -> Ok Hw_expect
  | () when String.equal s "expect_err" -> Ok Hw_expect_err
  | () when String.equal s "both" -> Ok Hw_both
  | () -> Error (W_unknown_hint s)

let parse_js_form s =
  match () with
  | () when String.equal s "direct" -> Ok Jf_direct
  | () when String.equal s "closure" -> Ok Jf_closure
  | () when String.equal s "absent" -> Ok Jf_absent
  | () -> Error (W_unknown_js_form s)

(* The inverse of Obs.encode_panic_class: six spellings, no aliasing,
   no prefix matching and no case folding. *)
let parse_class s =
  match () with
  | () when String.equal s "unwrap" -> Ok Obs.P_unwrap
  | () when String.equal s "expect" -> Ok Obs.P_expect
  | () when String.equal s "unwrap_err" -> Ok Obs.P_unwrap_err
  | () when String.equal s "expect_err" -> Ok Obs.P_expect_err
  | () when String.equal s "signal_write" -> Ok Obs.P_signal_write
  | () when String.equal s "other" -> Ok Obs.P_other
  | () -> Error (W_unknown_class s)

(* ---------- exact key sets ---------- *)

(* Each set is a function, not a constant: zxlint trap2 rejects a
   helper that reads a top-level constant. *)
let value_keys () =
  [
    "case"; "outcome"; "value"; "rendered_hex"; "js_consistent"; "js_hex";
    "js_form"; "hint"; "signals";
  ]

let panic_keys () =
  [ "case"; "outcome"; "class"; "msg_hex"; "js_hex"; "js_form"; "hint";
    "signals" ]

let no_terminate_keys () = [ "case"; "outcome"; "hint" ]
let signal_keys () = [ "id"; "value"; "debug_hex" ]

let has_key pairs k =
  Option.fold ~none:false ~some:(fun _ -> true) (Json.obj_get pairs k)

let rec mem_key k keys =
  match keys with
  | [] -> false
  | k1 :: rest -> String.equal k k1 || mem_key k rest

let rec check_missing keys pairs =
  match keys with
  | [] -> Ok ()
  | k :: rest -> (
      match () with
      | () when has_key pairs k -> check_missing rest pairs
      | () -> Error (W_missing_key k))

let rec check_extra actual keys =
  match actual with
  | [] -> Ok ()
  | k :: rest -> (
      match () with
      | () when mem_key k keys -> check_extra rest keys
      | () -> Error (W_extra_key k))

(* Missing first, then extra, so a line that is short AND long names
   the missing key.  Order inside the object is free. *)
let check_keys pairs keys =
  Result.bind (check_missing keys pairs) (fun () ->
      check_extra (Json.obj_keys pairs) keys)

(* ---------- typed accessors ---------- *)

let require pairs key =
  Option.fold
    ~none:(Error (W_missing_key key))
    ~some:(fun v -> Ok v)
    (Json.obj_get pairs key)

let get_str key pairs =
  Result.bind (require pairs key) (fun v ->
      match v with
      | Json.J_str s -> Ok s
      | Json.J_null | Json.J_true | Json.J_false | Json.J_int _
      | Json.J_arr _ | Json.J_obj _ ->
          Error (W_bad_shape key))

let get_int key pairs =
  Result.bind (require pairs key) (fun v ->
      match v with
      | Json.J_int n -> Ok n
      | Json.J_null | Json.J_true | Json.J_false | Json.J_str _
      | Json.J_arr _ | Json.J_obj _ ->
          Error (W_bad_shape key))

let get_bool key pairs =
  Result.bind (require pairs key) (fun v ->
      match v with
      | Json.J_true -> Ok true
      | Json.J_false -> Ok false
      | Json.J_null | Json.J_int _ | Json.J_str _ | Json.J_arr _
      | Json.J_obj _ ->
          Error (W_bad_shape key))

let get_arr key pairs =
  Result.bind (require pairs key) (fun v ->
      match v with
      | Json.J_arr items -> Ok items
      | Json.J_null | Json.J_true | Json.J_false | Json.J_int _
      | Json.J_str _ | Json.J_obj _ ->
          Error (W_bad_shape key))

let get_hex key pairs =
  Result.bind (get_str key pairs) (fun s -> hex_bytes key s)

let get_hint pairs = Result.bind (get_str "hint" pairs) parse_hint
let get_js_form pairs = Result.bind (get_str "js_form" pairs) parse_js_form

(* One 32-bit half.  4294967296 is the first rejected value. *)
let check_half key n =
  match () with
  | () when n >= 0 && n <= 4294967295 -> Ok n
  | () -> Error (W_range (key, n))

(* ---------- value objects ---------- *)

let rec decode_value v =
  match v with
  | Json.J_obj pairs -> decode_value_obj pairs
  | Json.J_null | Json.J_true | Json.J_false | Json.J_int _ | Json.J_str _
  | Json.J_arr _ ->
      Error (W_bad_shape "value")

and decode_value_obj pairs =
  Result.bind (get_str "t" pairs) (fun t ->
      match () with
      | () when String.equal t "unit" -> tagged pairs [ "t" ] Obs.V_unit
      | () when String.equal t "none" -> tagged pairs [ "t" ] Obs.V_none
      | () when String.equal t "closure" -> tagged pairs [ "t" ] Obs.V_closure
      | () when String.equal t "f64" -> decode_f64 pairs
      | () when String.equal t "bool" -> decode_bool pairs
      | () when String.equal t "str" -> decode_str pairs
      | () when String.equal t "tuple" -> decode_tuple pairs
      | () when String.equal t "some" -> decode_wrap pairs (fun w -> Obs.V_some w)
      | () when String.equal t "ok" -> decode_wrap pairs (fun w -> Obs.V_ok w)
      | () when String.equal t "err" -> decode_wrap pairs (fun w -> Obs.V_err w)
      | () -> Error (W_unknown_tag t))

(* A nullary tag carries the key "t" and nothing else. *)
and tagged pairs keys v = Result.map (fun () -> v) (check_keys pairs keys)

and decode_f64 pairs =
  Result.bind (check_keys pairs [ "t"; "hi"; "lo" ]) (fun () ->
      Result.bind (get_int "hi" pairs) (fun hi ->
          Result.bind (check_half "hi" hi) (fun hi1 ->
              Result.bind (get_int "lo" pairs) (fun lo ->
                  Result.map
                    (fun lo1 -> Obs.V_f64_bits (hi1, lo1))
                    (check_half "lo" lo)))))

and decode_bool pairs =
  Result.bind (check_keys pairs [ "t"; "v" ]) (fun () ->
      Result.map (fun b -> Obs.V_bool b) (get_bool "v" pairs))

and decode_str pairs =
  Result.bind (check_keys pairs [ "t"; "hex" ]) (fun () ->
      Result.map (fun s -> Obs.V_str s) (get_hex "hex" pairs))

and decode_tuple pairs =
  Result.bind (check_keys pairs [ "t"; "vs" ]) (fun () ->
      Result.bind (get_arr "vs" pairs) (fun items ->
          Result.map (fun vs -> Obs.V_tuple vs) (decode_values items [])))

and decode_wrap pairs f =
  Result.bind (check_keys pairs [ "t"; "v" ]) (fun () ->
      Result.bind (require pairs "v") (fun jv ->
          Result.map f (decode_value jv)))

and decode_values items acc =
  match items with
  | [] -> Ok (rev acc)
  | v :: rest ->
      Result.bind (decode_value v) (fun d -> decode_values rest (d :: acc))

(* ---------- signals ---------- *)

(* One entry becomes a pair of pairs: the (id, value) that belongs in
   the observation, and the (id, Debug bytes) that stays beside it. *)
let decode_signal jv =
  match jv with
  | Json.J_obj pairs ->
      Result.bind (check_keys pairs (signal_keys ())) (fun () ->
          Result.bind (get_int "id" pairs) (fun id ->
              Result.bind (require pairs "value") (fun v ->
                  Result.bind (decode_value v) (fun dv ->
                      Result.map
                        (fun dbg -> ((id, dv), (id, dbg)))
                        (get_hex "debug_hex" pairs)))))
  | Json.J_null | Json.J_true | Json.J_false | Json.J_int _ | Json.J_str _
  | Json.J_arr _ ->
      Error (W_bad_shape "signals")

let rec decode_signals items acc_sig acc_dbg =
  match items with
  | [] -> Ok (rev acc_sig, rev acc_dbg)
  | it :: rest ->
      Result.bind (decode_signal it) (fun p ->
          decode_signals rest (fst p :: acc_sig) (snd p :: acc_dbg))

(* Wire order is kept.  No sorting anywhere. *)
let get_signals pairs =
  Result.bind (get_arr "signals" pairs) (fun items ->
      decode_signals items [] [])

(* ---------- one line ---------- *)

(* The three wire extras travel together, so the decode chain stays
   shallow enough to read. *)
type wextras = { x_js : string; x_form : js_form; x_consistent : bool }

let value_extras pairs =
  Result.bind (get_hex "js_hex" pairs) (fun js ->
      Result.bind (get_js_form pairs) (fun form ->
          Result.map
            (fun c -> { x_js = js; x_form = form; x_consistent = c })
            (get_bool "js_consistent" pairs)))

(* A panic line and a no-terminate line carry no js_consistent key.
   True is the harness default: observed_bare builds every such
   observation with js_consistent true, and the writer omits the key
   because the field is meaningless without a direct site.  This is a
   projection of that default, not an invention. *)
let panic_extras pairs =
  Result.bind (get_hex "js_hex" pairs) (fun js ->
      Result.map
        (fun form -> { x_js = js; x_form = form; x_consistent = true })
        (get_js_form pairs))

let decode_value_line pairs =
  Result.bind (check_keys pairs (value_keys ())) (fun () ->
  Result.bind (get_int "case" pairs) (fun case ->
  Result.bind (get_hint pairs) (fun h ->
  Result.bind (require pairs "value") (fun jv ->
  Result.bind (decode_value jv) (fun v ->
  Result.bind (get_hex "rendered_hex" pairs) (fun rendered ->
  Result.bind (value_extras pairs) (fun x ->
  Result.map
    (fun sigs ->
      {
        d_case = case;
        d_hint = h;
        d_obs =
          { Obs.outcome = Obs.O_value v; rendered; signals = fst sigs };
        d_js = x.x_js;
        d_js_form = x.x_form;
        d_js_consistent = x.x_consistent;
        d_debug = snd sigs;
      })
    (get_signals pairs))))))))

(* A panic line carries no rendered_hex, so the rendered channel is the
   empty string. *)
let decode_panic_line pairs =
  Result.bind (check_keys pairs (panic_keys ())) (fun () ->
  Result.bind (get_int "case" pairs) (fun case ->
  Result.bind (get_hint pairs) (fun h ->
  Result.bind (get_str "class" pairs) (fun cw ->
  Result.bind (parse_class cw) (fun cls ->
  Result.bind (get_hex "msg_hex" pairs) (fun msg ->
  Result.bind (panic_extras pairs) (fun x ->
  Result.map
    (fun sigs ->
      {
        d_case = case;
        d_hint = h;
        d_obs =
          {
            Obs.outcome = Obs.O_panic (cls, msg);
            rendered = "";
            signals = fst sigs;
          };
        d_js = x.x_js;
        d_js_form = x.x_form;
        d_js_consistent = x.x_consistent;
        d_debug = snd sigs;
      })
    (get_signals pairs))))))))

(* A no-terminate line carries case, outcome and hint only.  The three
   other columns are the harness defaults for a line that carries none
   of them: Form::Absent, an empty js payload and js_consistent true. *)
let decode_no_terminate_line pairs =
  Result.bind (check_keys pairs (no_terminate_keys ())) (fun () ->
  Result.bind (get_int "case" pairs) (fun case ->
  Result.map
    (fun h ->
      {
        d_case = case;
        d_hint = h;
        d_obs =
          { Obs.outcome = Obs.O_no_terminate; rendered = ""; signals = [] };
        d_js = "";
        d_js_form = Jf_absent;
        d_js_consistent = true;
        d_debug = [];
      })
    (get_hint pairs)))

let decode_obj pairs =
  Result.bind (get_str "outcome" pairs) (fun o ->
      match () with
      | () when String.equal o "value" -> decode_value_line pairs
      | () when String.equal o "panic" -> decode_panic_line pairs
      | () when String.equal o "no_terminate" -> decode_no_terminate_line pairs
      | () -> Error (W_unknown_outcome o))

let decode_line line =
  Result.bind
    (Result.map_error (fun e -> W_json e) (Json.parse line))
    (fun jv ->
      match jv with
      | Json.J_obj pairs -> decode_obj pairs
      | Json.J_null | Json.J_true | Json.J_false | Json.J_int _ | Json.J_str _
      | Json.J_arr _ ->
          Error W_not_object)

(* The ONLY route to a resume index.  m23_gate.sh read it with a
   regex;  M24 decodes the line instead, so a malformed tail is a named
   error and never a silent zero. *)
let next_from line = Result.map (fun d -> d.d_case + 1) (decode_line line)
