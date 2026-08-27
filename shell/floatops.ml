(* IEEE-754 binary64 ops over (hi32, lo32) bit pairs (M15). Shell
   side: full OCaml, real floats. Rendering matches the rustc probe
   recorded in research/m13-rust-render-probe.md:
   - display = Rust `Display`: shortest round-trip digits, ALWAYS
     positional (1e300 prints as 301 digits), integral values drop
     the point ("1"), "inf"/"-inf"/"NaN"/"-0".
   - debug = Rust `Debug`: same digits; positional with a forced ".0"
     when the decimal exponent is in [-4, 15], exponential otherwise
     ("1e16", "5e-324", "1.2345678901234568e17"; no "+" sign).
   - literal = f64-literal token for the printer: Debug form is
     always a valid (possibly minus-prefixed) float literal, while
     Display form of integral values would be an integer literal,
     which expr! rejects. NaN/infinities have no literal spelling;
     their output here fails under expr! by design (generator never
     emits them).
   Shortest-digit search uses correctly-rounded %.*e output; where
   several same-length decimals round-trip, the tie choice could in
   principle differ from Rust's algorithm - the differential runs
   themselves gate that residue. *)

let to_float hi lo =
  Int64.float_of_bits
    (Int64.logor (Int64.shift_left (Int64.of_int hi) 32) (Int64.of_int lo))

let of_float f =
  let b = Int64.bits_of_float f in
  ( Int64.to_int (Int64.shift_right_logical b 32),
    Int64.to_int (Int64.logand b 0xFFFFFFFFL) )

let lift2 op h1 l1 h2 l2 = of_float (op (to_float h1 l1) (to_float h2 l2))

let liftb (op : float -> float -> bool) h1 l1 h2 l2 =
  op (to_float h1 l1) (to_float h2 l2)

let f_add = lift2 ( +. )

let f_sub = lift2 ( -. )

let f_mul = lift2 ( *. )

let f_div = lift2 ( /. )

let f_neg hi lo = of_float (-.to_float hi lo)

(* Monomorphic float comparisons compile to IEEE compares: NaN is
   unordered (all four orderings false, = false), -0 equals 0. *)
let f_eq = liftb (fun (a : float) b -> a = b)

let f_lt = liftb (fun (a : float) b -> a < b)

let f_le = liftb (fun (a : float) b -> a <= b)

let f_gt = liftb (fun (a : float) b -> a > b)

let f_ge = liftb (fun (a : float) b -> a >= b)

let f_of_int n = of_float (float_of_int n)

let sign_bit hi = hi land 0x80000000 <> 0

let roundtrips target s =
  Option.fold ~none:false
    ~some:(fun v -> Int64.equal (Int64.bits_of_float v) target)
    (float_of_string_opt s)

(* Shortest correctly-rounded decimal of |f| (finite, nonzero) as
   (significant digits, decimal exponent): value = d1.d2...dn E e10.
   The first precision that round-trips is minimal, so the last digit
   is never a redundant zero. 17 significant digits always round-trip
   for binary64, so the search is total (the p cap is unreachable). *)
let shortest f =
  let abs_f = Float.abs f in
  let target = Int64.bits_of_float abs_f in
  let rec search p =
    let s = Printf.sprintf "%.*e" p abs_f in
    if roundtrips target s || p >= 16 then s else search (p + 1)
  in
  match String.split_on_char 'e' (search 0) with
  | mant :: exp :: [] ->
      ( String.concat "" (String.split_on_char '.' mant),
        Option.value ~default:0 (int_of_string_opt exp) )
  | _ -> ("0", 0) (* unreachable: %e output always carries an 'e' *)

(* digits is nonempty and dot-free; e10 branches keep every range
   inside [0, n]. *)
let positional digits e10 =
  let n = String.length digits in
  if e10 >= n - 1 then digits ^ String.make (e10 - (n - 1)) '0'
  else if e10 >= 0 then
    String.sub digits 0 (e10 + 1) ^ "." ^ String.sub digits (e10 + 1) (n - e10 - 1) (* @total-accessor *)
  else "0." ^ String.make (-e10 - 1) '0' ^ digits

let exponential digits e10 =
  let n = String.length digits in
  (if n <= 1 then digits
   else String.sub digits 0 1 ^ "." ^ String.sub digits 1 (n - 1) (* @total-accessor *))
  ^ "e"
  ^ string_of_int e10

let f_display hi lo =
  let f = to_float hi lo in
  match Float.classify_float f with
  | FP_nan -> "NaN"
  | FP_infinite -> if sign_bit hi then "-inf" else "inf"
  | FP_zero -> if sign_bit hi then "-0" else "0"
  | FP_normal | FP_subnormal ->
      let d = shortest f in
      (if sign_bit hi then "-" else "") ^ positional (fst d) (snd d)

let f_debug hi lo =
  let f = to_float hi lo in
  match Float.classify_float f with
  | FP_nan -> "NaN"
  | FP_infinite -> if sign_bit hi then "-inf" else "inf"
  | FP_zero -> if sign_bit hi then "-0.0" else "0.0"
  | FP_normal | FP_subnormal ->
      let d = shortest f in
      let e10 = snd d in
      let body =
        if e10 >= -4 && e10 <= 15 then
          let p = positional (fst d) e10 in
          if String.contains p '.' then p else p ^ ".0"
        else exponential (fst d) e10
      in
      (if sign_bit hi then "-" else "") ^ body

let f_literal hi lo =
  let f = to_float hi lo in
  match Float.classify_float f with
  | FP_nan -> "f64::NAN"
  | FP_infinite ->
      if sign_bit hi then "-f64::INFINITY" else "f64::INFINITY"
  | FP_zero | FP_normal | FP_subnormal -> f_debug hi lo
