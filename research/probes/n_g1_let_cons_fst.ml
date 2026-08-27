let entrypoint _ =
  let xs = (1, 2) :: [] in
  match xs with
  | [] -> 0
  | kv :: _ -> fst kv
