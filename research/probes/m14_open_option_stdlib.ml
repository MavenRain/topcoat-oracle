open Option

let entrypoint _ = fold ~none:0 ~some:(fun x -> x) (Some 1)
