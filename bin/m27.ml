(* M27 verdict CLI (DESIGN.md M27, spec section 5).

   Usage: m27 seeds <rust-jsonl> <out-dir> [--clone <dir>] [--root <dir>]

   seeds reads the rust capture the M24 gate wrote, runs the node
   driver over that SAME file into <out-dir>, runs the reference
   interpreter over Driver.seed_cases, and prints FOUR lines per case
   on stdout in case order:  R for the rust leg, J for the js leg, F
   for the reference leg, and V for the verdict core/differ.ml gives
   over those three cells.  The first three lines are byte-identical to
   the ones bin/m26.ml prints, and m27_verdict.sh check 5 asserts that
   against the m26 table of the same ladder run.

   This program holds NO comparison logic.  Every channel, every split
   and every excuse lives in core/differ.ml, which is pure and inside
   the ZxCaml subset.  The shell computes exactly two things the differ
   does not:  the by_design count, which reads a cell the differ never
   looks at, and the excused count, which reads the tag list the differ
   returns.

   The orchestration below (the flag reader, the rust capture read, the
   js leg run, the reference leg map, the count checks, the hint check
   and the position zip) is COPIED from bin/m26.ml rather than shared
   with it.  bin/m26.ml is untouched, so its green gate never becomes a
   dependent of M27 code.  The duplication is residual R5 (spec section
   10), which M31, the pipeline CLI, resolves by hoisting the shared
   part.

   The two hint types are different types with different constructor
   names (spec 0.4), so the hint check compares the WIRE SPELLINGS and
   never the constructors. *)

open Prelude

let usage =
  "usage: m27 seeds <rust-jsonl> <out-dir> [--clone <dir>] [--root <dir>] \
   [--plant ref:<name>|js:<name>]\n"

(* The seed list is the one bin/m24.ml captured from, in the same
   order, so its length is the count every leg must answer with. *)
let cases = len Driver.seed_cases

(* default_config needs the repo root, for the driver directory and for
   the clone.  M27_ROOT is the explicit route and the gate always sets
   it.  The fallback is two levels up from the out-dir, which is
   _emit for an out-dir at _emit/m27/out, so a run off the gate path
   must set M27_ROOT or pass --root.  Spec 5.1 pins the two-level
   fallback, so the code stays as it is.  Both routes are total:
   Sys.getenv_opt returns an option and Filename.dirname does not
   raise.  bin/m26.ml:39-43 is the same shape. *)
let root_of (dir : string) : string =
  Option.fold
    ~none:(Filename.dirname (Filename.dirname dir))
    ~some:(fun r -> r)
    (Sys.getenv_opt "M27_ROOT")

(* The reference leg's config is built from the js leg's, because the
   flag reader threads one record and the plant rides in it (spec 6.2).
   Plant.ops answers Ops.interp_ops for No_plant and for a js plant, so
   the reference leg is planted only by a ref plant. *)
let ref_config (cfg : Js_leg.config) : Ref_leg.config =
  { Ref_leg.default_config with Ref_leg.ops = Plant.ops cfg.Js_leg.plant }

(* Every named way this program can stop.  A sum type, so the compiler
   catches a new one, and one text function, so the CLI and the gate
   print the same words.  A Diverge, a Known and a Leg_fail verdict are
   RESULTS and are absent from this type on purpose (spec 5.5). *)
type failure =
  | F_flag of string (* the flag reader's own message *)
  | F_read of Js_leg.error (* the rust capture could not be read *)
  | F_rust_line of int * Wire.werror (* 1-based line number *)
  | F_js of Js_leg.error
  | F_count of string * int * int (* leg name, expected, observed *)
  | F_hint of (int * string * string) list (* case, reference, rust *)
  | F_exit of int (* the js driver's own exit code *)

let hint_text (ms : (int * string * string) list) : string =
  Option.fold ~none:"the hint check failed with no named case"
    ~some:(fun (n, refw, rustw) ->
      "case " ^ nat_to_string n ^ ": the reference hint is " ^ refw
      ^ " and the rust hint is " ^ rustw)
    (nth_opt ms 0)

let failure_text (f : failure) : string =
  match f with
  | F_flag m -> m
  | F_read e -> "the rust capture: " ^ Js_leg.error_text e
  | F_rust_line (n, w) ->
      "rust line " ^ nat_to_string n ^ " does not decode: "
      ^ Wire.werror_name w
  | F_js e -> Js_leg.error_text e
  | F_count (leg, want, got) ->
      "the " ^ leg ^ " leg answered " ^ nat_to_string got ^ " cases, expected "
      ^ nat_to_string want
  | F_hint ms -> "the reference hint differs from the rust hint at " ^ hint_text ms
  | F_exit n -> "the js driver exited " ^ nat_to_string n ^ ", expected 0"

(* The flag reader (spec 5.1), bin/m26.ml:83-91 unchanged.  A recursive
   read over the tail with the defaults ALREADY FILLED, so no field is
   ever an option and no later arm has to ask whether a flag was seen.
   --root moves the driver directory only:  the clone has its own flag
   and the gate passes both. *)
let rec read_flags (cfg : Js_leg.config) (args : string list) :
    (Js_leg.config, string) result =
  match args with
  | [] -> Ok cfg
  | "--clone" :: v :: rest -> read_flags { cfg with Js_leg.clone = v } rest
  | "--root" :: v :: rest ->
      read_flags { cfg with Js_leg.driver_dir = v ^ "/driver-js" } rest
  | "--plant" :: v :: rest ->
      Option.fold
        ~none:(Error ("unknown plant " ^ v))
        ~some:(fun p -> read_flags { cfg with Js_leg.plant = p } rest)
        (Plant.of_string v)
  | f :: [] -> Error ("the flag " ^ f ^ " has no value")
  | f :: _ :: _ -> Error ("unknown flag " ^ f)

(* ---------- the rust leg ---------- *)

let rec decode_rust (n : int) (lines : string list) :
    (Wire.decoded list, failure) result =
  match lines with
  | [] -> Ok []
  | line :: rest ->
      Result.bind
        (Result.map_error (fun w -> F_rust_line (n, w)) (Wire.decode_line line))
        (fun d -> Result.map (fun more -> d :: more) (decode_rust (n + 1) rest))

(* Rust_leg.read_file and Rust_leg.split_lines are the reuse of spec
   0.6.  Js_leg.of_rust carries the Rust leg's error into the js leg's
   error, so this program names one error type and not two. *)
let read_rust (path : string) : (Wire.decoded list, failure) result =
  Result.bind
    (Result.map_error
       (fun e -> F_read (Js_leg.of_rust e))
       (Rust_leg.read_file path))
    (fun text -> decode_rust 1 (Rust_leg.split_lines text))

(* ---------- the hint check ---------- *)

let rec hint_diffs (n : int) (ss : Sample.t list) (ds : Wire.decoded list) :
    (int * string * string) list =
  match (ss, ds) with
  | s :: ss1, d :: ds1 ->
      let refw = Driver.hint_wire (Ref_leg.hint s) in
      let rustw = Wire.hint_wire d.Wire.d_hint in
      append
        (match () with
        | () when String.equal refw rustw -> []
        | () -> [ (n, refw, rustw) ])
        (hint_diffs (n + 1) ss1 ds1)
  | [], [] | [], _ :: _ | _ :: _, [] -> []

(* ---------- the cells the differ adjudicates (spec 5.3) ---------- *)

(* The reference leg answers with an observation, and the SAME sample
   carries the mode the verdict needs.  They travel together, in one
   record and never in a pair of parallel lists, so the position zip
   below stays the three-list zip of bin/m26.ml:144-150 with its
   exhaustive seven-arm mismatch case. *)
type refcell = { r_mode : Taxonomy.mode; r_obs : Obs.observation }

let ref_cell_of (cfg : Ref_leg.config) (s : Sample.t) : refcell =
  { r_mode = s.Sample.mode; r_obs = Ref_leg.observe cfg s }

(* Four of the five Wire_js constructors carry no observation.  The
   Absent reason is Js_leg.cell itself, so it is BYTE-IDENTICAL to the
   J cell this program prints for the same line, by construction and
   not by a second spelling. *)
let js_cell (l : Wire_js.jline) : Differ.cell =
  match l.Wire_js.jl_body with
  | Wire_js.Jl_obs (o, _x) -> Differ.Present o
  | Wire_js.Jl_skipped _ | Wire_js.Jl_js_error (_, _)
  | Wire_js.Jl_driver_error (_, _) | Wire_js.Jl_lossy _ ->
      Differ.Absent (Js_leg.cell l)

(* The rust and the reference cells are always Present today.  The type
   carries Absent for M36's browser leg and for a rust line that fails
   to decode, and no M27 path builds one (spec section 10). *)
let cells_of (d : Wire.decoded) (l : Wire_js.jline) (o : Obs.observation) :
    Differ.cells =
  {
    Differ.rust = Differ.Present d.Wire.d_obs;
    js = js_cell l;
    reference = Differ.Present o;
  }

(* by_design counts a Signal_writing case whose RUST cell is a
   signal_write panic.  It is informational, it is never a verdict, and
   it is computed HERE because the differ does not look at that cell at
   all:  the rust leg is not a party on such a sample (spec 5.4). *)
let design_count (m : Taxonomy.mode) (cs : Differ.cells) : int =
  match m with
  | Taxonomy.Read_only -> 0
  | Taxonomy.Signal_writing -> (
      match cs.Differ.rust with
      | Differ.Absent _ -> 0
      | Differ.Present o -> (
          match o.Obs.outcome with
          | Obs.O_value _ -> 0
          | Obs.O_no_terminate -> 0
          | Obs.O_panic (p, _) -> (
              match p with
              | Obs.P_signal_write -> 1
              | Obs.P_unwrap | Obs.P_expect | Obs.P_unwrap_err
              | Obs.P_expect_err | Obs.P_other ->
                  0)))

(* A case is excused when the differ returned any tag for it.  Case 10
   is both excused and diverge, so this is a separate count and never a
   verdict. *)
let excused_count (ts : Differ.tag list) : int =
  match ts with [] -> 0 | _ :: _ -> 1

(* ---------- the printed table (spec 5.4) ---------- *)

(* Four lines per case, one space between the fields.  The cell can
   carry spaces, because a panic message can, so the verdict script
   reads $1 and $2 only.  The R and the J case numbers are each leg's
   OWN case number, and the F and the V case numbers are the position
   in Driver.seed_cases.  A capture whose lines ever fell out of order
   therefore prints different numbers and the byte compare names it. *)
type row = {
  rw_text : string;
  rw_verdict : Differ.verdict;
  rw_excused : Differ.tag list;
  rw_design : int;
}

let row_text (n : int) (d : Wire.decoded) (l : Wire_js.jline) (rc : refcell)
    (v : Differ.verdict) : string =
  nat_to_string d.Wire.d_case ^ " R " ^ Obs.encode d.Wire.d_obs ^ "\n"
  ^ nat_to_string l.Wire_js.jl_case ^ " J " ^ Js_leg.cell l ^ "\n"
  ^ nat_to_string n ^ " F " ^ Obs.encode rc.r_obs ^ "\n"
  ^ nat_to_string n ^ " V " ^ Taxonomy.mode_name rc.r_mode ^ " "
  ^ Differ.verdict_text v ^ "\n"

let row_of (n : int) (d : Wire.decoded) (l : Wire_js.jline) (rc : refcell) : row
    =
  let cs = cells_of d l rc.r_obs in
  let v = Differ.verdict rc.r_mode (Differ.known_seed ()) cs in
  {
    rw_text = row_text n d l rc v;
    rw_verdict = v;
    rw_excused = Differ.excused rc.r_mode (Differ.known_seed ()) cs;
    rw_design = design_count rc.r_mode cs;
  }

let rec table (n : int) (ds : Wire.decoded list) (ls : Wire_js.jline list)
    (os : refcell list) : row list =
  match (ds, ls, os) with
  | d :: ds1, l :: ls1, o :: os1 -> row_of n d l o :: table (n + 1) ds1 ls1 os1
  | [], [], [] | [], [], _ :: _ | [], _ :: _, [] | [], _ :: _, _ :: _
  | _ :: _, [], [] | _ :: _, [], _ :: _ | _ :: _, _ :: _, [] ->
      []

(* ---------- the summary line (spec 5.4) ---------- *)

type counts = {
  c_agree : int;
  c_diverge : int;
  c_known : int;
  c_leg_fail : int;
  c_excused : int;
  c_design : int;
}

let no_counts () : counts =
  {
    c_agree = 0;
    c_diverge = 0;
    c_known = 0;
    c_leg_fail = 0;
    c_excused = 0;
    c_design = 0;
  }

let bump_verdict (c : counts) (v : Differ.verdict) : counts =
  match v with
  | Differ.Agree -> { c with c_agree = c.c_agree + 1 }
  | Differ.Diverge (_, _) -> { c with c_diverge = c.c_diverge + 1 }
  | Differ.Known _ -> { c with c_known = c.c_known + 1 }
  | Differ.Leg_fail (_, _) -> { c with c_leg_fail = c.c_leg_fail + 1 }

let bump (c : counts) (r : row) : counts =
  let c1 = bump_verdict c r.rw_verdict in
  {
    c1 with
    c_excused = c1.c_excused + excused_count r.rw_excused;
    c_design = c1.c_design + r.rw_design;
  }

let tally (rs : row list) : counts = fold bump (no_counts ()) rs

(* The four verdict counts sum to cases.  excused and by_design are
   separate axes:  a case can be both excused and diverge, and case 10
   is. *)
let summary (c : counts) ~(rust : int) ~(js : int) ~(reference : int)
    ~(hint_mismatch : int) : string =
  "m27: cases " ^ nat_to_string cases ^ " rust " ^ nat_to_string rust ^ " js "
  ^ nat_to_string js ^ " ref " ^ nat_to_string reference ^ " agree "
  ^ nat_to_string c.c_agree ^ " diverge " ^ nat_to_string c.c_diverge
  ^ " known " ^ nat_to_string c.c_known ^ " leg_fail "
  ^ nat_to_string c.c_leg_fail ^ " excused " ^ nat_to_string c.c_excused
  ^ " by_design " ^ nat_to_string c.c_design ^ " hint_mismatch "
  ^ nat_to_string hint_mismatch

(* One line, and only when a plant is set.  An unconditional line would
   change the stderr of every m27 run and turn the M27 gate red. *)
let plant_line (p : Plant.t) : string =
  match p with
  | Plant.No_plant -> ""
  | Plant.Ref _ | Plant.Js _ -> "plant: " ^ Plant.name p ^ "\n"

(* ---------- the report ---------- *)

let named (f : failure) : int =
  prerr_string (failure_text f ^ "\n");
  1

(* The table and the summary print FIRST, so a run that answered the
   wrong count still shows what every leg said and what the differ made
   of it.  The exit code then names the first thing that is wrong.  A
   divergence is never one of those things (spec 5.5). *)
let report_out (ds : Wire.decoded list) (rep : Js_leg.report)
    (os : refcell list) (ms : (int * string * string) list)
    ~(plant : Plant.t) : int =
  let rs = table 0 ds rep.Js_leg.j_lines os in
  print_string (concat (map (fun r -> r.rw_text) rs));
  prerr_string
    (plant_line plant
    ^ summary (tally rs) ~rust:(len ds)
        ~js:(len rep.Js_leg.j_lines)
        ~reference:(len os) ~hint_mismatch:(len ms)
    ^ "\n");
  match () with
  | () when not (len ds = cases) -> named (F_count ("rust", cases, len ds))
  | () when not (len rep.Js_leg.j_lines = cases) ->
      named (F_count ("js", cases, len rep.Js_leg.j_lines))
  | () when not (len os = cases) ->
      named (F_count ("reference", cases, len os))
  | () when not (len ms = 0) -> named (F_hint ms)
  | () when not (rep.Js_leg.j_exit = 0) -> named (F_exit rep.Js_leg.j_exit)
  | () -> 0

let run_legs (cfg : Js_leg.config) ~(rust : string) ~(dir : string) : int =
  Result.fold ~ok:(fun code -> code)
    ~error:(fun f -> named f)
    (Result.bind (read_rust rust) (fun ds ->
         Result.bind
           (Result.map_error (fun e -> F_js e) (Js_leg.run cfg ~rust ~dir))
           (fun rep ->
             Ok
               (report_out ds rep
                  (map (ref_cell_of (ref_config cfg)) Driver.seed_cases)
                  (hint_diffs 0 Driver.seed_cases ds)
                  ~plant:cfg.Js_leg.plant))))

(* A flag the reader cannot read is a usage error, so it exits 2 beside
   the usage line and never 1, which is reserved for a named error of a
   run that started. *)
let seeds (rust : string) (dir : string) (rest : string list) : int =
  Result.fold
    ~ok:(fun cfg -> run_legs cfg ~rust ~dir)
    ~error:(fun m ->
      prerr_string (failure_text (F_flag m) ^ "\n");
      prerr_string usage;
      2)
    (read_flags (Js_leg.default_config ~root:(root_of dir)) rest)

(* Explicit arms, never a wildcard, as bin/m26.ml:207-214 spells them:
   the empty argv, a bare program name, a mode with no paths, a mode
   with one path, and every argv of four or more whose second word is
   not seeds. *)
let run_argv (argv : string list) : int =
  match argv with
  | _ :: "seeds" :: rust :: dir :: rest -> seeds rust dir rest
  | [] | [ _ ] | [ _; _ ] | [ _; _; _ ] | _ :: _ :: _ :: _ :: _ ->
      prerr_string usage;
      2

let () = exit (run_argv (Array.to_list Sys.argv))
