(* Total combinators for the dual-compiled core (ZxCaml subset).
   Positional access and division in core/ go through these wrappers
   only. Option/Result handling uses the stdlib combinator surface
   (map, bind, fold, value), which both toolchains provide: stock
   OCaml via Stdlib, omlz via its stdlib/core.ml. *)

let rec nth_opt xs n =
  match xs with
  | [] -> None
  | x :: rest ->
      if n < 0 then None
      else if n = 0 then Some x
      else nth_opt rest (n - 1)

(* Total division: the divisor is tested on the same line. *)
let div_opt a b = if b = 0 then None else Some (a / b) (* @total-accessor *)

let rec fold f acc xs =
  match xs with
  | [] -> acc
  | x :: rest -> fold f (f acc x) rest

let rec map f xs =
  match xs with
  | [] -> []
  | x :: rest -> f x :: map f rest

let len xs = fold (fun n _ -> n + 1) 0 xs

let rev xs = fold (fun acc x -> x :: acc) [] xs

let rec append xs ys =
  match xs with
  | [] -> ys
  | x :: rest -> x :: append rest ys

(* Element-wise list equality with a caller-supplied equality. *)
let rec list_eq eq xs ys =
  match xs with
  | [] -> (match ys with [] -> true | _ :: _ -> false)
  | x :: xs' ->
      (match ys with [] -> false | y :: ys' -> eq x y && list_eq eq xs' ys')

let concat parts = fold (fun acc s -> acc ^ s) "" parts

(* Separator-joined concatenation; empty list renders empty. *)
let joined sep parts =
  match parts with
  | [] -> ""
  | p :: rest -> p ^ concat (map (fun q -> sep ^ q) rest)

let digit_str d =
  match d with
  | 0 -> "0" | 1 -> "1" | 2 -> "2" | 3 -> "3" | 4 -> "4"
  | 5 -> "5" | 6 -> "6" | 7 -> "7" | 8 -> "8" | 9 -> "9"
  | _ -> ""

(* Decimal rendering of a non-negative int; negative inputs clamp to
   "0" (callers in core/ only pass 32-bit halves, always >= 0). *)
let nat_to_string n =
  if n <= 0 then "0"
  else
    let rec go m acc =
      if m = 0 then acc
      else go (m / 10) (digit_str (m mod 10) ^ acc) (* @total-accessor *)
    in
    go n ""

(* Association-list lookup with a caller-supplied key equality, so no
   polymorphic compare is needed anywhere in core/. The head pair is
   taken apart with fst/snd: a tuple pattern nested in a cons pattern
   is outside the ZxCaml subset (omlz UnsupportedPattern, M08 probe). *)
let rec assoc_opt eq key xs =
  match xs with
  | [] -> None
  | kv :: rest -> if eq (fst kv) key then Some (snd kv) else assoc_opt eq key rest
