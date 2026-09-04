(* M26 three-leg CLI (DESIGN.md M26, spec section 6).

   Usage: m26 seeds <rust-jsonl> <out-dir> [--clone <dir>] [--root <dir>]

   seeds reads the rust capture the M24 gate wrote, runs the node
   driver over that SAME file into <out-dir>, runs the reference
   interpreter over Driver.seed_cases, and prints three lines per case
   on stdout in case order:  R for the rust leg, J for the js leg, F
   for the reference leg.  Js_leg.summary goes to stderr, and
   m26_verdict.sh asserts that one line whole.

   This program holds NO logic beyond the argv dispatch, the flag
   reader, the three leg calls, the two checks and the printing.  The
   J cell text and the summary format both live in shell/js_leg.ml, and
   the R and F cells are Obs.encode, so the unit tests and the gate
   share ONE oracle.

   The two hint types are different types with different constructor
   names (Driver.hint against Wire.hint, spec 0.4), so the hint check
   compares the WIRE SPELLINGS and never the constructors. *)

open Prelude

let usage =
  "usage: m26 seeds <rust-jsonl> <out-dir> [--clone <dir>] [--root <dir>]\n"

(* The seed list is the one bin/m24.ml captured from, in the same
   order, so its length is the count every leg must answer with. *)
let cases = len Driver.seed_cases

(* default_config needs the repo root, for the driver directory and for
   the clone.  M26_ROOT is the explicit route and the gate always sets
   it.  The fallback is two levels up from the out-dir, which is
   _emit for an out-dir at _emit/m26/out, so a run off the gate path
   must set M26_ROOT or pass --root.  Spec 6.1 pins the two-level
   fallback, so the code stays as it is.  Both routes
   are total:  Sys.getenv_opt returns an option and Filename.dirname
   does not raise.  bin/m24.ml:27-31 is the same shape. *)
let root_of (dir : string) : string =
  Option.fold
    ~none:(Filename.dirname (Filename.dirname dir))
    ~some:(fun r -> r)
    (Sys.getenv_opt "M26_ROOT")

(* Every named way this program can stop.  A sum type, so the compiler
   catches a new one, and one text function, so the CLI and the gate
   print the same words. *)
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

(* The flag reader (spec 6.1).  A recursive read over the tail with the
   defaults ALREADY FILLED, so no field is ever an option and no later
   arm has to ask whether a flag was seen.  --root moves the driver
   directory only:  the clone has its own flag and the gate passes
   both. *)
let rec read_flags (cfg : Js_leg.config) (args : string list) :
    (Js_leg.config, string) result =
  match args with
  | [] -> Ok cfg
  | "--clone" :: v :: rest -> read_flags { cfg with Js_leg.clone = v } rest
  | "--root" :: v :: rest ->
      read_flags { cfg with Js_leg.driver_dir = v ^ "/driver-js" } rest
  | f :: [] -> Error ("the flag " ^ f ^ " has no value")
  | f :: _ :: _ -> Error ("unknown flag " ^ f)

(* ---------- the rust leg (spec 6.2 step 1) ---------- *)

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

(* ---------- the hint check (spec 6.2 step 4, ruling Q4) ---------- *)

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

(* ---------- the printed table (spec 6.2 step 5) ---------- *)

(* Three lines per case, one space between the fields.  The cell can
   carry spaces, because a panic message can, so the verdict reads $1
   and $2 only.  The R and the J case numbers are each leg's OWN case
   number, and the F case number is the position in Driver.seed_cases,
   which is the reference leg's case number.  A capture whose lines
   ever fell out of order therefore prints three different numbers and
   the byte compare names it. *)
let rows (n : int) (d : Wire.decoded) (l : Wire_js.jline)
    (o : Obs.observation) : string =
  nat_to_string d.Wire.d_case ^ " R " ^ Obs.encode d.Wire.d_obs ^ "\n"
  ^ nat_to_string l.Wire_js.jl_case ^ " J " ^ Js_leg.cell l ^ "\n"
  ^ nat_to_string n ^ " F " ^ Obs.encode o ^ "\n"

let rec table (n : int) (ds : Wire.decoded list) (ls : Wire_js.jline list)
    (os : Obs.observation list) : string list =
  match (ds, ls, os) with
  | d :: ds1, l :: ls1, o :: os1 -> rows n d l o :: table (n + 1) ds1 ls1 os1
  | [], [], [] | [], [], _ :: _ | [], _ :: _, [] | [], _ :: _, _ :: _
  | _ :: _, [], [] | _ :: _, [], _ :: _ | _ :: _, _ :: _, [] ->
      []

(* ---------- the report (spec 6.2 steps 5 to 7) ---------- *)

let named (f : failure) : int =
  prerr_string (failure_text f ^ "\n");
  1

(* The table and the summary print FIRST, so a run that answered the
   wrong count still shows what every leg said.  The exit code then
   names the first thing that is wrong. *)
let report_out (ds : Wire.decoded list) (rep : Js_leg.report)
    (os : Obs.observation list) (ms : (int * string * string) list) : int =
  print_string (concat (table 0 ds rep.Js_leg.j_lines os));
  prerr_string
    (Js_leg.summary rep ~cases ~rust:(len ds) ~reference:(len os)
       ~hint_mismatch:(len ms)
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
                  (map (Ref_leg.observe Ref_leg.default_config)
                     Driver.seed_cases)
                  (hint_diffs 0 Driver.seed_cases ds)))))

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

(* Explicit arms, never a wildcard, as bin/m24.ml:70-75 spells them:
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
