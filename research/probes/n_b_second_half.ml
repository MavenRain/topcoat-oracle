let rec fold f acc xs =
  match xs with
  | [] -> acc
  | x :: rest -> fold f (f acc x) rest

let rev xs = fold (fun acc x -> x :: acc) [] xs

let rec append xs ys =
  match xs with
  | [] -> ys
  | x :: rest -> x :: append rest ys

let rec assoc_opt eq key xs =
  match xs with
  | [] -> None
  | kv :: rest -> if eq (fst kv) key then Some (snd kv) else assoc_opt eq key rest

let entrypoint _ =
  let xs = 1 :: 2 :: 3 :: [] in
  let l = fold (fun n _ -> n + 1) 0 (append (rev xs) xs) in
  let kvs = (1, 10) :: (2, 20) :: [] in
  let v =
    Option.fold ~none:0 ~some:(fun x -> x)
      (assoc_opt (fun a b -> a = b) 2 kvs)
  in
  l + v
