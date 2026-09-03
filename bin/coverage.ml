(* M22 coverage report CLI (DESIGN.md M22).

   A thin main.  Every decision lives in shell/cover.ml, so the whole
   report is testable without a process: Cover.main takes the argv
   list and returns the two streams and the exit code.  There is no
   file IO here on purpose;  the caller redirects.

   The module is `coverage` and the library module is `Cover`,
   because oracle_shell is (wrapped false) and a `Coverage` module in
   both places would collide. *)

let () =
  let out = Cover.main Ops.printer_renderer (Array.to_list Sys.argv) in
  print_string out.Cover.o_stdout;
  prerr_string out.Cover.o_stderr;
  flush stdout;
  flush stderr;
  exit out.Cover.o_code
