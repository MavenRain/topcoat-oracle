let head_fst xs =
  match xs with
  | [] -> 0
  | kv :: _ -> fst kv

let entrypoint _ = head_fst ((1, 2) :: [])
