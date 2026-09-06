(* Exercise the production continuation after the first cargo process exits.
   Code 3 proves a driver timeout without compiling a Rust fixture. *)
let check first want_stage want_ref =
  let cfg = { (Rust_leg.default_config ~root:".") with resume_budget = 0 } in
  let sample : Sample.t =
    { mode = Taxonomy.Read_only; inputs = []; signals = [];
      target = Ast.T_bool; body = Ast.E_lit (Ast.L_bool true) }
  in
  Result.fold ~ok:(fun _ -> false)
    ~error:(fun failure ->
      let be = Legs.Be_rust failure in
      let text = "rust leg: " ^ Rust_leg.error_text failure.Rust_leg.rf_error in
      String.equal text (Legs.batch_error_text be)
      && match Pipeline.rows_fail Ref_leg.default_config 0 be [sample] with
         | [entry] ->
             let row = entry.Pipeline.e_row in
             let trace =
               { Correspond.tl_i = 0;
                 tl_steps = List.map Correspond.step_name entry.Pipeline.e_steps }
             in
             Bool.equal want_ref (not (String.equal row.Journal.jl_f ""))
             && (not want_ref || String.equal row.Journal.jl_f
                   (Obs.encode (Ref_leg.observe Ref_leg.default_config sample)))
             && Result.fold ~error:(fun _ -> false)
                  ~ok:(String.equal want_stage)
                  (Correspond.check_line 2 row trace)
         | [] | _ :: _ -> false)
    (Rust_leg.finish_run cfg ~name:"unused" ~jsonl:"/dev/null/missing"
       ~err:"/dev/null/missing" ~first [sample])

let () =
  let cases =
    [ "timeout budget is an execution failure", check 3 "leg_failed" true;
      "output read failure follows execution", check 0 "leg_failed" true;
      "compile failure stays a generator failure", check 101 "gen_bug" false ]
  in
  List.iter (fun (name, ok) -> print_endline ((if ok then "ok " else "FAIL ") ^ name)) cases;
  exit (if List.for_all snd cases then 0 else 1)
