let head_sum xs =
  match xs with
  | [] -> 0
  | kv :: _ ->
      let (a, b) = kv in
      a + b

let entrypoint _ = head_sum ((1, 2) :: [])
