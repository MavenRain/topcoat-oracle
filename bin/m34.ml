(* M34 campaign report CLI. Build the entire validated report before writing
   stdout, so any failure leaves redirected output empty. *)

type failure = F_usage of string | F_report of Campaign_report.error

let usage () = "m34 report <dir> [--minimum N]"

let run (dir : string) (minimum : int) : (string, failure) result =
  Result.map_error (fun e -> F_report e)
    (Campaign_report.report ~minimum dir)

let job (argv : string list) : (string, failure) result =
  match argv with
  | [ _; "report"; dir ] -> run dir Campaign_report.default_minimum
  | [ _; "report"; dir; "--minimum"; value ] ->
      Option.fold
        ~none:(Error (F_usage ("--minimum requires a positive integer; " ^ usage ())))
        ~some:(fun n -> run dir n)
        (Walk.positive_opt value)
  | [] | [ _ ] | [ _; _ ] | [ _; _; _ ] | [ _; _; _; _ ]
  | _ :: _ :: _ :: _ :: _ :: _ -> Error (F_usage (usage ()))

let main () : unit =
  Result.fold
    ~ok:print_string
    ~error:(fun f ->
      match f with
      | F_usage text ->
          prerr_string ("m34 usage: " ^ text ^ "\n");
          exit 2
      | F_report e ->
          prerr_string ("m34 failure: " ^ Campaign_report.error_text e ^ "\n");
          exit 1)
    (job (Array.to_list Sys.argv))

let () = main ()
