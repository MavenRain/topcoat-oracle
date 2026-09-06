(* M29 minimizer CLI (DESIGN.md M29, spec section 7).

   Usage: m29 minimize <dir> --plant ref:display_sign|js:signal_get_plus_one
          [--clone <dir>] [--root <dir>] [--fuel <n>]

   minimize takes the M29 case that belongs to the plant
   (shell/m29_cases.ml), measures its verdict once through the three
   legs, runs the shrink loop of core/minimize.ml over it, and prints
   one line per round and then the final block.

   The last line is a CONTROL: the minimized sample run once more with
   NO plant, which must agree.  A divergence that survives the control
   is a pre-existing one and not the planted bug, so the control line is
   the difference between a minimizer and a coincidence.

   Every leg call is real: one crate build per round, one node start per
   round.  This file holds no comparison logic at all; every channel and
   every split lives in core/differ.ml, and the walk lives in
   core/minimize.ml.

   Since M30 the walk itself lives in shell/walk.ml (M30 ruling R2), and
   this file is argv, the No_plant refusal and printing. *)

let usage : string =
  "usage: m29 minimize <dir> --plant ref:display_sign|js:signal_get_plus_one \
   [--clone <dir>] [--root <dir>] [--fuel <n>]\n"

(* Print a named failure and answer the exit code. *)
let named (f : Walk.failure) : int =
  prerr_string (Walk.failure_text f ^ "\n");
  1

(* The plant selects the case.  No plant is a usage error, because a run
   with no plant has nothing to minimize. *)
let with_flags (dir : string) (f : Walk.flags) : int =
  match f.Walk.fl_plant with
  | Plant.No_plant ->
      prerr_string "the --plant flag is required\n";
      prerr_string usage;
      2
  | Plant.Ref _ | Plant.Js _ ->
      Result.fold
        ~ok:(fun (r : Walk.run) ->
          print_string r.Walk.wk_text;
          0)
        ~error:named
        (Walk.run ~dir f)

(* The minimize verb: read the flags, then run. *)
let minimize (dir : string) (rest : string list) : int =
  Result.fold
    ~ok:(fun f -> with_flags dir f)
    ~error:(fun m ->
      prerr_string (Walk.failure_text (Walk.F_flag m) ^ "\n");
      prerr_string usage;
      2)
    (Walk.read_flags (Walk.defaults dir) rest)

(* The argv reader.  Every shape but the minimize verb with a directory
   is a usage error. *)
let run_argv (argv : string list) : int =
  match argv with
  | _ :: "minimize" :: dir :: rest -> minimize dir rest
  | [] -> prerr_string usage; 2
  | _ :: [] -> prerr_string usage; 2
  | _ :: _ :: [] -> prerr_string usage; 2
  | _ :: _ :: _ :: _ -> prerr_string usage; 2

(* The entry point. *)
let () = exit (run_argv (Array.to_list Sys.argv))
