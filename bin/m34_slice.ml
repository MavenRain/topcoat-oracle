(* Internal M34 batch executor. A slice carries global indices, so its
   journal is input to the campaign joiner, not a standalone decoded run.
   Every leg, timeout, mode and draw weight comes from the shipped pipeline. *)

type failure =
  | F_usage of string
  | F_directory of string * string
  | F_exists of string
  | F_pipeline of Pipeline.failure
  | F_sample_count of int * int

type request = {
  s_dir : string;
  s_start : int;
  s_count : int;
  s_seed : int;
  s_root : string;
  s_clone : string;
}

let usage () = "m34_slice DIR START COUNT SEED ROOT CLONE"

let failure_text (f : failure) : string =
  match f with
  | F_usage text -> text
  | F_directory (path, text) -> "directory " ^ path ^ ": " ^ text
  | F_exists path -> "output directory already exists: " ^ path
  | F_pipeline f -> Pipeline.failure_text f
  | F_sample_count (expected, actual) ->
      "generator selected " ^ Prelude.nat_to_string actual ^ " samples; expected "
      ^ Prelude.nat_to_string expected

let nonnegative (text : string) : int option =
  Option.bind (int_of_string_opt text) (fun n ->
      if n >= 0 then Some n else None)

let seed_of (text : string) : int option =
  Option.bind (nonnegative text) (fun n ->
      if String.length (Prelude.nat_to_string n) <= 18 then Some n else None)

let read_args (args : string list) : (request, failure) result =
  match args with
  | [ _; dir; start; count; seed; root; clone ] ->
      Option.fold ~none:(Error (F_usage "START must be a nonnegative integer"))
        ~some:(fun first ->
          Option.fold ~none:(Error (F_usage "COUNT must be an integer from 1 to 100"))
            ~some:(fun n ->
              match () with
              | () when n < 1 || n > 100 ->
                  Error (F_usage "COUNT must be an integer from 1 to 100")
              | () when first > max_int - n ->
                  Error (F_usage "START + COUNT overflows the sample index")
              | () ->
                  Option.fold
                    ~none:(Error (F_usage "SEED must be nonnegative with at most 18 decimal digits"))
                    ~some:(fun value ->
                      Ok { s_dir = dir; s_start = first; s_count = n;
                           s_seed = value; s_root = root; s_clone = clone })
                    (seed_of seed))
            (nonnegative count))
        (nonnegative start)
  | [] | [ _ ] | [ _; _ ] | [ _; _; _ ] | [ _; _; _; _ ]
  | [ _; _; _; _; _ ] | [ _; _; _; _; _; _ ]
  | _ :: _ :: _ :: _ :: _ :: _ :: _ :: _ -> Error (F_usage (usage ()))

(** Reject dot segments before checking the four-directory dependency
    contract. These names cannot stand for one ordinary directory level. *)
let rec ancestor (levels : int) (path : string) : string option =
  if Int.equal levels 0 then Some path
  else
    let name = Filename.basename path in
    let parent = Filename.dirname path in
    if String.equal name "." || String.equal name ".."
       || String.equal parent path then None
    else ancestor (levels - 1) parent

(** The only new effect boundaries. Every Unix failure is returned with its
    path; mkdir is exclusive so even an existing empty directory is refused. *)
let realpath (path : string) : (string, failure) result =
  try Ok (Unix.realpath path) with
  | Unix.Unix_error (e, _, _) ->
      Error (F_directory (path, Unix.error_message e))

let fresh_directory (path : string) : (unit, failure) result =
  try Ok (Unix.mkdir path 0o755) with
  | Unix.Unix_error (e, _, _) ->
      if e = Unix.EEXIST then Error (F_exists path)
      else Error (F_directory (path, Unix.error_message e))

let prepare (r : request) : (request, failure) result =
  let bad_depth () = Error (F_usage "DIR must be exactly four directories below ROOT") in
  Option.fold ~none:(bad_depth ())
    ~some:(fun upper ->
      Result.bind (realpath r.s_root) (fun root ->
          Result.bind (realpath upper) (fun found ->
              match () with
              | () when not (String.equal root found) -> bad_depth ()
              | () ->
                  let parent = Filename.dirname r.s_dir in
                  Result.bind
                    (Result.map_error
                       (fun e -> F_directory (parent, Rust_leg.error_text e))
                       (Rust_leg.mkdir_parents parent))
                    (fun () ->
                      Result.bind (realpath parent) (fun resolved_parent ->
                          Option.fold ~none:(bad_depth ())
                            ~some:(fun actual_root ->
                              if not (String.equal root actual_root) then bad_depth ()
                              else
                                let dir = Filename.concat resolved_parent (Filename.basename r.s_dir) in
                                Result.map
                                  (fun () -> { r with s_root = root; s_dir = dir })
                                  (fresh_directory dir))
                            (ancestor 3 resolved_parent))))))
    (ancestor 4 r.s_dir)

let config_of (r : request) : Pipeline.config =
  { Pipeline.p_dir = r.s_dir; Pipeline.p_samples = r.s_start + r.s_count;
    Pipeline.p_seed = r.s_seed; Pipeline.p_batch = 100;
    Pipeline.p_plant = Plant.No_plant; Pipeline.p_clone = r.s_clone;
    Pipeline.p_root = r.s_root }

let run (r : request) : (string, failure) result =
  Result.bind (prepare r) (fun ready ->
      let c = config_of ready in
      let lcfg =
        { (Pipeline.legs_config c) with
          Legs.l_name = "m34batch_" ^ Prelude.nat_to_string ready.s_start }
      in
      let path = Pipeline.journal_path ready.s_dir in
      let tpath = Pipeline.trace_path ready.s_dir in
      let samples =
        Pipeline.drop ready.s_start
          (Pipeline.draw (ready.s_start + ready.s_count) ready.s_seed)
      in
      match () with
      | () when not (Int.equal (Prelude.len samples) ready.s_count) ->
          Error (F_sample_count (ready.s_count, Prelude.len samples))
      | () ->
          Result.bind
            (Result.map_error (fun e -> F_pipeline e)
               (Pipeline.fresh_open c lcfg path tpath))
            (fun _ ->
              Result.map
                (fun () ->
                  "m34 slice " ^ Prelude.nat_to_string ready.s_start ^ " count "
                  ^ Prelude.nat_to_string ready.s_count ^ "\n")
                (Result.map_error (fun e -> F_pipeline e)
                   (Pipeline.run_batches lcfg ~progress:prerr_endline ~path ~tpath
                      ~batch:100 ready.s_start samples))))

let job (args : string list) : (string, failure) result =
  Result.bind (read_args args) run

let main () : unit =
  Result.fold ~ok:print_string
    ~error:(fun f ->
      let code = match f with
        | F_usage _ -> 2
        | F_directory (_, _) | F_exists _ | F_pipeline _ | F_sample_count (_, _) -> 1
      in
      prerr_endline ("m34 slice failure: " ^ failure_text f);
      exit code)
    (job (Array.to_list Sys.argv))

let () = main ()
