open Prelude

let entrypoint _ = Option.fold ~none:0 ~some:(fun x -> x) (nth_opt (1 :: 2 :: []) 1)
