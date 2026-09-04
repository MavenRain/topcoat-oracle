(* M23 rust-leg driver-crate emitter (DESIGN.md M23).

   Usage: emit_m23 (seed|batch) <relative-file>
   Prints ONE crate file to stdout;  the gate script redirects it into
   place (m23_gate.sh owns every mkdir, redirect and the copy of
   driver-rs/harness.rs), so this program performs no file IO at all
   and stays exception-free.

   seed  : the twelve hand-picked cases of Driver.seed_cases, one per
           channel the M24 parser has to read.  m23_verdict.sh checks
           its JSONL line by line.
   batch : 300 samples at seed 0x4d3233 through
           Sample_gen.gen_sample at the m20 scope, one case fn per
           kept sample, plus the cases.span and count sidecars.  The
           batch is the compile-coverage leg: it proves the emitter
           renders the drawn corpus, not just the seed vector. *)

open Prelude

let seed_files () = Driver.crate_files ~name:"m23seed" ~dep_prefix:"../../../" Driver.seed_cases

let batch_files () =
  let samples =
    QCheck.Gen.generate ~n:300
      ~rand:(Random.State.make [| 0x4d3233 |])
      (Sample_gen.gen_sample true Weights.m20)
  in
  Driver.crate_files ~name:"m23batch" ~dep_prefix:"../../../" samples

let usage = "usage: emit_m23 (seed|batch) <relative-file>\n"

(* Exit code as a value: 0 with the file on stdout, 2 with usage (an
   unknown mode or a file the crate does not contain). *)
let run argv =
  match argv with
  | _ :: "seed" :: rel :: [] ->
      Option.fold ~none:(usage, 2)
        ~some:(fun content -> (content, 0))
        (assoc_opt String.equal rel (seed_files ()))
  | _ :: "batch" :: rel :: [] ->
      Option.fold ~none:(usage, 2)
        ~some:(fun content -> (content, 0))
        (assoc_opt String.equal rel (batch_files ()))
  (* Explicit arms, never a wildcard: the shapes left over are the
     empty argv, a bare program name, a mode with no file, and every
     argv of three or more whose second word is neither mode. *)
  | [] | [ _ ] | [ _; _ ] | _ :: _ :: _ :: _ -> (usage, 2)

let () =
  let out = run (Array.to_list Sys.argv) in
  print_string (fst out);
  exit (snd out)
