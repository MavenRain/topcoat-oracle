(* The M29 minimizer walk (DESIGN.md M29, M30 spec section 4).

   The walk used to live in bin/m29.ml.  M30 needs the SAME walk under a
   second CLI, so ruling R2 moved it here and left bin/m29.ml as a thin
   wrapper whose stdout is byte identical.  Every printer below is the
   shipped M29 printer with its shipped bytes;  m29_verdict.sh compares
   the recorded stdout with cmp, so a single moved space is a red gate.

   This file prints nothing.  It answers the text, and bin/ prints it,
   because a stdlib channel call inside shell/ is forbidden (M29 spec
   section 14.1).  named and usage stayed behind for that reason. *)

open Prelude

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

(** [binding_body kind b] is one walk binding line WITHOUT its newline.
    bin/m30.ml needs the text without the newline, and env_text needs it
    with one, so the shipped printer is split and neither caller retypes
    a byte of it. *)
let binding_body (kind : string) (b : Sample.binding) : string =
  "m29 " ^ kind ^ " "
  ^ Printer_rust.var_str b.Sample.id
  ^ ": " ^ ty_text b.Sample.ty ^ " = "
  ^ Printer_rust.print Ops.printer_renderer b.Sample.init

(** [binding_line kind b] is what env_text uses.  The bytes the walk
    prints do not move: this is the shipped body plus the shipped
    newline. *)
let binding_line (kind : string) (b : Sample.binding) : string =
  binding_body kind b ^ "\n"

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

(** [let_lines s] is the minimized program as RUST let lines, inputs
    first and signals second, in the sample's own order.  The two shapes
    are the crate writer's own, let <v>: <ty> = <init>; and
    let <v> = Signal::new(<init>); (shell/driver.ml:304-311);  the
    initialiser text is the sample's own, printed by the same call
    binding_body uses, so the program block and the trace cannot
    drift. *)
let let_lines (s : Sample.t) : string list =
  append
    (map
       (fun b ->
         "let "
         ^ Printer_rust.var_str b.Sample.id
         ^ ": " ^ ty_text b.Sample.ty ^ " = "
         ^ Printer_rust.print Ops.printer_renderer b.Sample.init
         ^ ";")
       s.Sample.inputs)
    (map
       (fun b ->
         "let "
         ^ Printer_rust.var_str b.Sample.id
         ^ " = Signal::new("
         ^ Printer_rust.print Ops.printer_renderer b.Sample.init
         ^ ");")
       s.Sample.signals)

(** [body_text s] is the body expression as Rust, with no newline.  It is
    the one expression final_text prints after "m29 body: "
    (bin/m29.ml:168), so the repro program block and the walk agree. *)
let body_text (s : Sample.t) : string =
  Printer_rust.print Ops.printer_renderer s.Sample.body

(** One whole walk: the text M29 prints, the minimizer result, the start
    sample and its size, the control ANSWER, the leg config, the flags
    the run was given and the divergence it preserved.  The record is
    what lets a second CLI re-use the walk without a second copy of
    it. *)
type run = {
  wk_text : string;  (** the M29 stdout, verbatim, newline terminated *)
  wk_result : Minimize.result;
  wk_start : Sample.t;
  wk_start_size : int;
  wk_control : Minimize.answer;
  wk_cfg : Legs.config;
  wk_flags : flags;  (** the parsed flags, so the plant and the fuel travel *)
  wk_keep : Differ.verdict;  (** the divergence the oracle preserved *)
  wk_sample : Sample.t;  (** the final sample, that is wk_result.m_final *)
}

(** [text p s v r ctl] is the whole M29 stdout.  It is the SAME eight
    printers in the SAME order M29 printed them, so the concatenation is
    the same byte stream a sequence of print_string calls wrote.  That is
    the whole byte identity argument of ruling R2. *)
let text (p : Plant.t) (s : Sample.t) (v : Differ.verdict)
    (r : Minimize.result) (ctl : Minimize.answer) : string =
  head_text p s v
  ^ concat (map round_line r.Minimize.m_trace)
  ^ final_text r ctl

(* The run, once the start verdict is known to be a divergence. *)
let walk (cfg : Legs.config) (f : flags) (p : Plant.t) (s : Sample.t)
    (v : Differ.verdict) : (run, failure) result =
  let r =
    Minimize.run (Legs.oracle cfg) { Minimize.fuel = f.fl_fuel } ~target:v s
  in
  let ctl = Legs.control cfg r.Minimize.m_final in
  Ok
    {
      wk_text = text p s v r ctl;
      wk_result = r;
      wk_start = s;
      wk_start_size = Minimize.size_of s;
      wk_control = ctl;
      wk_cfg = cfg;
      wk_flags = f;
      wk_keep = v;
      wk_sample = r.Minimize.m_final;
    }

(* Measure the start sample, then walk.  A start that is not a
   divergence is a named failure and never an empty run: the case is
   supposed to be planted, so an agreeing start means the plant did not
   take. *)
let minimize_case (cfg : Legs.config) (f : flags) (p : Plant.t) (s : Sample.t)
    : (run, failure) result =
  match Legs.start cfg s with
  | Minimize.A_no_verdict why -> Error (F_start why)
  | Minimize.A_verdict v -> (
      match v with
      | Differ.Diverge (_, _) -> walk cfg f p s v
      | Differ.Agree -> Error (F_no_diverge (Differ.verdict_text v))
      | Differ.Known _ -> Error (F_no_diverge (Differ.verdict_text v))
      | Differ.Leg_fail (_, _) ->
          Error (F_no_diverge (Differ.verdict_text v)))

(** [run ~dir f] is one whole walk under the output directory [dir].  It
    builds the leg config the shipped with_flags built
    (bin/m29.ml:216-230) from the same three labelled arguments, looks
    the case up and answers the record.  The No_plant refusal did NOT
    move: it prints, so it stayed in bin/. *)
let run ~(dir : string) (f : flags) : (run, failure) result =
  let cfg =
    Legs.default_config ~root:f.fl_root ~clone:f.fl_clone ~out:dir f.fl_plant
  in
  Result.fold
    ~ok:(fun s ->
      Result.bind
        (Result.map_error
           (fun e -> F_start (Rust_leg.error_text e))
           (Rust_leg.mkdir_parents dir))
        (fun () -> minimize_case cfg f f.fl_plant s))
    ~error:(fun m -> Error (F_no_case m))
    (M29_cases.case_of f.fl_plant)
