let rec assoc_default eq key default xs =
  match xs with
  | [] -> default
  | kv :: rest ->
      if eq (fst kv) key then snd kv else assoc_default eq key default rest

let entrypoint _ =
  assoc_default (fun a b -> a = b) 2 0 ((1, 10) :: (2, 20) :: [])
