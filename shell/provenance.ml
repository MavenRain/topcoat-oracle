(** Provenance captures the two repository shas a repro file records.  It
    spawns [git] through the [Rust_leg] primitives rather than adding a second
    way to run a process. *)

(** What can go wrong.  The three failing primitives answer a
    [Rust_leg.error], whose text is carried through rather than thrown away,
    so a red gate reads the path and the errno message. *)
type error =
  | Pv_spawn of string * string  (** the name, then the Rust_leg error text *)
  | Pv_exit of string * int  (** git answered a non zero code *)
  | Pv_read of string * string  (** the captured stdout could not be read *)
  | Pv_shape of string  (** the line is not 40 lowercase hex digits *)

(** [error_text e] names one failure. *)
let error_text e =
  match e with
  | Pv_spawn (n, m) -> "the git spawn for " ^ n ^ " failed: " ^ m
  | Pv_exit (n, c) ->
      "git rev-parse for " ^ n ^ " answered exit " ^ string_of_int c
  | Pv_read (n, m) -> "the captured sha of " ^ n ^ " could not be read: " ^ m
  | Pv_shape t -> t

(** [read_sha cfg ~out ~name ~repo] answers the HEAD sha of [repo].  The raw
    stdout is kept at [out]/sha/[name].sha and the raw stderr at
    [out]/sha/[name].err, so a red gate has the bytes to read.  The shape is
    judged by [Repro.sha_of_line] and by nothing else, so the core test and
    this module cannot drift apart. *)
let read_sha (cfg : Rust_leg.config) ~out ~name ~repo =
  let d = out ^ "/sha" in
  let o = d ^ "/" ^ name ^ ".sha" in
  let e = d ^ "/" ^ name ^ ".err" in
  Result.bind
    (Result.map_error
       (fun x -> Pv_spawn (name, Rust_leg.error_text x))
       (Rust_leg.mkdir_one d))
    (fun () ->
      Result.bind
        (Result.map_error
           (fun x -> Pv_spawn (name, Rust_leg.error_text x))
           (Rust_leg.spawn_once cfg
              ~argv:[ "git"; "-C"; repo; "rev-parse"; "HEAD" ]
              ~jsonl:o ~err:e ~append:false))
        (fun code ->
          if Int.equal code 0 then
            Result.bind
              (Result.map_error
                 (fun x -> Pv_read (name, Rust_leg.error_text x))
                 (Rust_leg.read_file o))
              (fun l ->
                Result.map_error (fun t -> Pv_shape t) (Repro.sha_of_line l))
          else Error (Pv_exit (name, code))))
