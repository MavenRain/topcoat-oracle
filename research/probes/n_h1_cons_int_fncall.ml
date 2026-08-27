let succ x = x + 1

let head_succ xs =
  match xs with
  | [] -> 0
  | x :: _ -> succ x

let entrypoint _ = head_succ (1 :: [])
