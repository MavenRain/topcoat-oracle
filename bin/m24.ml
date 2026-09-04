(* M24 rust-leg CLI (DESIGN.md M24, spec section 5).

   Usage: m24 seeds <out-dir>

   seeds builds the seed crate from Driver.seed_cases under <out-dir>,
   runs it with the pinned toolchain, decodes the JSONL it wrote and
   prints one Rust_leg.row per case on stdout, in case order.
   Rust_leg.summary goes to stderr, and m24_verdict.sh asserts that one
   line whole.

   This program holds NO logic beyond the argv dispatch, one
   Rust_leg.run call and the printing.  The row format and the summary
   format both live in shell/rust_leg.ml, so the unit tests and the
   gate share ONE oracle. *)

open Prelude

let usage = "usage: m24 seeds <out-dir>\n"

(* default_config needs the repo root, for the target dir and for the
   harness path.  M24_ROOT is the explicit route and the gate always
   sets it.  The fallback is two levels up from the out-dir, which is
   the repo root whenever the out-dir sits at _emit/m24seed, and that
   same two-level assumption fixes dep_prefix = "../../../".  Both
   routes are total: Sys.getenv_opt returns an option and
   Filename.dirname does not raise. *)
let root_of (dir : string) : string =
  Option.fold
    ~none:(Filename.dirname (Filename.dirname dir))
    ~some:(fun r -> r)
    (Sys.getenv_opt "M24_ROOT")

let rows_text (rep : Rust_leg.report) : string =
  concat (map (fun d -> Rust_leg.row d ^ "\n") rep.Rust_leg.p_lines)

(* Exit 0 when every line decoded and the line count equals the kept
   count.  A count mismatch is named on stderr and exits 1.  A run that
   lost a direct JS body on at least one case adds a second stderr line
   naming those cases, so exit 4 is surfaced and never swallowed. *)
let report_out (rep : Rust_leg.report) : int =
  print_string (rows_text rep);
  prerr_string (Rust_leg.summary rep ^ "\n");
  prerr_string
    (match () with
    | () when len rep.Rust_leg.p_inconsistent > 0 ->
        Rust_leg.inconsistent_text rep ^ "\n"
    | () -> "");
  match () with
  | () when len rep.Rust_leg.p_lines = rep.Rust_leg.p_kept -> 0
  | () ->
      prerr_string
        (Rust_leg.error_text
           (Rust_leg.Er_count
              (rep.Rust_leg.p_kept, len rep.Rust_leg.p_lines))
        ^ "\n");
      1

let seeds (dir : string) : int =
  Result.fold ~ok:report_out
    ~error:(fun e ->
      prerr_string (Rust_leg.error_text e ^ "\n");
      1)
    (Rust_leg.run
       (Rust_leg.default_config ~root:(root_of dir))
       ~name:"m24seed" ~dir Driver.seed_cases)

(* Explicit arms, never a wildcard, as bin/emit_m23.ml spells them: the
   empty argv, a bare program name, a mode with no directory, and every
   argv of three or more whose second word is not seeds. *)
let run_argv (argv : string list) : int =
  match argv with
  | _ :: "seeds" :: dir :: [] -> seeds dir
  | [] | [ _ ] | [ _; _ ] | _ :: _ :: _ :: _ ->
      prerr_string usage;
      2

let () = exit (run_argv (Array.to_list Sys.argv))
