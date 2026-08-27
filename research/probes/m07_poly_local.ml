let entrypoint _ =
  let id x = x in
  let a = id 1 in
  let b = if id true then 1 else 0 in
  a + b
