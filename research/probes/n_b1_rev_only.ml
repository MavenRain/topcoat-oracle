let rec fold f acc xs =
  match xs with
  | [] -> acc
  | x :: rest -> fold f (f acc x) rest

let rev xs = fold (fun acc x -> x :: acc) [] xs

let entrypoint _ =
  let xs = 1 :: 2 :: 3 :: [] in
  fold (fun n _ -> n + 1) 0 (rev xs)
