(* M08 probe: whole-program harness so `omlz check` (which requires an
   entrypoint and runs region inference on the whole program) exercises
   every combinator in core/prelude.ml. The sibling prelude.ml here is
   a byte-for-byte copy of core/prelude.ml, refreshed by the gate. *)

open Prelude

let entrypoint _ =
  let xs = 1 :: 2 :: 3 :: [] in
  let n1 = Option.fold ~none:0 ~some:(fun x -> x) (nth_opt xs 1) in
  let n2 = Option.fold ~none:0 ~some:(fun x -> x) (div_opt 10 n1) in
  let s = fold (fun acc x -> acc + x) 0 (map (fun x -> x * 2) xs) in
  let l = len (append (rev xs) xs) in
  let kvs = (1, 10) :: (2, 20) :: [] in
  let v =
    Option.fold ~none:0 ~some:(fun x -> x)
      (assoc_opt (fun a b -> a = b) 2 kvs)
  in
  n1 + n2 + s + l + v
