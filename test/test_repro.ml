(** Tests for [Repro]: the sha shape, the origin field and the rendered
    shape.  Nothing here spawns anything.  The renderer is pure, so this
    suite needs no process, no clone and no network, which is the reason
    ruling R1 put the renderer in core in the first place. *)

(** [say name ok] prints one result line and answers [ok].  The line is the
    only report a reader gets for a single test, so it carries the name. *)
let say name ok =
  print_string ((if ok then "ok " else "FAIL ") ^ name ^ "\n");
  ok

(** A small input that exercises every block.  Every field is filled,
    because OCaml refuses a record literal with a missing field and the
    renderer reads all of them. *)
let sample_input () =
  {
    Repro.rp_plant = "ref:display_sign";
    rp_origin = Repro.Origin_case "diverge:rendered:odd:ref";
    rp_clone_sha = String.make 40 'a';
    rp_oracle_sha = String.make 40 'b';
    rp_fuel = 24;
    rp_start_size = 6;
    rp_final_size = 1;
    rp_bindings = [];
    rp_body = "0.0";
    rp_js_src = "cx.hydrate(0.0)";
    rp_js_form = "direct";
    rp_rust = "R";
    rp_js = "J";
    rp_ref = "F";
    rp_verdict = "read_only diverge:rendered:odd:ref";
    rp_walk = "one\ntwo\n";
    rp_root = ".";
    rp_clone = "./../topcoat";
    rp_dir = "_emit/m30/out/ref:display_sign";
  }

(** [lines s] counts the newline terminated lines of [s].  The split leaves
    one empty tail piece after the last newline, so the count is one less
    than the number of pieces. *)
let lines s = Prelude.len (String.split_on_char '\n' s) - 1

(** Forty lowercase hex digits with the trailing newline of git are a sha. *)
let t_sha_ok () =
  say "sha 40 hex" (Result.is_ok (Repro.sha_of_line (String.make 40 'a' ^ "\n")))

(** Thirty nine digits are a truncated sha and must be refused. *)
let t_sha_short () =
  say "sha 39 hex" (Result.is_error (Repro.sha_of_line (String.make 39 'a')))

(** An uppercase sha is refused, so the provenance block has ONE spelling. *)
let t_sha_upper () =
  say "sha uppercase" (Result.is_error (Repro.sha_of_line (String.make 40 'A')))

(** A [-dirty] suffix is refused, which is what ruling R7 asks for. *)
let t_sha_dirty () =
  say "sha dirty suffix"
    (Result.is_error (Repro.sha_of_line (String.make 40 'a' ^ "-dirty")))

(** An empty line is refused, so a failed spawn cannot pass as a sha. *)
let t_sha_empty () = say "sha empty" (Result.is_error (Repro.sha_of_line ""))

(** The case origin renders the plant name it carries. *)
let t_origin_case () =
  say "origin case"
    (String.equal (Repro.origin_text (Repro.Origin_case "c")) "case c")

(** The seed origin renders the M31 seed, which is the second constructor. *)
let t_origin_seed () =
  say "origin seed"
    (String.equal (Repro.origin_text (Repro.Origin_seed 7)) "seed 7")

(** The file ends in exactly one newline, so a reader's editor adds none. *)
let t_one_newline () =
  let t = Repro.render (sample_input ()) in
  say "ends in one newline"
    (String.ends_with ~suffix:"\n" t && not (String.ends_with ~suffix:"\n\n" t))

(** The line count is fixed by the block arithmetic and not by inspection:
    2 title + 11 provenance + 6 program + 8 emitted js + 5 size + 7 witness
    + (5 + 2) trace + 10 reproduce + 4 what to look for = 60. *)
let t_line_count () =
  say "60 lines for no binding and a walk of two lines"
    (Int.equal (lines (Repro.render (sample_input ()))) 60)

(** The walk text reaches the rendered file, so the trace block is real. *)
let t_walk_verbatim () =
  let ls = String.split_on_char '\n' (Repro.render (sample_input ())) in
  let has w = Prelude.fold (fun seen l -> seen || String.equal l w) false ls in
  say "walk verbatim" (has "one" && has "two")

(** The planted sentence is one whole line of the rendered file, so a reader
    meets it before the program block. *)
let t_planted () =
  let target = Repro.planted (sample_input ()) in
  say "planted sentence"
    (Prelude.fold
       (fun seen l -> seen || String.equal l target)
       false
       (String.split_on_char '\n' (Repro.render (sample_input ()))))

(** With no plant the sentence changes, so the file never claims a plant it
    does not carry. *)
let t_unplanted () =
  let i = { (sample_input ()) with Repro.rp_plant = "none" } in
  say "unplanted sentence"
    (String.starts_with ~prefix:"No plant is injected" (Repro.planted i))

(** Both commands must retain overrides rather than selecting CLI defaults. *)
let t_replay_paths () =
  let i = { (sample_input ()) with
    Repro.rp_root = "../oracle copy";
    rp_clone = "../topcoat-alt";
    rp_dir = "_emit/m30/out/my repro";
  } in
  say "replay preserves paths"
    (String.equal (Repro.m30_command i)
       "dune exec bin/m30.exe -- repro '_emit/m30/out/my repro' --plant 'ref:display_sign' --fuel 24 --root '../oracle copy' --clone '../topcoat-alt'"
     && String.equal (Repro.m29_command i)
       "dune exec bin/m29.exe -- minimize '_emit/m29/out/ref:display_sign' --plant 'ref:display_sign' --fuel 24 --root '../oracle copy' --clone '../topcoat-alt'")

(** The entry point.  It runs the thirteen tests, prints the count line the
    gate reads and exits non zero on any failure. *)
let () =
  let all =
    [
      t_sha_ok (); t_sha_short (); t_sha_upper (); t_sha_dirty ();
      t_sha_empty (); t_origin_case (); t_origin_seed (); t_one_newline ();
      t_line_count (); t_walk_verbatim (); t_planted (); t_unplanted (); t_replay_paths ();
    ]
  in
  print_string
    ("test_repro: "
    ^ string_of_int (Prelude.fold (fun n b -> if b then n + 1 else n) 0 all)
    ^ "/" ^ string_of_int (Prelude.len all) ^ "\n");
  exit (if Prelude.fold (fun a b -> a && b) true all then 0 else 1)
