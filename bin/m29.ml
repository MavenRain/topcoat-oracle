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
   core/minimize.ml. *)

open Prelude

let usage : string =
  "usage: m29 minimize <dir> --plant ref:display_sign|js:signal_get_plus_one \
   [--clone <dir>] [--root <dir>] [--fuel <n>]\n"

(* The parsed flags. *)
type flags = {
  fl_root : string;
  fl_clone : string;
  fl_plant : Plant.t;
  fl_fuel : int;
}

(* A fuel below one would stop the loop before it entered a round and
   print a fuel stop with an empty trace, which reads like a fixpoint at
   the start size.  The parser refuses it at the boundary instead. *)
let positive_opt (v : string) : int option =
  Option.fold ~none:None
    ~some:(fun n -> if n >= 1 then Some n else None)
    (int_of_string_opt v)

(* The shipped flags for an output directory.  The output directory is
   <root>/_emit/m29/out/<plant>, four segments below the root, so the
   default root is four dirnames up.  The gate passes --root explicitly
   anyway, and the dep prefix of shell/legs.ml depends on that same
   depth. *)
let defaults (dir : string) : flags =
  let up (p : string) : string = Filename.dirname p in
  let root = up (up (up (up dir))) in
  {
    fl_root = root;
    fl_clone = root ^ "/../topcoat";
    fl_plant = Plant.No_plant;
    fl_fuel = Minimize.default_config.Minimize.fuel;
  }

(* One pass over the flag list.  Every unknown flag and every missing
   value is a usage error and never a silent default. *)
let rec read_flags (f : flags) (args : string list) : (flags, string) result =
  match args with
  | [] -> Ok f
  | "--clone" :: v :: rest -> read_flags { f with fl_clone = v } rest
  | "--root" :: v :: rest -> read_flags { f with fl_root = v } rest
  | "--plant" :: v :: rest ->
      Option.fold
        ~none:(Error ("unknown plant " ^ v))
        ~some:(fun p -> read_flags { f with fl_plant = p } rest)
        (Plant.of_string v)
  | "--fuel" :: v :: rest ->
      Option.fold
        ~none:(Error ("the --fuel value " ^ v ^ " is not a positive number"))
        ~some:(fun n -> read_flags { f with fl_fuel = n } rest)
        (positive_opt v)
  | a :: [] -> Error ("the flag " ^ a ^ " has no value")
  | a :: _ :: _ -> Error ("unknown flag " ^ a)

(* Every way a run can fail with a named reason. *)
type failure =
  | F_flag of string
  | F_no_case of string
  | F_start of string
  | F_no_diverge of string

(* The stderr text of a named failure. *)
let failure_text (f : failure) : string =
  match f with
  | F_flag m -> m
  | F_no_case m -> m
  | F_start why -> "the start sample produced no verdict: " ^ why
  | F_no_diverge v ->
      "the start sample is " ^ v
      ^ " under the plant, and the minimizer needs a divergence to preserve"

(* Print a named failure and answer the exit code. *)
let named (f : failure) : int =
  prerr_string (failure_text f ^ "\n");
  1

(* One trace line.  round <k> size <n> cands <m> accepted <i|none> *)
let round_line (st : Minimize.step) : string =
  "round "
  ^ nat_to_string st.Minimize.st_round
  ^ " size "
  ^ nat_to_string st.Minimize.st_size
  ^ " cands "
  ^ nat_to_string st.Minimize.st_cands
  ^ " accepted "
  ^ (match st.Minimize.st_accepted with
    | Minimize.Acc_none -> "none"
    | Minimize.Acc_index i -> nat_to_string i)
  ^ "\n"

(* The stop reason as it appears in the stop line.  Stuck carries its
   reason inline, so the word is "stuck" followed by one space and the
   reason text (spec 7.3, ruling Q8).  The reason may hold spaces, which
   is why only the fixpoint and the fuel shapes have fixed field
   positions past field 3, and why m29_verdict.sh reads field 3 before
   it reads any other field of this line. *)
let stop_word (s : Minimize.stop) : string =
  match s with
  | Minimize.Fixpoint -> "fixpoint"
  | Minimize.Fuel -> "fuel"
  | Minimize.Stuck why -> "stuck " ^ why

(* The Rust text of a type.  core/printer_rust.ml prints expressions
   only, so the type text comes from the crate writer's own function
   (shell/driver.ml:163-175, re-read at eca3372).  A type it cannot
   render prints as ? and the gate's byte comparison catches it. *)
let ty_text (t : Ast.ty) : string =
  Option.fold ~none:"?" ~some:(fun s -> s) (Driver.rust_ty t)

(* One binding of the final environment. *)
let binding_line (kind : string) (b : Sample.binding) : string =
  "m29 " ^ kind ^ " "
  ^ Printer_rust.var_str b.Sample.id
  ^ ": " ^ ty_text b.Sample.ty ^ " = "
  ^ Printer_rust.print Ops.printer_renderer b.Sample.init
  ^ "\n"

(* The final environment, inputs then signals, in the sample's own
   order.  An empty environment prints nothing at all. *)
let env_text (s : Sample.t) : string =
  concat
    (append
       (map (binding_line "input") s.Sample.inputs)
       (map (binding_line "signal") s.Sample.signals))

(* The control line's text. *)
let answer_text (a : Minimize.answer) : string =
  match a with
  | Minimize.A_verdict v -> Differ.verdict_text v
  | Minimize.A_no_verdict why -> "no_verdict: " ^ why

(* The two header lines. *)
let head_text (p : Plant.t) (s : Sample.t) (v : Differ.verdict) : string =
  "m29 case: " ^ Plant.name p ^ "\n" ^ "m29 start: "
  ^ Taxonomy.mode_name s.Sample.mode
  ^ " size "
  ^ nat_to_string (Minimize.size_of s)
  ^ " " ^ Differ.verdict_text v ^ "\n"

(* The final block.  Body first, then the surviving environment, then
   the preserved verdict, the size, the stop reason with its two counts
   and the control. *)
let final_text (r : Minimize.result) (ctl : Minimize.answer) : string =
  "m29 body: "
  ^ Printer_rust.print Ops.printer_renderer r.Minimize.m_final.Sample.body
  ^ "\n"
  ^ env_text r.Minimize.m_final
  ^ "m29 verdict: "
  ^ Taxonomy.mode_name r.Minimize.m_final.Sample.mode
  ^ " "
  ^ Differ.verdict_text r.Minimize.m_verdict
  ^ "\n" ^ "m29 size: "
  ^ nat_to_string (Minimize.size_of r.Minimize.m_final)
  ^ "\n" ^ "m29 stop: "
  ^ stop_word r.Minimize.m_stop
  ^ " rounds "
  ^ nat_to_string r.Minimize.m_rounds
  ^ " candidates "
  ^ nat_to_string r.Minimize.m_evaluated
  ^ "\n" ^ "m29 control: " ^ answer_text ctl ^ "\n"

(* The run, once the start verdict is known to be a divergence. *)
let walk (cfg : Legs.config) (f : flags) (p : Plant.t) (s : Sample.t)
    (v : Differ.verdict) : int =
  let r =
    Minimize.run (Legs.oracle cfg) { Minimize.fuel = f.fl_fuel } ~target:v s
  in
  let ctl = Legs.control cfg r.Minimize.m_final in
  print_string
    (head_text p s v
    ^ concat (map round_line r.Minimize.m_trace)
    ^ final_text r ctl);
  0

(* Measure the start sample, then walk.  A start that is not a
   divergence is a named failure and never an empty run: the case is
   supposed to be planted, so an agreeing start means the plant did not
   take. *)
let minimize_case (cfg : Legs.config) (f : flags) (p : Plant.t) (s : Sample.t)
    : int =
  match Legs.start cfg s with
  | Minimize.A_no_verdict why -> named (F_start why)
  | Minimize.A_verdict v -> (
      match v with
      | Differ.Diverge (_, _) -> walk cfg f p s v
      | Differ.Agree -> named (F_no_diverge (Differ.verdict_text v))
      | Differ.Known _ -> named (F_no_diverge (Differ.verdict_text v))
      | Differ.Leg_fail (_, _) ->
          named (F_no_diverge (Differ.verdict_text v)))

(* The plant selects the case.  No plant is a usage error, because a run
   with no plant has nothing to minimize. *)
let with_flags (dir : string) (f : flags) : int =
  match f.fl_plant with
  | Plant.No_plant ->
      prerr_string "the --plant flag is required\n";
      prerr_string usage;
      2
  | Plant.Ref _ | Plant.Js _ ->
      let cfg =
        Legs.default_config ~root:f.fl_root ~clone:f.fl_clone ~out:dir
          f.fl_plant
      in
      Result.fold
        ~ok:(fun s -> minimize_case cfg f f.fl_plant s)
        ~error:(fun m -> named (F_no_case m))
        (M29_cases.case_of f.fl_plant)

(* The minimize verb: read the flags, then run. *)
let minimize (dir : string) (rest : string list) : int =
  Result.fold
    ~ok:(fun f -> with_flags dir f)
    ~error:(fun m ->
      prerr_string (failure_text (F_flag m) ^ "\n");
      prerr_string usage;
      2)
    (read_flags (defaults dir) rest)

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
