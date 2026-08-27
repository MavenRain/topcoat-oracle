(* M08 consolidated probe: self-contained (no open, single file), the
   seven prelude combinators that pass omlz Core IR lowering, plus an
   entrypoint exercising them. assoc_opt is deliberately absent: a
   top-level function projecting fst/snd out of a cons-match arm
   crashes omlz lowering (UnsupportedNode) — see m08-omlz-verdict.md. *)

let rec nth_opt xs n =
  match xs with
  | [] -> None
  | x :: rest ->
      if n < 0 then None
      else if n = 0 then Some x
      else nth_opt rest (n - 1)

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

let entrypoint _ =
  let xs = 1 :: 2 :: 3 :: [] in
  let n1 = Option.fold ~none:0 ~some:(fun x -> x) (nth_opt xs 1) in
  let n2 = Option.fold ~none:0 ~some:(fun x -> x) (div_opt 10 n1) in
  let s = fold (fun acc x -> acc + x) 0 (map (fun x -> x * 2) xs) in
  let l = len (append (rev xs) xs) in
  n1 + n2 + s + l
