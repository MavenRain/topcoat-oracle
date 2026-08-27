let rec assoc_opt eq key xs =
  match xs with
  | [] -> None
  | kv :: rest -> if eq (fst kv) key then Some (snd kv) else assoc_opt eq key rest

let entrypoint _ =
  let kvs = (1, 10) :: (2, 20) :: [] in
  Option.fold ~none:0 ~some:(fun x -> x)
    (assoc_opt (fun a b -> a = b) 2 kvs)
