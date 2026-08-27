let entrypoint _ = Option.fold ~none:0 ~some:(fun x -> x) (Some 1)
