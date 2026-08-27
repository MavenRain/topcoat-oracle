let rec fold f acc xs =
  match xs with
  | [] -> acc
  | x :: rest -> fold f (f acc x) rest

let rec append xs ys =
  match xs with
  | [] -> ys
  | x :: rest -> x :: append rest ys

let entrypoint _ =
  let xs = 1 :: 2 :: 3 :: [] in
  fold (fun n _ -> n + 1) 0 (append xs xs)
