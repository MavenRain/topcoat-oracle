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

let entrypoint _ =
  let xs = 1 :: 2 :: 3 :: [] in
  let n1 = Option.fold ~none:0 ~some:(fun x -> x) (nth_opt xs 1) in
  let n2 = Option.fold ~none:0 ~some:(fun x -> x) (div_opt 10 n1) in
  let s = fold (fun acc x -> acc + x) 0 (map (fun x -> x * 2) xs) in
  let l = len xs in
  n1 + n2 + s + l
