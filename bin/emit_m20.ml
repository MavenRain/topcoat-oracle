(* M20 driver-crate emitter (DESIGN.md M20).

   Usage: emit_m20 (r2|batch) <relative-file>
   Prints ONE crate file to stdout; the gate script redirects it into
   place (m20_gate.sh / m20_r2.sh own the mkdir and redirects, so this
   program performs no file IO at all and stays exception-free).

   r2    : round-2 probe crate. AST-built probes, printed through the
           real renderer, adjudicating the constructs round 1 could
           not hand-write (flow keywords are generated text) plus the
           method/operator surface the m20 generator emits. Verdicts
           land in research/m20-expr-macro-probe.md.
   batch : the 1k gate crate. 1000 samples at seed 0x4d3230 through
           Gen.gen_target_m20 M20.genv, one fn per sample, plus the
           case_neg negative control and its line-span sidecar
           (case_neg.span). *)

open Prelude
open Ast

let fb x =
  let p = Floatops.of_float x in
  E_lit (L_f64_bits (fst p, snd p))

let e_case name note e =
  { Emit.cname = name; note = [ note ]; body = Emit.B_expr e }

let raw_case name note lines =
  { Emit.cname = name; note = [ note ]; body = Emit.B_raw lines }

let str s = E_lit (L_str s)

let clone_of v = E_method (E_var v, M_clone, [])

(* Round-2 probes. One risky mechanism per case so an unexpected
   failure counts once. *)
let r2_cases =
  [
    e_case "p01_loop_break"
      "EXPECT pass: Loop/Break dispatch arms exist (grammar expr.rs:134-155)"
      (E_loop (E_block_unit [ E_break ]));
    e_case "p02_while_signal_set"
      "EXPECT pass: While arm exists; surrogate bool condition"
      (E_while (E_var 1, E_block_unit [ E_method (E_var 3, M_set, [ fb 1.0 ]) ]));
    e_case "p03_loop_continue_suffix"
      "EXPECT pass: Continue arm; suffix break after an if-continue"
      (E_loop
         (E_block_unit [ E_if (E_var 1, E_block_unit [ E_continue ]); E_break ]));
    e_case "p04_nested_loop" "EXPECT pass: nested Loop arms"
      (E_loop (E_block_unit [ E_loop (E_block_unit [ E_break ]); E_break ]));
    e_case "p05_then_annotated"
      "EXPECT unknown (CRITICAL): our print annotates the then-arg closure return; round-1 f1 says annotated types stay real while bodies are surrogates"
      (E_method (E_var 1, M_then, [ E_closure ([], T_f64, fb 1.0) ]));
    raw_case "p06_then_bare_control"
      "EXPECT pass: round-1 f6 verified this bare-closure arg verbatim"
      [ "let v1: bool = true;"; "let _ = expr!(v1.then(|| 1.0));" ];
    e_case "p07_trim_start"
      "EXPECT unknown: round-1 M_trim was E0597 even on first use; same StrSurrogate borrow suspected"
      (E_method (E_var 2, M_trim_start, []));
    e_case "p08_trim_end" "EXPECT unknown: same class as p07"
      (E_method (E_var 2, M_trim_end, []));
    e_case "p09_trim_start_cloned"
      "EXPECT unknown: the receiver shape gen actually emits (var_use clones)"
      (E_method (clone_of 2, M_trim_start, []));
    e_case "p10_trim_end_cloned" "EXPECT unknown: same as p09"
      (E_method (clone_of 2, M_trim_end, []));
    e_case "p11_is_empty" "EXPECT pass: String predicate, first use"
      (E_method (E_var 2, M_is_empty, []));
    e_case "p12_starts_with" "EXPECT pass: String predicate with literal arg"
      (E_method (E_var 2, M_starts_with, [ str "a" ]));
    e_case "p13_ends_with" "EXPECT pass: String predicate with literal arg"
      (E_method (E_var 2, M_ends_with, [ str "a" ]));
    e_case "p14_is_none" "EXPECT pass: round-1 c3 sibling (is_some passed)"
      (E_method (E_var 8, M_is_none, []));
    e_case "p15_is_err" "EXPECT pass: round-1 c4 sibling (is_ok passed)"
      (E_method (E_var 6, M_is_err, []));
    e_case "p16_unwrap_err" "EXPECT pass: Result method, first use"
      (E_method (E_var 7, M_unwrap_err, []));
    e_case "p17_err" "EXPECT pass: Result method, first use"
      (E_method (E_var 6, M_err, []));
    e_case "p18_res_clone_unwrap"
      "EXPECT pass: var_use shape for Result vars (clone then method)"
      (E_method (clone_of 6, M_unwrap, []));
    e_case "p19_opt_clone_unwrap" "EXPECT pass: var_use shape for Option vars"
      (E_method (clone_of 8, M_unwrap, []));
    e_case "p20_str_eq"
      "EXPECT pass: String surrogate PartialEq (round 1 only covered f64 cmp)"
      (E_binary (B_eq, clone_of 2, str "a"));
    e_case "p21_str_lt" "EXPECT pass: String surrogate PartialOrd"
      (E_binary (B_lt, str "a", clone_of 2));
    e_case "p22_bool_eq" "EXPECT pass: bool surrogate PartialEq"
      (E_binary (B_eq, E_var 1, E_lit (L_bool false)));
    e_case "p23_then_some_lit_recv"
      "EXPECT pass: literal bool receiver (b2 class); m20 option-leaf fallback shape"
      (E_method (E_lit (L_bool false), M_then_some, [ fb 1.5 ]));
    e_case "p24_then_some_string"
      "EXPECT pass: then_some with a cloned String value arg"
      (E_method (E_var 1, M_then_some, [ clone_of 2 ]));
    e_case "p25_push_str_arg"
      "EXPECT pass: push_str with a cloned String arg (d1 used first-use forms)"
      (E_method (E_var 5, M_push_str, [ clone_of 2 ]));
    e_case "p26_while_cond_get"
      "EXPECT pass: While condition through a signal get"
      (E_while (E_method (E_var 4, M_get, []), E_block_unit []));
    e_case "p27_f64_specials"
      "EXPECT unknown: f_literal prints these as f64::NAN / f64::INFINITY path exprs; grammar path support unverified"
      (E_binary (B_add, fb nan, fb infinity));
    e_case "p28_expect_escaped"
      "EXPECT pass: escaped string literal arg (debug-rendered)"
      (E_method (E_var 8, M_expect, [ str "quote\"and\\back" ]));
    e_case "p29_contains_utf8" "EXPECT pass: UTF-8 multibyte string literal arg"
      (E_method (E_var 2, M_contains, [ str "caf\xc3\xa9" ]));
    e_case "p30_set_same_signal"
      "EXPECT pass: same signal twice in one expr! (d3 verified)"
      (E_method
         ( E_var 3,
           M_set,
           [ E_binary (B_add, E_method (E_var 3, M_get, []), fb 1.0) ] ));
    (* Round 2b: the shapes the round-3 scope narrowing leans on. *)
    e_case "p31_starts_with_clone_recv"
      "EXPECT pass: cloned String receiver, literal pattern arg"
      (E_method (clone_of 2, M_starts_with, [ str "a" ]));
    e_case "p32_str_eq_values"
      "EXPECT pass: StringSurrogate == StringSurrogate (no literal side)"
      (E_binary (B_eq, clone_of 2, E_method (E_var 5, M_get, [])));
    e_case "p33_str_cmp_values"
      "EXPECT pass: StringSurrogate < StringSurrogate"
      (E_binary (B_lt, E_method (E_var 5, M_get, []), clone_of 2));
    e_case "p34_set_string_value"
      "EXPECT pass: String signal set with a StringSurrogate arg (the literal arg form is E0308)"
      (E_method (E_var 5, M_set, [ clone_of 2 ]));
    e_case "p35_ifelse_string_values"
      "EXPECT pass: both branches StringSurrogate"
      (E_method
         ( E_if_else (E_var 1, clone_of 2, E_method (E_var 5, M_get, [])),
           M_len,
           [] ));
    e_case "p36_let_string_clone"
      "EXPECT pass: let-bound StringSurrogate reused through clone (var_use on internal lets)"
      (E_block
         ( [ E_let (10, clone_of 2) ],
           E_method (E_method (E_var 10, M_clone, []), M_len, []) ));
    e_case "p37_loop_signal_break"
      "EXPECT pass: signal write inside a loop body, forced break suffix"
      (E_loop
         (E_block_unit [ E_method (E_var 3, M_set, [ fb 1.0 ]); E_break ]));
  ]

let r2_files () =
  Emit.crate_files ~name:"m20r2-probe" ~dep_prefix:"../../../../" r2_cases

let batch_files () =
  let samples =
    QCheck.Gen.generate ~n:1000
      ~rand:(Random.State.make [| 0x4d3230 |])
      (Gen.gen_target_m20 M20.genv)
  in
  Emit.crate_files ~name:"m20-batch" ~dep_prefix:"../../../"
    (Emit.batch_cases samples)

let usage = "usage: emit_m20 (r2|batch) <relative-file>\n"

(* Exit code as a value: 0 with the file on stdout, 2 with usage (an
   unknown mode or a file the crate does not contain). *)
let run argv =
  match argv with
  | _ :: "r2" :: rel :: [] ->
      Option.fold
        ~none:(usage, 2)
        ~some:(fun content -> (content, 0))
        (assoc_opt String.equal rel (r2_files ()))
  | _ :: "batch" :: rel :: [] ->
      Option.fold
        ~none:(usage, 2)
        ~some:(fun content -> (content, 0))
        (assoc_opt String.equal rel (batch_files ()))
  | _ -> (usage, 2)

let () =
  let out = run (Array.to_list Sys.argv) in
  print_string (fst out);
  exit (snd out)
