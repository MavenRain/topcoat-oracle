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

(* Association-list lookup with a caller-supplied key equality, so no
   polymorphic compare is needed anywhere in core/. The head pair is
   taken apart with fst/snd: a tuple pattern nested in a cons pattern
   is outside the ZxCaml subset (omlz UnsupportedPattern, M08 probe). *)
let rec assoc_opt eq key xs =
  match xs with
  | [] -> None
  | kv :: rest -> if eq (fst kv) key then Some (snd kv) else assoc_opt eq key rest
