open Prelude

let entrypoint _ =
  if Option.is_some (nth_opt (1 :: 2 :: []) 1) then 1 else 0
