(* M26 js wire decoder (DESIGN.md M26, spec section 3).  One JSONL line
   from driver-js/lib/line.mjs becomes a sum type.  The js line is NOT
   the Rust line:  it has no js_hex and no js_consistent, its signal
   entries have two keys and not three, and it carries three outcomes
   the Rust wire never carries (js_error, skipped and driver_error).

   The decoder is strict.  The key set per outcome is EXACT, so a
   missing key, an extra key or a wrong shape is a named error that
   carries the key.  Key ORDER is free.  Nothing is coerced, nothing is
   repaired and nothing wraps.

   core/wire.ml is reused and never edited.  Wire.decode_value,
   Wire.check_keys, Wire.require, Wire.get_int, Wire.get_hex,
   Wire.parse_class, Wire.get_hint and Wire.get_js_form all apply to a
   js line.  Wire.get_signals does not:  Wire.signal_keys () demands
   debug_hex (core/wire.ml:193), which a js signal entry never carries,
   so this module builds its own two-key signal decoder.  Relaxing the
   Rust decoder would weaken the wire the M24 gate rests on.

   Every key-set table is a FUNCTION of (), because zxlint trap2
   rejects a helper that reads a top-level constant.  core/wire.ml:180
   says the same thing about its own tables. *)

(* The js line's two extras.  js_form and hint are Rust-side facts the
   driver COPIES from the input line and never recomputes
   (m25_verdict.sh:46-47), so they ride beside the observation exactly
   as Wire's extras do, and they never fold into Obs.observation. *)
type jextras = { j_form : Wire.js_form; j_hint : Wire.hint }

type decoded =
  | Jl_obs of Obs.observation * jextras
  | Jl_js_error of string * string (* decoded name bytes, decoded msg bytes *)
  | Jl_skipped of string (* the reason word *)
  | Jl_driver_error of string * string (* the error word, decoded detail bytes *)
  | Jl_lossy of string (* the key that carried utf16 code units *)

type wjerror =
  | Wj_wire of Wire.werror (* every shape core/wire.ml already names *)
  | Wj_unknown_outcome of string (* the six js outcomes, and no others *)
  | Wj_unknown_reason of string (* skipped carries "no_js" and nothing else *)
  | Wj_signal_shape of string (* a signals entry that is not a two-key object *)
  | Wj_bad_case of int (* a negative case index *)

let wjerror_name (e : wjerror) : string =
  match e with
  | Wj_wire w -> "wire:" ^ Wire.werror_name w
  | Wj_unknown_outcome _ -> "unknown_outcome"
  | Wj_unknown_reason _ -> "unknown_reason"
  | Wj_signal_shape _ -> "signal_shape"
  | Wj_bad_case _ -> "bad_case"

(* The decoded line carries its case index beside the sum, so a row
   printer can name the case for every arm, the lossy one included. *)
type jline = { jl_case : int; jl_body : decoded }

(* Wj_wire wraps a Wire.werror wherever the shape is the same:  a
   missing key, an extra key, a bad shape, an unknown tag, an unknown
   class, an unknown hint, an unknown js_form, an out-of-range half, an
   odd hex run and a bad hex byte are all named there already. *)
let lift (r : ('a, Wire.werror) result) : ('a, wjerror) result =
  Result.map_error (fun w -> Wj_wire w) r

(* ---------- the exact key sets (spec 3.2) ---------- *)

(* Copied from the OUT table of driver-js/lib/line.mjs:314-338.  Note
   what is absent against Wire.value_keys () and Wire.panic_keys ():  no
   js_hex and no js_consistent, because both are Rust-side facts.  A js
   line that carried either is W_extra_key, which is the right answer. *)
let value_keys () =
  [ "case"; "outcome"; "value"; "rendered_hex"; "js_form"; "hint"; "signals" ]

let panic_keys () =
  [ "case"; "outcome"; "class"; "msg_hex"; "js_form"; "hint"; "signals" ]

let js_error_keys () =
  [ "case"; "outcome"; "name_hex"; "msg_hex"; "js_form"; "hint"; "signals" ]

let no_terminate_keys () = [ "case"; "outcome"; "hint" ]
let skipped_keys () = [ "case"; "outcome"; "reason" ]
let driver_error_keys () = [ "case"; "outcome"; "error"; "detail_hex" ]
let signal_keys () = [ "id"; "value" ]

(* ---------- the signals (spec 3.3) ---------- *)

(* Two keys, id and value.  A THREE-key entry that carries debug_hex is
   rejected with W_extra_key "debug_hex", which is the guard that this
   decoder is not silently the Rust one. *)
let decode_signal (jv : Json.jvalue) : (int * Obs.value, wjerror) result =
  match jv with
  | Json.J_obj pairs ->
      Result.bind (lift (Wire.check_keys pairs (signal_keys ()))) (fun () ->
          Result.bind (lift (Wire.get_int "id" pairs)) (fun id ->
              Result.bind (lift (Wire.require pairs "value")) (fun v ->
                  Result.map (fun dv -> (id, dv)) (lift (Wire.decode_value v)))))
  | Json.J_null | Json.J_true | Json.J_false | Json.J_int _ | Json.J_str _
  | Json.J_arr _ ->
      Error (Wj_signal_shape "signals")

(* Wire order is kept.  No sorting anywhere, as core/wire.ml:363 says. *)
let rec decode_signals (items : Json.jvalue list) :
    ((int * Obs.value) list, wjerror) result =
  match items with
  | [] -> Ok []
  | jv :: rest ->
      Result.bind (decode_signal jv) (fun one ->
          Result.map (fun more -> one :: more) (decode_signals rest))

let get_signals (pairs : (string * Json.jvalue) list) :
    ((int * Obs.value) list, wjerror) result =
  Result.bind (lift (Wire.get_arr "signals" pairs)) decode_signals

(* ---------- lossy detection (spec 3.5) ---------- *)

(* The CLOSED set of key names that mark UTF-16 units.  It is closed
   because textField has exactly three bases (rendered, msg, name), the
   value-level key is utf16_hex, and lossyField writes the one marker.
   A function, not a constant: zxlint trap2. *)
let lossy_keys () =
  [ "lossy"; "utf16_hex"; "rendered_utf16_hex"; "msg_utf16_hex";
    "name_utf16_hex" ]

let rec key_in (keys : string list) (k : string) : bool =
  match keys with
  | [] -> false
  | k1 :: rest -> String.equal k k1 || key_in rest k

(* The object's OWN keys decide, in wire order, so a lossy value object
   {"t":"str","utf16_hex":"..","lossy":true} names utf16_hex and not the
   marker that follows it.  Section 9 group 5 pins that. *)
let rec first_lossy_key (keys : string list)
    (pairs : (string * Json.jvalue) list) : string option =
  match pairs with
  | [] -> None
  | p :: rest -> (
      match () with
      | () when key_in keys (fst p) -> Some (fst p)
      | () -> first_lossy_key keys rest)

let rec lossy_in (v : Json.jvalue) : string option =
  match v with
  | Json.J_obj pairs ->
      Option.fold
        ~none:(lossy_in_pairs pairs)
        ~some:(fun k -> Some k)
        (first_lossy_key (lossy_keys ()) pairs)
  | Json.J_arr items -> lossy_in_items items
  | Json.J_null | Json.J_true | Json.J_false | Json.J_int _ | Json.J_str _ ->
      None

and lossy_in_pairs (pairs : (string * Json.jvalue) list) : string option =
  match pairs with
  | [] -> None
  | p :: rest ->
      Option.fold
        ~none:(lossy_in_pairs rest)
        ~some:(fun k -> Some k)
        (lossy_in (snd p))

and lossy_in_items (items : Json.jvalue list) : string option =
  match items with
  | [] -> None
  | v :: rest ->
      Option.fold ~none:(lossy_in_items rest) ~some:(fun k -> Some k) (lossy_in v)

(* ---------- the outcome arms (spec 3.4) ---------- *)

let decode_value_line (pairs : (string * Json.jvalue) list) :
    (decoded, wjerror) result =
  Result.bind (lift (Wire.check_keys pairs (value_keys ()))) (fun () ->
      Result.bind (lift (Wire.require pairs "value")) (fun jv ->
          Result.bind (lift (Wire.decode_value jv)) (fun v ->
              Result.bind (lift (Wire.get_hex "rendered_hex" pairs))
                (fun rendered ->
                  Result.bind (lift (Wire.get_js_form pairs)) (fun form ->
                      Result.bind (lift (Wire.get_hint pairs)) (fun hint ->
                          Result.map
                            (fun signals ->
                              Jl_obs
                                ( {
                                    Obs.outcome = Obs.O_value v;
                                    rendered;
                                    signals;
                                  },
                                  { j_form = form; j_hint = hint } ))
                            (get_signals pairs)))))))

let decode_panic_line (pairs : (string * Json.jvalue) list) :
    (decoded, wjerror) result =
  Result.bind (lift (Wire.check_keys pairs (panic_keys ()))) (fun () ->
      Result.bind
        (lift (Result.bind (Wire.get_str "class" pairs) Wire.parse_class))
        (fun cls ->
          Result.bind (lift (Wire.get_hex "msg_hex" pairs)) (fun msg ->
              Result.bind (lift (Wire.get_js_form pairs)) (fun form ->
                  Result.bind (lift (Wire.get_hint pairs)) (fun hint ->
                      Result.map
                        (fun signals ->
                          Jl_obs
                            ( {
                                Obs.outcome = Obs.O_panic (cls, msg);
                                rendered = "";
                                signals;
                              },
                              { j_form = form; j_hint = hint } ))
                        (get_signals pairs))))))

(* A no_terminate line carries hint and nothing else, so its js_form is
   the explicit Jf_absent.  core/wire.ml:445-458 fills the same value on
   the Rust no-terminate line, and its comment at :442-444 calls that
   "the harness defaults for a line that carries none of them". *)
let decode_no_terminate_line (pairs : (string * Json.jvalue) list) :
    (decoded, wjerror) result =
  Result.bind (lift (Wire.check_keys pairs (no_terminate_keys ()))) (fun () ->
      Result.map
        (fun hint ->
          Jl_obs
            ( { Obs.outcome = Obs.O_no_terminate; rendered = ""; signals = [] },
              { j_form = Wire.Jf_absent; j_hint = hint } ))
        (lift (Wire.get_hint pairs)))

(* A throw that is not a Panic has no observation to attach js_form,
   hint and signals to, so the key check reads them and the decode
   discards them. *)
let decode_js_error_line (pairs : (string * Json.jvalue) list) :
    (decoded, wjerror) result =
  Result.bind (lift (Wire.check_keys pairs (js_error_keys ()))) (fun () ->
      Result.bind (lift (Wire.get_hex "name_hex" pairs)) (fun name ->
          Result.map
            (fun msg -> Jl_js_error (name, msg))
            (lift (Wire.get_hex "msg_hex" pairs))))

(* no_js is the only reason the driver writes
   (driver-js/lib/line.mjs:336-337, where the reason is a literal). *)
let decode_skipped_line (pairs : (string * Json.jvalue) list) :
    (decoded, wjerror) result =
  Result.bind (lift (Wire.check_keys pairs (skipped_keys ()))) (fun () ->
      Result.bind (lift (Wire.get_str "reason" pairs)) (fun reason ->
          match () with
          | () when String.equal reason "no_js" -> Ok (Jl_skipped reason)
          | () -> Error (Wj_unknown_reason reason)))

let decode_driver_error_line (pairs : (string * Json.jvalue) list) :
    (decoded, wjerror) result =
  Result.bind (lift (Wire.check_keys pairs (driver_error_keys ()))) (fun () ->
      Result.bind (lift (Wire.get_str "error" pairs)) (fun word ->
          Result.map
            (fun detail -> Jl_driver_error (word, detail))
            (lift (Wire.get_hex "detail_hex" pairs))))

let dispatch (pairs : (string * Json.jvalue) list) : (decoded, wjerror) result =
  Result.bind (lift (Wire.get_str "outcome" pairs)) (fun o ->
      match () with
      | () when String.equal o "value" -> decode_value_line pairs
      | () when String.equal o "panic" -> decode_panic_line pairs
      | () when String.equal o "no_terminate" -> decode_no_terminate_line pairs
      | () when String.equal o "js_error" -> decode_js_error_line pairs
      | () when String.equal o "skipped" -> decode_skipped_line pairs
      | () when String.equal o "driver_error" -> decode_driver_error_line pairs
      | () -> Error (Wj_unknown_outcome o))

(* Option.fold's ~none arm is EAGER, so both arms are functions of ()
   and only the chosen one runs.  That is what keeps the outcome
   dispatch, and with it Wire.decode_value, from running on a lossy
   line.  A lossy value object would otherwise report
   W_missing_key "hex", which names the wrong thing. *)
let dispatch_or_lossy (pairs : (string * Json.jvalue) list) :
    (decoded, wjerror) result =
  Option.fold
    ~none:(fun () -> dispatch pairs)
    ~some:(fun k () -> Ok (Jl_lossy k))
    (lossy_in (Json.J_obj pairs))
    ()

(* The case index is read FIRST, so a lossy line still names its case. *)
let get_case (pairs : (string * Json.jvalue) list) : (int, wjerror) result =
  Result.bind (lift (Wire.get_int "case" pairs)) (fun n ->
      match () with () when n < 0 -> Error (Wj_bad_case n) | () -> Ok n)

let decode_line (line : string) : (jline, wjerror) result =
  Result.bind
    (lift (Result.map_error (fun e -> Wire.W_json e) (Json.parse line)))
    (fun jv ->
      match jv with
      | Json.J_obj pairs ->
          Result.bind (get_case pairs) (fun case ->
              Result.map
                (fun body -> { jl_case = case; jl_body = body })
                (dispatch_or_lossy pairs))
      | Json.J_null | Json.J_true | Json.J_false | Json.J_int _ | Json.J_str _
      | Json.J_arr _ ->
          Error (Wj_wire Wire.W_not_object))
