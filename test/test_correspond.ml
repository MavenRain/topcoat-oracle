(** test_correspond: the M32 correspondence checker.  Thirteen tests, no
    framework, one line per test and a non zero exit on any red, after
    test/test_journal.ml. *)

let say name ok =
  print_string ((if ok then "ok " else "FAIL ") ^ name ^ "\n");
  ok

let a_header () : Journal.header =
  { Journal.jh_seed = 5059377; Journal.jh_batch = 100;
    Journal.jh_plant = "none"; Journal.jh_topcoat = "0123456789abcdef0123456789abcdef01234567" }

let a_trace_header () : Correspond.trace_header =
  { Correspond.th_seed = 5059377; Correspond.th_batch = 100;
    Correspond.th_plant = "none";
    Correspond.th_topcoat = "0123456789abcdef0123456789abcdef01234567" }

let a_row (i : int) (verdict : string) (r : string) (j : string) (f : string) :
    Journal.line =
  { Journal.jl_i = i; Journal.jl_mode = "read_only"; Journal.jl_size = 3;
    Journal.jl_verdict = verdict; Journal.jl_r = r; Journal.jl_j = j;
    Journal.jl_f = f; Journal.jl_env = []; Journal.jl_body = "()" }

let a_trace (i : int) (steps : string list) : Correspond.trace_line =
  { Correspond.tl_i = i; Correspond.tl_steps = steps }

let of_kind (k : Correspond.kind) (rp : Correspond.presence)
    (jp : Correspond.presence) (fp : Correspond.presence) (h : string) :
    string list =
  Prelude.map Correspond.step_name
    (Correspond.steps_of
       { Correspond.ev_kind = k; Correspond.ev_rust = rp;
         Correspond.ev_js = jp; Correspond.ev_ref = fp;
         Correspond.ev_head = h })

let cell = "Vu|r0:|"

(* 1  every name of every step round trips through step_of_name. *)
let t_names () =
  say "step names round trip"
    (Prelude.fold
       (fun acc t ->
         acc
         && Option.fold ~none:false
              ~some:(fun t1 ->
                String.equal (Correspond.step_name t1) (Correspond.step_name t))
              (Correspond.step_of_name (Correspond.step_name t)))
       true
       (Correspond.all_steps ()))

(* 2  the 19 names are distinct, so step_of_name is a function. *)
let t_distinct () =
  let names = Prelude.map Correspond.step_name (Correspond.all_steps ()) in
  say "step names are distinct"
    (Int.equal (Prelude.len names) 19
    && Prelude.fold
         (fun acc n ->
           acc
           && Int.equal 1
                (Prelude.fold
                   (fun k m -> match () with
                              | () when String.equal m n -> k + 1
                              | () -> k)
                   0 names))
         true names)

(* 3  a K5 agree row corresponds and lands in dropped_agree. *)
let t_agree () =
  let steps =
    of_kind Correspond.Kd_paired Correspond.Cell_present
      Correspond.Cell_present Correspond.Cell_present "agree"
  in
  say "agree row"
    (Result.fold ~error:(fun _ -> false)
       ~ok:(fun (r : Correspond.report) ->
         Int.equal r.Correspond.rp_dropped_agree 1
         && Int.equal r.Correspond.rp_lines 1)
       (Correspond.check (a_header ())
          [ a_row 0 "agree" cell cell cell ]
          (a_trace_header ())
          [ a_trace 0 steps ]))

(* 4  a leg_fail:js row lands in leg_failed. *)
let t_leg_fail () =
  let v = "leg_fail:js:skipped:no_js" in
  let steps =
    of_kind Correspond.Kd_paired Correspond.Cell_present
      Correspond.Cell_absent Correspond.Cell_present "leg_fail"
  in
  say "leg_fail row"
    (Result.fold ~error:(fun _ -> false)
       ~ok:(fun (r : Correspond.report) ->
         Int.equal r.Correspond.rp_leg_failed 1)
       (Correspond.check (a_header ())
          [ a_row 0 v cell "skipped:no_js" cell ]
          (a_trace_header ())
          [ a_trace 0 steps ]))

(* 5  a diverge row ends in minimizing_hi and is NOT required to be terminal. *)
let t_diverge () =
  let steps =
    of_kind Correspond.Kd_paired Correspond.Cell_present
      Correspond.Cell_present Correspond.Cell_present "diverge"
  in
  say "diverge row"
    (Result.fold ~error:(fun _ -> false)
       ~ok:(fun (r : Correspond.report) ->
         Int.equal r.Correspond.rp_minimizing_hi 1)
       (Correspond.check (a_header ())
          [ a_row 0 "diverge:value:odd:js" cell cell cell ]
          (a_trace_header ())
          [ a_trace 0 steps ]))

(* 6  the N3 mutation is rejected: a removed exec step breaks the walk. *)
let t_missing_step () =
  say "missing exec step"
    (Result.fold ~ok:(fun _ -> false)
       ~error:(fun f ->
         String.equal (Correspond.failure_text f)
           "the step exec_ref_ok is not an edge from stage=compiled rust=o js=p ref=p verdict=none")
       (Correspond.check (a_header ())
          [ a_row 0 "agree" cell cell cell ]
          (a_trace_header ())
          [ a_trace 0
              [ "shape_ok"; "print_ok"; "compile_ok"; "exec_rust_ok";
                "exec_ref_ok"; "judge_agree" ] ]))

(* 7  the N1 mutation is rejected: a valid walk with the wrong judge step. *)
let t_wrong_judge () =
  say "wrong judge step"
    (Result.fold ~ok:(fun _ -> false)
       ~error:(fun f ->
         String.equal (Correspond.failure_text f)
           "the judge step judge_known does not match the verdict head agree")
       (Correspond.check (a_header ())
          [ a_row 0 "agree" cell cell cell ]
          (a_trace_header ())
          [ a_trace 0
              [ "shape_ok"; "print_ok"; "compile_ok"; "exec_rust_ok";
                "exec_js_ok"; "exec_ref_ok"; "judge_known" ] ]))

(* 8  the R9b finding: a Present rust cell with an exec_rust_crash step is
      rejected by check C3, before any judge step is read. *)
let t_absent_rust () =
  say "rust cell against rust step"
    (Result.fold ~ok:(fun _ -> false)
       ~error:(fun f ->
         String.equal (Correspond.failure_text f)
           "the rust leg has a cell in the journal and did not run in the trace")
       (Correspond.check (a_header ())
          [ a_row 0 "agree" cell cell cell ]
          (a_trace_header ())
          [ a_trace 0
              [ "shape_ok"; "print_ok"; "compile_ok"; "exec_rust_crash";
                "exec_js_crash"; "exec_ref_ok"; "judge_infra" ] ]))

(* 9  the trace codec round trips a header and a line. *)
let t_codec () =
  let h = a_trace_header () in
  let l = a_trace 7 [ "shape_ok"; "print_ok"; "compile_fail" ] in
  say "trace codec round trip"
    (Result.fold ~error:(fun _ -> false)
       ~ok:(fun hl ->
         let th = fst hl in
         Int.equal th.Correspond.th_seed 5059377
         && Int.equal th.Correspond.th_batch 100
         && String.equal th.Correspond.th_plant "none"
         && String.equal th.Correspond.th_topcoat
              "0123456789abcdef0123456789abcdef01234567"
         && Prelude.fold
              (fun acc (t : Correspond.trace_line) ->
                acc && Int.equal t.Correspond.tl_i 7
                && Int.equal (Prelude.len t.Correspond.tl_steps) 3)
              true (snd hl)
         && Int.equal (Prelude.len (snd hl)) 1)
       (Correspond.decode_trace
          [ Correspond.encode_trace_header h; Correspond.encode_trace_line l ]))

(* 10  a K4 no_line row: the crate ran, the rust leg wrote no line, the two
       product legs crash, the reference answers, and judge_infra ends the
       world in leg_failed.  C4 accepts because judge_of_head "no_line" is
       Some Judge_infra. *)
let t_no_line () =
  let steps =
    of_kind Correspond.Kd_no_line Correspond.Cell_absent
      Correspond.Cell_absent Correspond.Cell_present "no_line"
  in
  say "no_line row"
    (Result.fold ~error:(fun _ -> false)
       ~ok:(fun (r : Correspond.report) ->
         Int.equal r.Correspond.rp_leg_failed 1
         && Int.equal r.Correspond.rp_lines 1)
       (Correspond.check (a_header ())
          [ a_row 0 "no_line" "" "" cell ]
          (a_trace_header ())
          [ a_trace 0 steps ]))

(* 11  a K3 batch_fail row that lost its leg AFTER the crate ran.  The head
       "batch_fail" asks for no judge step, and judge_free accepts the
       judge_infra the walk really took, so the row lands in leg_failed. *)
let t_leg_lost () =
  let v = "batch_fail:rust leg: the driver exited 1" in
  let steps =
    of_kind Correspond.Kd_leg_lost Correspond.Cell_absent
      Correspond.Cell_absent Correspond.Cell_present "batch_fail"
  in
  say "leg_lost row"
    (Result.fold ~error:(fun _ -> false)
       ~ok:(fun (r : Correspond.report) ->
         Int.equal r.Correspond.rp_leg_failed 1
         && Int.equal r.Correspond.rp_lines 1)
       (Correspond.check (a_header ())
          [ a_row 0 v "" "" cell ]
          (a_trace_header ())
          [ a_trace 0 steps ]))

(* 12  a K2 batch_fail row whose trace line was rewritten with the K3 step
       tail with a crashed reference is refused by check C5.  Every cell of
       the row is empty, the walk is valid, C3 sees three absent cells and
       judge_free accepts the judge_infra, so C5 on the f cell is the ONLY
       check that can refuse the relabelling of a gen_bug batch as an
       oracle_bug batch.  The other K3 tail, the one with a live reference
       that ends exec_ref_ok, is refused earlier and by C3, because
       exec_ref_ok against an empty f cell is a cell failure. *)
let t_batch_fail_crash () =
  let v = "batch_fail:rust leg: the driver exited 1" in
  say "batch_fail rewritten with the crash tail"
    (Result.fold ~ok:(fun _ -> false)
       ~error:(fun f ->
         String.equal (Correspond.failure_text f)
           "a batch_fail verdict must not end in oracle_bug")
       (Correspond.check (a_header ())
          [ a_row 0 v "" "" "" ]
          (a_trace_header ())
          [ a_trace 0
              [ "shape_ok"; "print_ok"; "compile_ok"; "exec_rust_crash";
                "exec_js_crash"; "exec_ref_crash"; "judge_infra" ] ]))

(* 13  a K1 dropped row whose trace line was rewritten to ["shape_fail"] is
       refused by the front of walk rule of C5.  The walk alone accepts that
       list, because Shape_fail is an edge from Generated into the terminal
       Gen_bug, C3 sees three absent cells, C4 and C6 ask nothing of a
       "dropped" head and C5 on the end stage lists "gen_bug", so the front
       rule is the ONLY check that can refuse it.  The same rewrite on the
       empty f cell batch_fail head is refused by the same rule. *)
let t_shape_fail_front () =
  say "shape_fail at the front"
    (Result.fold ~ok:(fun _ -> false)
       ~error:(fun f ->
         String.equal (Correspond.failure_text f)
           "a dropped verdict with an empty f cell holds shape_fail at step 1")
       (Correspond.check (a_header ())
          [ a_row 0 "dropped" "" "" "" ]
          (a_trace_header ())
          [ a_trace 0 [ "shape_fail" ] ]))

let () =
  let all =
    [ t_names (); t_distinct (); t_agree (); t_leg_fail (); t_diverge ();
      t_missing_step (); t_wrong_judge (); t_absent_rust (); t_codec ();
      t_no_line (); t_leg_lost (); t_batch_fail_crash ();
      t_shape_fail_front () ]
  in
  print_string
    ("test_correspond: "
    ^ string_of_int (Prelude.fold (fun n b -> if b then n + 1 else n) 0 all)
    ^ "/" ^ string_of_int (Prelude.len all) ^ "\n");
  exit (if Prelude.fold (fun a b -> a && b) true all then 0 else 1)
