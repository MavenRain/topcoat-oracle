open Prelude

let entrypoint _ =
  Option.value ~default:0 (assoc_opt (fun a b -> a = b) 2 ((1, 10) :: (2, 20) :: []))
