let rec loop n kv =
  if n = 0 then fst kv else loop (n - 1) kv

let entrypoint _ = loop 3 (1, 2)
