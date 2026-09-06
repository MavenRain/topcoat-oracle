(* m31: the pipeline CLI.
     m31 run <dir> --samples N --seed S [--batch B] [--plant P] [--clone C] [--root R]
     m31 replay <dir>
   It draws N samples at one seed, runs them in batches through the three
   legs, appends one journal line per sample and prints the summary.  This is
   the ONLY M31 module that prints: shell/ may not (shell/walk.ml:9-11). *)

(** What can go wrong before a summary exists. *)
type failure = F_usage of string | F_run of string

(** [usage ()] is the one line an exit 2 prints. *)
let usage () =
  "m31 run <dir> --samples N --seed S [--batch B] [--plant P] [--clone C] "
  ^ "[--root R] | m31 replay <dir>"

(** The flags of a run before the defaults are resolved.  --samples and --seed
    are options because they are REQUIRED and a missing one is a usage
    failure, not a default. *)
type opts = {
  o_samples : int option;
  o_seed : int option;
  o_batch : int;
  o_plant : Plant.t;
  o_clone : string option;
  o_root : string option;
}

(** [default_opts ()] is batch 100 and no plant (ruling R2). *)
let default_opts () : opts =
  {
    o_samples = None;
    o_seed = None;
    o_batch = 100;
    o_plant = Plant.No_plant;
    o_clone = None;
    o_root = None;
  }

(** [int_at_least lo s] is shell/cover.ml:272-273 verbatim: [int_of_string_opt]
    takes a decimal literal, the 0x, 0o and 0b prefixes and the _ separator,
    and the answer must be [lo] or more. *)
let int_at_least (lo : int) (s : string) : int option =
  Option.bind (int_of_string_opt s) (fun n ->
      match () with
      | () when n >= lo -> Some n
      | () -> None)

(** [seed_opt s] is a seed: 0 or more, in the [Cover] syntax, and at most 18
    DECIMAL digits once rendered.  The cap is not taste: the header carries
    the seed as a JSON number and core/json.ml:131 caps a digit run at
    [max_digits () = 18], so a 19 digit seed would write a journal this
    repository cannot read back. *)
let seed_opt (s : string) : int option =
  Option.bind (int_at_least 0 s) (fun n ->
      match () with
      | () when String.length (Prelude.nat_to_string n) <= 18 -> Some n
      | () -> None)

(** [read_flags o args] reads the flags left to right, so a repeated flag
    takes its LAST value, exactly as shell/cover.ml:289-306 reads its own.  A
    flag with no value and an unknown flag are both usage failures. *)
let rec read_flags (o : opts) (args : string list) : (opts, failure) result =
  match args with
  | [] -> Ok o
  | "--samples" :: v :: rest ->
      Option.fold
        ~none:(Error (F_usage ("--samples wants an integer of 1 or more: " ^ v)))
        ~some:(fun n -> read_flags { o with o_samples = Some n } rest)
        (int_at_least 1 v)
  | "--seed" :: v :: rest ->
      Option.fold
        ~none:
          (Error
             (F_usage
                ("--seed wants an integer of 0 or more with at most 18 digits: "
               ^ v)))
        ~some:(fun n -> read_flags { o with o_seed = Some n } rest)
        (seed_opt v)
  | "--batch" :: v :: rest ->
      Option.fold
        ~none:(Error (F_usage ("--batch wants an integer of 1 or more: " ^ v)))
        ~some:(fun n -> read_flags { o with o_batch = n } rest)
        (int_at_least 1 v)
  | "--plant" :: v :: rest ->
      Option.fold
        ~none:(Error (F_usage ("unknown plant " ^ v)))
        ~some:(fun p -> read_flags { o with o_plant = p } rest)
        (Plant.of_string v)
  | "--clone" :: v :: rest -> read_flags { o with o_clone = Some v } rest
  | "--root" :: v :: rest -> read_flags { o with o_root = Some v } rest
  | a :: [] -> Error (F_usage ("the flag " ^ a ^ " has no value"))
  | a :: _ :: _ -> Error (F_usage ("unknown flag " ^ a))

(** [config_of dir o] resolves the defaults.  The root is four dirnames above
    <dir> and the clone is root ^ "/../topcoat", both through the SHIPPED
    rule of shell/walk.ml:36-44, so m31 and m29 read the same tree from the
    same directory (ruling R2).  --root and --clone are independent, exactly
    as shell/walk.ml:48-64 keeps them: --root alone does not move the clone. *)
let config_of (dir : string) (o : opts) : (Pipeline.config, failure) result =
  let d = Walk.defaults dir in
  Option.fold
    ~none:(Error (F_usage "run needs --samples N"))
    ~some:(fun n ->
      Option.fold
        ~none:(Error (F_usage "run needs --seed S"))
        ~some:(fun s ->
          Ok
            {
              Pipeline.p_dir = dir;
              Pipeline.p_samples = n;
              Pipeline.p_seed = s;
              Pipeline.p_batch = o.o_batch;
              Pipeline.p_plant = o.o_plant;
              Pipeline.p_clone =
                Option.fold ~none:d.Walk.fl_clone ~some:(fun v -> v) o.o_clone;
              Pipeline.p_root =
                Option.fold ~none:d.Walk.fl_root ~some:(fun v -> v) o.o_root;
            })
        o.o_seed)
    o.o_samples

(** [progress t] prints one batch line on STDERR.  Stdout carries the summary
    and nothing else (ruling R7);  the gate compares run stdout with replay
    stdout, so one stray stdout byte is a red gate.  [prerr_endline] flushes
    stderr, so the line is on disk before the next batch starts and a killed
    run still names the batch it died in (ruling F5). *)
let progress (t : string) : unit = prerr_endline t

(** [job argv] is the whole CLI as a value: the summary text, or a named
    failure.  Nothing here prints and nothing here exits. *)
let job (argv : string list) : (string, failure) result =
  match argv with
  | _ :: "run" :: dir :: rest ->
      Result.bind (read_flags (default_opts ()) rest) (fun o ->
          Result.bind (config_of dir o) (fun c ->
              Result.map_error
                (fun f -> F_run (Pipeline.failure_text f))
                (Pipeline.run ~progress c)))
  | [ _; "replay"; dir ] ->
      Result.map_error
        (fun f -> F_run (Pipeline.failure_text f))
        (Pipeline.replay ~dir)
  | [] | [ _ ] | [ _; _ ] | _ :: _ :: _ :: _ -> Error (F_usage (usage ()))

(** [main ()] prints the summary on stdout and exits 0, or names the failure
    on stderr and exits 1 for a run failure and 2 for a usage failure
    (ruling R2). *)
let main () : unit =
  Result.fold
    ~ok:(fun t -> print_string t)
    ~error:(fun f ->
      match f with
      | F_usage t ->
          prerr_string ("m31 usage: " ^ t ^ "\n");
          exit 2
      | F_run t ->
          prerr_string ("m31 failure: " ^ t ^ "\n");
          exit 1)
    (job (Array.to_list Sys.argv))

let () = main ()
