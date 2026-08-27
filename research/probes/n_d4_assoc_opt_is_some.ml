let rec assoc_opt eq key xs =
  match xs with
  | [] -> None
  | kv :: rest -> if eq (fst kv) key then Some (snd kv) else assoc_opt eq key rest

let entrypoint _ =
  if Option.is_some (assoc_opt (fun a b -> a = b) 2 ((1, 10) :: (2, 20) :: [])) then 1 else 0
