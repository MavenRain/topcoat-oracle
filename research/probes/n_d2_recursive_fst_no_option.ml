let rec sum_fst xs =
  match xs with
  | [] -> 0
  | kv :: rest -> fst kv + sum_fst rest

let entrypoint _ =
  sum_fst ((1, 10) :: (2, 20) :: [])
