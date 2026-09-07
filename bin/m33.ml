(* m33: the allowlist CLI.
     m33 render
     m33 cite <clone-root> <repo-root>
   render prints KNOWN.md on stdout and exits 0.  cite checks every citation
   of core/known.ml under the two roots, prints one "ok <name> <path>:<lo>-<hi>"
   line per row and exits 0.  On the FIRST failure it prints NOTHING on stdout,
   names the row and the reason on stderr and exits 1.  A usage error exits 2.

   This is the only M33 module that prints and the only one that reads a file:
   core/known.ml reads nothing (ruling R5).  The whole ok text is built before
   one byte is printed, so a failed run cannot leave a half report on stdout. *)

(** Usage and source failures have separate exit codes for gate checks. *)
type failure = F_usage of string | F_cite of string

(** Keep one usage string so every rejected argument shape agrees. *)
let usage () = "m33 render | m33 cite <clone-root> <repo-root>"

(** [slurp name path] reads a file as the list of its lines, with the M31 rule
    that one empty tail piece is dropped (bin/m32.ml:12-23).  A read failure is
    a cite failure and not a usage error, because the path came from an
    entry. *)
let slurp (name : string) (path : string) : (string list, failure) result =
  Result.fold
    ~ok:(fun text -> Ok (Pipeline.journal_lines text))
    ~error:(fun e ->
      Error
        (F_cite (name ^ ": " ^ path ^ " could not be read: "
                ^ Rust_leg.error_text e)))
    (Rust_leg.read_file path)

(** Citations select a root explicitly instead of depending on the cwd. *)
let root_dir (clone : string) (repo : string) (r : Known.root) : string =
  match r with Known.R_repo -> repo | Known.R_clone -> clone

(** [range lines lo hi] is the 1 based slice [lo, hi] of [lines].  It indexes
    nothing: the line number rides the fold, so there is no List.nth and no
    array access. *)
let range (lines : string list) (lo : int) (hi : int) : string list =
  Prelude.rev
    (snd
       (Prelude.fold
          (fun acc l ->
            let n = fst acc + 1 in
            ( n,
              if n >= lo && n <= hi then l :: snd acc else snd acc ))
          (0, []) lines))

(** A quote is searched with the ONE shared matcher, Prelude.occurs, so the
    CLI and test/test_known.ml exercise the same code and no second copy can
    drift from this one. *)
let occurs (hay : string) (nee : string) : bool = Prelude.occurs hay nee

(** Use the same source location shape in every citation diagnostic. *)
let where (c : Known.cite) : string =
  c.Known.c_path ^ ":"
  ^ Prelude.nat_to_string c.Known.c_lo
  ^ "-"
  ^ Prelude.nat_to_string c.Known.c_hi

(** One row.  Six reasons to fail, in this order: the file is absent, the
    range is not a range, the range runs past the end of the file, the range
    is wider than twelve lines (a wide range makes the quote check vacuous,
    the M33 hazard list), the quote is SHORTER THAN TWELVE BYTES
    (Prelude.occurs answers true on an empty needle for every file, and a
    one-space or two-word needle occurs in almost any twelve-line window, so
    a short quote would pass vacuously), or the quote does not occur in the
    join of the range.  Twelve is below the shortest shipped quote, the
    sixteen byte "reason":"no_js" of X-no-js, and test/test_known.ml pins
    every quote at twelve bytes or more. *)
let check_row (clone : string) (repo : string) (row : string * Known.cite) :
    (string, failure) result =
  let name = fst row in
  let c = snd row in
  let path = root_dir clone repo c.Known.c_root ^ "/" ^ c.Known.c_path in
  match () with
  | () when not (Sys.file_exists path) ->
      Error (F_cite (name ^ ": there is no file at " ^ path))
  | () ->
      Result.bind (slurp name path) (fun lines ->
          let n = Prelude.len lines in
          match () with
          | () when c.Known.c_lo < 1 || c.Known.c_lo > c.Known.c_hi ->
              Error (F_cite (name ^ ": " ^ where c ^ " is not a range"))
          | () when c.Known.c_hi > n ->
              Error
                (F_cite
                   (name ^ ": " ^ where c ^ " runs past line "
                  ^ Prelude.nat_to_string n))
          | () when c.Known.c_hi - c.Known.c_lo > 11 ->
              Error
                (F_cite (name ^ ": " ^ where c ^ " is wider than twelve lines"))
          | () when String.length c.Known.c_quote < 12 ->
              Error
                (F_cite
                   (name ^ ": " ^ where c
                  ^ " carries a quote shorter than twelve bytes"))
          | () when
              not
                (occurs
                   (Prelude.joined "\n" (range lines c.Known.c_lo c.Known.c_hi))
                   c.Known.c_quote) ->
              Error
                (F_cite
                   (name ^ ": the quote is not in " ^ where c ^ ": "
                  ^ c.Known.c_quote))
          | () -> Ok (Known.ok_line name c))

(** Every row, in render order, folded through Result.bind so the FIRST
    failure wins and no later row is checked. *)
let run_cite (clone : string) (repo : string) : (string, failure) result =
  Prelude.fold
    (fun acc row ->
      Result.bind acc (fun sofar ->
          Result.map (fun line -> sofar ^ line) (check_row clone repo row)))
    (Ok "") (Known.cite_rows ())

(** Accept only complete command shapes so extra arguments cannot be ignored. *)
let job (argv : string list) : (string, failure) result =
  match argv with
  | [ _; "render" ] -> Ok (Known.render ())
  | [ _; "cite"; clone; repo ] -> run_cite clone repo
  | [] | [ _ ] -> Error (F_usage (usage ()))
  | [ _; _ ] -> Error (F_usage (usage ()))
  | [ _; _; _ ] -> Error (F_usage (usage ()))
  | _ :: _ :: _ :: _ :: _ -> Error (F_usage (usage ()))

(** Print after the complete result so failed citations leave no partial report. *)
let main () : unit =
  Result.fold
    ~ok:(fun t -> print_string t)
    ~error:(fun f ->
      match f with
      | F_usage t ->
          prerr_string ("m33 usage: " ^ t ^ "\n");
          exit 2
      | F_cite t ->
          prerr_string ("m33 cite failure: " ^ t ^ "\n");
          exit 1)
    (job (Array.to_list Sys.argv))

(** Enter through the shared result handler so every command follows the exit contract. *)
let () = main ()
