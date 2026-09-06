(* m32: the correspondence gate CLI.
     m32 check <dir>
   It reads <dir>/journal.jsonl and <dir>/trace.jsonl, checks both directions
   and prints one report line.  Exit 0 when every line corresponds, 1 on the
   first failure, 2 on a usage error or a missing file.  This is the ONLY M32
   module that prints: shell/ may not (shell/walk.ml:9-11). *)

type failure = F_usage of string | F_check of string

let usage () = "m32 check <dir>"

(** [slurp path] reads a file as the list of its lines, with the M31 rule that
    one empty tail piece is dropped (shell/pipeline.ml:122-132). *)
let slurp (path : string) : (string list, failure) result =
  match () with
  | () when not (Sys.file_exists path) ->
      Error (F_usage ("there is no file at " ^ path))
  | () ->
      Result.fold
        ~ok:(fun text -> Ok (Pipeline.journal_lines text))
        ~error:(fun e ->
          Error (F_usage (path ^ " could not be read: " ^ Rust_leg.error_text e)))
        (Rust_leg.read_file path)

(** [journal_line e] is the 1 based line a journal decode failure names.  The
    number is inside [Journal.error_text] as well, so the "line N:" prefix
    reads it off the constructor instead of printing a constant that
    disagrees with the text.  An empty file has no line of its own and names
    line 1.  The match is exhaustive over the seven constructors of
    core/journal.ml:40-47 and carries no wildcard arm. *)
let journal_line (e : Journal.error) : int =
  match e with
  | Journal.E_empty -> 1
  | Journal.E_parse (n, _) -> n
  | Journal.E_not_object n -> n
  | Journal.E_missing (n, _) -> n
  | Journal.E_type (n, _) -> n
  | Journal.E_version (n, _) -> n
  | Journal.E_index (n, _, _) -> n

(** [line_text f] is the "line N: why" half of the failure line. *)
let line_text (f : Correspond.failure) : string =
  "line "
  ^ Prelude.nat_to_string (Correspond.failure_line f)
  ^ ": " ^ Correspond.failure_text f

let run_check (dir : string) : (string, failure) result =
  Result.bind (slurp (Pipeline.journal_path dir)) (fun jtexts ->
      Result.bind (slurp (Pipeline.trace_path dir)) (fun ttexts ->
          Result.bind
            (Result.map_error
               (fun e ->
                 F_check
                   ("line "
                   ^ Prelude.nat_to_string (journal_line e)
                   ^ ": the journal does not decode: "
                   ^ Journal.error_text e))
               (Journal.decode_journal jtexts))
            (fun jhl ->
              Result.bind
                (Result.map_error (fun f -> F_check (line_text f))
                   (Correspond.decode_trace ttexts))
                (fun thl ->
                  Result.fold
                    ~ok:(fun r -> Ok (Correspond.report_text ~dir r))
                    ~error:(fun f -> Error (F_check (line_text f)))
                    (Correspond.check (fst jhl) (snd jhl) (fst thl) (snd thl))))))

let job (argv : string list) : (string, failure) result =
  match argv with
  | [ _; "check"; dir ] -> run_check dir
  | [] | [ _ ] | [ _; _ ] | _ :: _ :: _ :: _ :: _ -> Error (F_usage (usage ()))
  | [ _; _; _ ] -> Error (F_usage (usage ()))

let main () : unit =
  Result.fold
    ~ok:(fun t -> print_string t)
    ~error:(fun f ->
      match f with
      | F_usage t ->
          prerr_string ("m32 usage: " ^ t ^ "\n");
          exit 2
      | F_check t ->
          prerr_string ("m32 failure: " ^ t ^ "\n");
          exit 1)
    (job (Array.to_list Sys.argv))

let () = main ()
