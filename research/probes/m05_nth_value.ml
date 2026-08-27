open Prelude

let entrypoint _ = Option.value ~default:0 (nth_opt (1 :: 2 :: []) 1)
