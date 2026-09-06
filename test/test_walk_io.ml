(** Output-directory regressions.  These tests use temporary files only;
    the missing harness stops the walk before either external leg spawns. *)
let check name ok =
  print_string ((if ok then "ok " else "FAIL ") ^ name ^ "\n");
  ok

(* Exercise the actual shell parser without executing the replay command. *)
let shell_roundtrip s =
  let command = "printf '%s' " ^ Repro.shell_arg s in
  let ic = Unix.open_process_args_in "/bin/sh" [| "sh"; "-c"; command |] in
  let actual = In_channel.input_all ic in
  let status = Unix.close_process_in ic in
  status = Unix.WEXITED 0 && String.equal actual s

let () =
  let quoted = check "shell arguments round-trip"
    (List.for_all shell_roundtrip
      [ ""; "_emit/m30/out/my repro"; "../oracle's clone";
        "$(printf expanded)`printf expanded`; * ? $HOME"; "line one\nline two" ]) in
  let base = Filename.temp_file "oracle-walk-" "" in
  Unix.unlink base;
  Unix.mkdir base 0o700;
  let parent = base ^ "/out" in
  let dir = parent ^ "/ref:display_sign" in
  let flags =
    {
      Walk.fl_root = base ^ "/missing-root";
      fl_clone = base ^ "/missing-clone";
      fl_plant = Plant.Ref Plant.Rp_display_sign;
      fl_fuel = 1;
    }
  in
  let reached_harness =
    Result.fold ~ok:(fun _ -> false)
      ~error:(fun e ->
        match e with
        | Walk.F_start why ->
            String.starts_with ~prefix:"rust leg: read failed at " why
        | Walk.F_flag _ | Walk.F_no_case _ | Walk.F_no_diverge _ -> false)
      (Walk.run ~dir flags)
  in
  let fresh = check "fresh walk reaches harness read" reached_harness in
  let exists = check "nested output exists" (Sys.is_directory dir) in
  let repeat =
    check "existing directory is accepted"
      (Result.is_ok (Rust_leg.mkdir_parents dir))
  in
  let file = base ^ "/file" in
  let wrote = check "file fixture" (Result.is_ok (Rust_leg.write_file file "x")) in
  let collision =
    check "file is not a directory"
      (Result.is_error (Rust_leg.mkdir_parents file))
  in
  let ancestor =
    check "file cannot be a parent"
      (Result.is_error (Rust_leg.mkdir_parents (file ^ "/child")))
  in
  Unix.unlink file;
  List.iter Unix.rmdir [ dir ^ "/rs/src"; dir ^ "/rs"; dir; parent; base ];
  exit (if quoted && fresh && exists && repeat && wrote && collision && ancestor then 0 else 1)
