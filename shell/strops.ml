(* Rust str-surface ops over UTF-8 byte strings (shell, full OCaml).
   Injected into core alongside the float ops: core never inspects
   string contents (byte length via String.length is the one
   exception, matching Rust's byte-counting str::len).
   - cmp: byte order, which for valid UTF-8 equals code-point order
     (the Rust `str` Ord the browser side patches JS to match, #236).
   - trim family: Rust strips the Unicode White_Space set (probe:
     U+0085 and U+2028 stripped, U+FEFF kept), not ECMAScript's
     (#238 on the browser side).
   - debug: Rust {:?} escaping, byte-exact for ASCII ('\0' stays
     "\\0", other C0 and DEL become "\\u{..}"); printable non-ASCII
     passes through verbatim. Rust additionally escapes
     grapheme-extend and unassigned code points - an accepted
     approximation until the generator emits such strings. The same
     text is a valid Rust string literal, so the printer reuses it. *)

let cmp = String.compare

let starts_with s t = String.starts_with ~prefix:t s

let ends_with s t = String.ends_with ~suffix:t s

let contains s t =
  let n = String.length s in
  let m = String.length t in
  let rec at i =
    if i + m > n then false
    else if String.equal (String.sub s i m) t then true (* @total-accessor *)
    else at (i + 1)
  in
  at 0

let is_rust_whitespace u =
  match u with
  | 0x09 | 0x0A | 0x0B | 0x0C | 0x0D | 0x20 | 0x85 | 0xA0 | 0x1680
  | 0x2000 | 0x2001 | 0x2002 | 0x2003 | 0x2004 | 0x2005 | 0x2006
  | 0x2007 | 0x2008 | 0x2009 | 0x200A | 0x2028 | 0x2029 | 0x202F
  | 0x205F | 0x3000 -> true
  | _ -> false

(* A decoded scalar counts as whitespace only when the decode is
   valid; malformed bytes act as content and stop the trim. Callers
   guard i < length s, so the decode itself stays in bounds, and the
   decode length is clamped to the remaining bytes. *)
let decode_ws s i =
  let d = String.get_utf_8_uchar s i in
  ( Uchar.utf_decode_length d,
    Uchar.utf_decode_is_valid d
    && is_rust_whitespace (Uchar.to_int (Uchar.utf_decode_uchar d)) )

let trim_start s =
  let n = String.length s in
  let rec from i =
    if i >= n then ""
    else
      let d = decode_ws s i in
      if snd d then from (i + fst d)
      else if i >= 0 && i <= n then String.sub s i (n - i) (* @total-accessor *)
      else ""
  in
  from 0

(* One forward pass tracking the end of the last non-whitespace
   scalar, so no backward UTF-8 decoding is needed; the tracked end
   is always a decode boundary, hence within [0, n]. *)
let trim_end s =
  let n = String.length s in
  let rec scan i keep =
    if i >= n then keep
    else
      let d = decode_ws s i in
      scan (i + fst d) (if snd d then keep else min (i + fst d) n)
  in
  let e = scan 0 0 in
  if e >= 0 && e <= n then String.sub s 0 e else s (* @total-accessor *)

let trim s = trim_end (trim_start s)

let escape_char c =
  match c with
  | '"' -> "\\\""
  | '\\' -> "\\\\"
  | '\n' -> "\\n"
  | '\r' -> "\\r"
  | '\t' -> "\\t"
  | '\x00' -> "\\0"
  | _ ->
      let n = Char.code c in
      if n < 0x20 || n = 0x7F then Printf.sprintf "\\u{%x}" n
      else String.make 1 c

let debug s =
  String.fold_left (fun acc c -> acc ^ escape_char c) "\"" s ^ "\""
