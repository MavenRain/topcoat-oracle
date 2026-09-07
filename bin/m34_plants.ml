(* M34 corpus-backed planted oracle command.  All output is delayed until both
   controls and both mutations succeed, so a failed command prints no report. *)

type failure = F_usage of string | F_run of Campaign_plants.error

(** The output directory follows the existing M29/M31 depth convention. *)
let usage () =
  "m34_plants <campaign-dir> <out-dir> [--root R] [--clone C]"

(** Repeated flags use the last value, as the existing pipeline CLI does. *)
let rec read_flags (c : Campaign_plants.config) (args : string list) :
    (Campaign_plants.config, failure) result =
  match args with
  | [] -> Ok c
  | "--root" :: root :: rest ->
      read_flags { c with Campaign_plants.cp_root = root } rest
  | "--clone" :: clone :: rest ->
      read_flags { c with Campaign_plants.cp_clone = clone } rest
  | flag :: _ -> Error (F_usage ("unknown flag or missing value: " ^ flag))

(** The four-level output root gives each direct child crate five levels. *)
let config_of (campaign : string) (out : string) : Campaign_plants.config =
  let defaults = Walk.defaults out in
  {
    Campaign_plants.cp_campaign = campaign;
    cp_out = out;
    cp_root = defaults.Walk.fl_root;
    cp_clone = defaults.Walk.fl_clone;
  }

(** Complete argument shapes prevent ignored trailing positional arguments. *)
let job (args : string list) : (string, failure) result =
  match args with
  | _ :: campaign :: out :: rest ->
      Result.bind (read_flags (config_of campaign out) rest) (fun c ->
          Result.map_error (fun e -> F_run e) (Campaign_plants.run c))
  | [] | [ _ ] | [ _; _ ] -> Error (F_usage (usage ()))

(** Usage errors exit 2; failed evidence exits 1; success prints two lines. *)
let main () : unit =
  Result.fold ~ok:print_string
    ~error:(fun e ->
      match e with
      | F_usage s ->
          prerr_endline ("m34_plants usage: " ^ s);
          exit 2
      | F_run f ->
          prerr_endline ("m34_plants failure: " ^ Campaign_plants.error_text f);
          exit 1)
    (job (Array.to_list Sys.argv))

let () = main ()
