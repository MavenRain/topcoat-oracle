let rec fold f acc xs =
  match xs with
  | [] -> acc
  | x :: rest -> fold f (f acc x) rest

let len xs = fold (fun n _ -> n + 1) 0 xs

let entrypoint _ = len (1 :: 2 :: 3 :: [])
