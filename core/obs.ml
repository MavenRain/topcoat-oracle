(* Observations (M12): the common ADT all three legs normalize into,
   plus a canonical byte-string encoding used for comparison and
   dedup. Two channels per observation: the bit-exact value channel
   (f64 as IEEE bit pattern halves, strings as bytes) and the
   rendered-text channel (each leg's own display path).

   The encoding is injective on the value channel: every constructor
   emits a distinct leading letter, strings and tuples are
   length-prefixed, and every element encoding starts with a
   non-digit, so decimal runs are self-delimiting. *)

open Prelude

type value =
  | V_unit
  | V_f64_bits of int * int (* hi32, lo32, both in [0, 0xFFFF_FFFF] *)
  | V_bool of bool
  | V_str of string
  | V_tuple of value list
  | V_none
  | V_some of value
  | V_ok of value
  | V_err of value
  | V_closure (* opaque: closures compare only by outcome of calls *)

(* Panic classes the legs can observe. The message text is carried
   separately: message wording is itself a conformance surface, so it
   diffs on its own channel instead of being folded into the class. *)
type panic_class =
  | P_unwrap
  | P_expect
  | P_unwrap_err
  | P_expect_err
  | P_signal_write (* server-side panic-by-design on write shorthands *)
  | P_other

type outcome =
  | O_value of value
  | O_panic of panic_class * string (* class, message text *)
  | O_no_terminate (* leg hit its iteration/time guard *)

type observation = {
  outcome : outcome;
  rendered : string; (* rendered-text channel, empty when absent *)
  signals : (int * value) list; (* final signal states by variable id *)
}

let rec encode_value v =
  match v with
  | V_unit -> "u"
  | V_f64_bits (hi, lo) ->
      "f" ^ nat_to_string hi ^ ":" ^ nat_to_string lo ^ ";"
  | V_bool b -> if b then "b1" else "b0"
  | V_str s -> "s" ^ nat_to_string (String.length s) ^ ":" ^ s
  | V_tuple vs ->
      "t" ^ nat_to_string (len vs) ^ ":" ^ concat (map encode_value vs)
  | V_none -> "n"
  | V_some v1 -> "S" ^ encode_value v1
  | V_ok v1 -> "O" ^ encode_value v1
  | V_err v1 -> "E" ^ encode_value v1
  | V_closure -> "c"

let encode_panic_class p =
  match p with
  | P_unwrap -> "unwrap"
  | P_expect -> "expect"
  | P_unwrap_err -> "unwrap_err"
  | P_expect_err -> "expect_err"
  | P_signal_write -> "signal_write"
  | P_other -> "other"

let encode_outcome o =
  match o with
  | O_value v -> "V" ^ encode_value v
  | O_panic (p, msg) ->
      "P" ^ encode_panic_class p ^ ":"
      ^ nat_to_string (String.length msg) ^ ":" ^ msg
  | O_no_terminate -> "T"

let encode_signals signals =
  concat
    (map
       (fun kv ->
         "g" ^ nat_to_string (fst kv) ^ ":" ^ encode_value (snd kv))
       signals)

(* Full canonical form of one observation; legs are compared on this
   plus the rendered channel separately. *)
let encode obs =
  encode_outcome obs.outcome ^ "|r"
  ^ nat_to_string (String.length obs.rendered)
  ^ ":" ^ obs.rendered ^ "|" ^ encode_signals obs.signals

(* Value/observation equality across legs lives in core/differ.ml
   (M27): it needs a byte-string equality, which arrives as an
   injected closure from the shell like the float ops do. *)
