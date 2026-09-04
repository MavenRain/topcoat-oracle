(* M24 JSON reader (DESIGN.md M24, spec section 3).  A hand-rolled,
   total, result-typed reader for the JSON subset the Rust harness
   writes.  No third-party dependency, because yojson raises and
   because M25 and M26 reuse this reader for the js leg.

   Every rejection is a named constructor that carries the byte
   offset, so a red gate names the byte.  Nothing is coerced, nothing
   wraps and nothing is repaired.

   Caps and bounds:
   - nesting depth 64.  A wire line reaches depth 4.  Passing the cap
     is E_depth with the offset of the bracket, never a stack
     overflow.
   - digit run 18.  18 digits is at most 999999999999999999, which is
     below 2^62, so acc * 10 + d cannot overflow the 63-bit native
     int.  A 19th digit is E_too_many_digits.
   - a minus sign, a fraction point and an exponent are each a named
     error.  The wire carries non-negative integers only.

   ONE documented laxness: a raw byte below 0x20 inside a string is
   ACCEPTED and copied verbatim.  Strict JSON rejects it.  Every wire
   payload is hex and every key is ASCII, so no wire line can carry
   one, and rejecting it would need a byte-order comparison the subset
   needs for nothing else. *)

open Prelude

type jvalue =
  | J_null
  | J_true
  | J_false
  | J_int of int
  | J_str of string (* decoded bytes, escapes resolved *)
  | J_arr of jvalue list
  | J_obj of (string * jvalue) list (* source order, no duplicates *)

type jerror =
  | E_unexpected of int (* byte offset of the offending byte *)
  | E_unterminated of int (* offset of the opening quote *)
  | E_bad_escape of int (* offset of the backslash *)
  | E_unicode_escape of int (* offset of the backslash of \u *)
  | E_minus of int
  | E_fraction of int
  | E_exponent of int
  | E_leading_zero of int
  | E_too_many_digits of int
  | E_dup_key of string * int (* the repeated key, offset of its quote *)
  | E_depth of int (* offset of the bracket that passed the cap *)
  | E_trailing of int (* offset of the first trailing byte *)

let error_name e =
  match e with
  | E_unexpected _ -> "unexpected"
  | E_unterminated _ -> "unterminated"
  | E_bad_escape _ -> "bad_escape"
  | E_unicode_escape _ -> "unicode_escape"
  | E_minus _ -> "minus"
  | E_fraction _ -> "fraction"
  | E_exponent _ -> "exponent"
  | E_leading_zero _ -> "leading_zero"
  | E_too_many_digits _ -> "too_many_digits"
  | E_dup_key _ -> "dup_key"
  | E_depth _ -> "depth"
  | E_trailing _ -> "trailing"

let error_offset e =
  match e with
  | E_unexpected n -> n
  | E_unterminated n -> n
  | E_bad_escape n -> n
  | E_unicode_escape n -> n
  | E_minus n -> n
  | E_fraction n -> n
  | E_exponent n -> n
  | E_leading_zero n -> n
  | E_too_many_digits n -> n
  | E_dup_key (_key, n) -> n
  | E_depth n -> n
  | E_trailing n -> n

(* The reader never mutates.  Every step returns a new cursor, and
   every accepting step advances pos by at least one byte, so the
   recursion is structural on the remaining input. *)
type cursor = { src : string; pos : int; depth : int }

(* "" is the end of input.  byte_at never returns a zero-length
   string, so the marker is unambiguous even on a NUL byte. *)
let byte_or_eof s i = Option.fold ~none:"" ~some:(fun b -> b) (byte_at s i)
let cur c = byte_or_eof c.src c.pos

(* A digit is found by a String.equal scan over the ten one-byte
   strings, so nothing assumes a character set.  The table is bound
   INSIDE the helper: zxlint trap2 says a helper that reads a top-level
   constant becomes an undeclared identifier in the emitted Zig. *)
let digit_val b =
  let digit_table =
    [
      ("0", 0); ("1", 1); ("2", 2); ("3", 3); ("4", 4);
      ("5", 5); ("6", 6); ("7", 7); ("8", 8); ("9", 9);
    ]
  in
  Option.fold ~none:(-1) ~some:(fun d -> d)
    (assoc_opt String.equal b digit_table)

let has_key key pairs =
  Option.fold ~none:false ~some:(fun _ -> true)
    (assoc_opt String.equal key pairs)

let is_ws b =
  String.equal b " " || String.equal b "\009" || String.equal b "\010"
  || String.equal b "\013"

let rec skip_ws c =
  match () with
  | () when is_ws (cur c) -> skip_ws { c with pos = c.pos + 1 }
  | () -> c

(* Whole-word match, byte by byte.  A partial word is rejected by the
   caller at the offset where the word started. *)
let rec word_at src pos w i =
  match () with
  | () when i >= String.length w -> true
  | () when String.equal (byte_or_eof src (pos + i)) (byte_or_eof w i) ->
      word_at src pos w (i + 1)
  | () -> false

(* The two caps are functions, not constants: a helper may call a
   top-level function, but reading a top-level constant is zxlint
   trap2. *)
let max_depth () = 64
let max_digits () = 18

let rec parse_value c =
  let c1 = skip_ws c in
  let b = cur c1 in
  match () with
  | () when String.equal b "{" -> open_obj c1
  | () when String.equal b "[" -> open_arr c1
  | () when String.equal b "\"" -> parse_string c1
  | () when String.equal b "n" -> parse_word c1 "null" J_null
  | () when String.equal b "t" -> parse_word c1 "true" J_true
  | () when String.equal b "f" -> parse_word c1 "false" J_false
  | () when String.equal b "-" -> Error (E_minus c1.pos)
  | () when digit_val b >= 0 -> read_digits c1 c1.pos 0 0
  | () -> Error (E_unexpected c1.pos)

and parse_word c w v =
  match () with
  | () when word_at c.src c.pos w 0 ->
      Ok (v, { c with pos = c.pos + String.length w })
  | () -> Error (E_unexpected c.pos)

and read_digits c start acc n =
  let b = cur c in
  let d = digit_val b in
  match () with
  | () when String.equal b "." -> Error (E_fraction c.pos)
  | () when String.equal b "e" || String.equal b "E" ->
      Error (E_exponent c.pos)
  | () when d < 0 -> end_number c start acc n
  | () when n >= max_digits () -> Error (E_too_many_digits start)
  | () -> read_digits { c with pos = c.pos + 1 } start ((acc * 10) + d) (n + 1)

and end_number c start acc n =
  match () with
  | () when n >= 2 && String.equal (byte_or_eof c.src start) "0" ->
      Error (E_leading_zero start)
  | () -> Ok (J_int acc, c)

and parse_string c =
  Result.map (fun p -> (J_str (fst p), snd p)) (read_string c)

(* c.pos is the opening quote;  the offset is kept for the
   unterminated error. *)
and read_string c = read_str_body { c with pos = c.pos + 1 } c.pos ""

and read_str_body c open_pos acc =
  let b = cur c in
  match () with
  | () when String.equal b "" -> Error (E_unterminated open_pos)
  | () when String.equal b "\"" -> Ok (acc, { c with pos = c.pos + 1 })
  | () when String.equal b "\\" -> read_escape c open_pos acc
  | () -> read_str_body { c with pos = c.pos + 1 } open_pos (acc ^ b)

and read_escape c open_pos acc =
  let escape_table =
    [
      ("\"", "\""); ("\\", "\\"); ("/", "/"); ("b", "\008");
      ("f", "\012"); ("n", "\010"); ("r", "\013"); ("t", "\009");
    ]
  in
  let e = byte_or_eof c.src (c.pos + 1) in
  match () with
  | () when String.equal e "" -> Error (E_unterminated open_pos)
  | () when String.equal e "u" -> Error (E_unicode_escape c.pos)
  | () ->
      Option.fold
        ~none:(Error (E_bad_escape c.pos))
        ~some:(fun d ->
          read_str_body { c with pos = c.pos + 2 } open_pos (acc ^ d))
        (assoc_opt String.equal e escape_table)

and open_arr c =
  match () with
  | () when c.depth >= max_depth () -> Error (E_depth c.pos)
  | () -> arr_first { c with pos = c.pos + 1; depth = c.depth + 1 } []

and arr_first c acc =
  let c1 = skip_ws c in
  match () with
  | () when String.equal (cur c1) "]" ->
      Ok (J_arr (rev acc), { c1 with pos = c1.pos + 1; depth = c1.depth - 1 })
  | () -> arr_item c1 acc

and arr_item c acc =
  Result.bind (parse_value c) (fun p -> arr_tail (snd p) (fst p :: acc))

and arr_tail c acc =
  let c1 = skip_ws c in
  let b = cur c1 in
  match () with
  | () when String.equal b "," -> arr_item { c1 with pos = c1.pos + 1 } acc
  | () when String.equal b "]" ->
      Ok (J_arr (rev acc), { c1 with pos = c1.pos + 1; depth = c1.depth - 1 })
  | () -> Error (E_unexpected c1.pos)

and open_obj c =
  match () with
  | () when c.depth >= max_depth () -> Error (E_depth c.pos)
  | () -> obj_first { c with pos = c.pos + 1; depth = c.depth + 1 } []

and obj_first c acc =
  let c1 = skip_ws c in
  match () with
  | () when String.equal (cur c1) "}" ->
      Ok (J_obj (rev acc), { c1 with pos = c1.pos + 1; depth = c1.depth - 1 })
  | () -> obj_key c1 acc

and obj_key c acc =
  let c1 = skip_ws c in
  match () with
  | () when String.equal (cur c1) "\"" ->
      Result.bind (read_string c1) (fun p ->
          obj_colon (snd p) acc (fst p) c1.pos)
  | () -> Error (E_unexpected c1.pos)

(* The duplicate test is an assoc_opt lookup against the pairs read so
   far.  That is quadratic in the key count;  a wire line has at most
   nine keys, so it is free. *)
and obj_colon c acc key kpos =
  let c1 = skip_ws c in
  match () with
  | () when not (String.equal (cur c1) ":") -> Error (E_unexpected c1.pos)
  | () when has_key key acc -> Error (E_dup_key (key, kpos))
  | () ->
      Result.bind
        (parse_value { c1 with pos = c1.pos + 1 })
        (fun p -> obj_tail (snd p) ((key, fst p) :: acc))

and obj_tail c acc =
  let c1 = skip_ws c in
  let b = cur c1 in
  match () with
  | () when String.equal b "," -> obj_key { c1 with pos = c1.pos + 1 } acc
  | () when String.equal b "}" ->
      Ok (J_obj (rev acc), { c1 with pos = c1.pos + 1; depth = c1.depth - 1 })
  | () -> Error (E_unexpected c1.pos)

(* One value, then optional whitespace, then end of input.  Anything
   after that is E_trailing at the offset of the first trailing
   byte. *)
let parse s =
  Result.bind
    (parse_value { src = s; pos = 0; depth = 0 })
    (fun p ->
      let c = skip_ws (snd p) in
      match () with
      | () when String.equal (cur c) "" -> Ok (fst p)
      | () -> Error (E_trailing c.pos))

let obj_get pairs key = assoc_opt String.equal key pairs
let obj_keys pairs = map fst pairs
