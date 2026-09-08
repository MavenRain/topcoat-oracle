(* Five hand-derived signal writers for the isolated M36 re-pin check. *)
let ( let* ) = Result.bind
let need yes why = if yes then Ok () else Error why

type case = {
  name : string;
  sample : Sample.t;
  expected : Obs.observation;
}

type row = {
  index : int;
  js_index : int;
  rust : Obs.observation;
  js : Obs.observation;
  reference : Obs.observation;
}

let number hi = Ast.E_lit (Ast.L_f64_bits (hi, 0))

let writer name ty init method_ inputs args value =
  {
    name;
    sample =
      {
        Sample.mode = Taxonomy.Signal_writing;
        inputs;
        signals = [ { Sample.id = 3; ty; init } ];
        target = Ast.T_unit;
        body = Ast.E_method (Ast.E_var 3, method_, args);
      };
    expected =
      { Obs.outcome = Obs.O_value Obs.V_unit; rendered = "";
        signals = [ (3, value) ] };
  }

(* These constants are IEEE binary64 high halves, derived from 1.5 and
   2.5 directly. Neither the interpreter nor another leg sets expectations. *)
let cases () =
  [
    writer "set" Ast.T_f64 (number 0x3ff80000) Ast.M_set []
      [ number 0x40040000 ] (Obs.V_f64_bits (0x40040000, 0));
    writer "toggle" Ast.T_bool (Ast.E_lit (Ast.L_bool false)) Ast.M_toggle
      [] [] (Obs.V_bool true);
    writer "increment" Ast.T_f64 (number 0x3ff80000) Ast.M_increment [] []
      (Obs.V_f64_bits (0x40040000, 0));
    writer "decrement" Ast.T_f64 (number 0x40040000) Ast.M_decrement [] []
      (Obs.V_f64_bits (0x3ff80000, 0));
    writer "push_str" Ast.T_string (Ast.E_lit (Ast.L_str "a")) Ast.M_push_str
      [ { Sample.id = 0; ty = Ast.T_string; init = Ast.E_lit (Ast.L_str "b") } ]
      [ Ast.E_var 0 ] (Obs.V_str "ab");
  ]

let check_wf c =
  let s = c.sample in
  let* () = List.fold_left
      (fun acc (b : Sample.binding) ->
        let* () = acc in
        let* ty = Result.map_error
            (fun e -> c.name ^ " init: " ^ Wf.wf_error_code e)
            (Wf.check_top [] b.Sample.init) in
        need (Ast.ty_eq ty b.Sample.ty) (c.name ^ " init type mismatch"))
      (Ok ()) (List.append s.Sample.inputs s.Sample.signals) in
  let* ty = Result.map_error
      (fun e -> c.name ^ " body: " ^ Wf.wf_error_code e)
      (Wf.check_top (Sample.wf_env s) s.Sample.body) in
  let* () = need (Ast.ty_eq ty s.Sample.target) (c.name ^ " target mismatch") in
  need (Sample.mode_ok s) (c.name ^ " mode mismatch")

let check_cases cs =
  List.fold_left (fun acc c -> let* () = acc in check_wf c) (Ok ()) cs

let signal_panic obs =
  match obs.Obs.outcome with
  | Obs.O_panic (Obs.P_signal_write, _) -> true
  | Obs.O_panic ((Obs.P_unwrap | Obs.P_expect | Obs.P_unwrap_err
      | Obs.P_expect_err | Obs.P_other), _)
  | Obs.O_value _ | Obs.O_no_terminate -> false

let exact name leg expected actual =
  need (String.equal (Obs.encode expected) (Obs.encode actual))
    (name ^ " " ^ leg ^ " expected " ^ Obs.encode expected
     ^ ", got " ^ Obs.encode actual)

let validate_row i c r =
  let* () = need (Int.equal r.index i && Int.equal r.js_index i)
      (c.name ^ " case index mismatch: Rust " ^ string_of_int r.index
       ^ ", JS " ^ string_of_int r.js_index ^ ", expected " ^ string_of_int i) in
  let* () = need (signal_panic r.rust)
      (c.name ^ " Rust expected signal_write panic, got " ^ Obs.encode r.rust) in
  let* () = exact c.name "JS" c.expected r.js in
  let* () = exact c.name "reference" c.expected r.reference in
  let verdict = Differ.verdict Taxonomy.Signal_writing (Known.allow ())
      { Differ.rust = Differ.Present r.rust; js = Differ.Present r.js;
        reference = Differ.Present r.reference } in
  match verdict with
  | Differ.Agree ->
      Ok (c.name ^ " R=" ^ Obs.encode r.rust ^ " J=" ^ Obs.encode r.js
          ^ " F=" ^ Obs.encode r.reference ^ " agree")
  | Differ.Diverge (_, _) | Differ.Known _ | Differ.Leg_fail (_, _) ->
      Error (c.name ^ " expected agree, got " ^ Differ.verdict_text verdict)

let validate cs rows =
  let* () = need (Int.equal (List.length cs) 5 && Int.equal (List.length rows) 5)
      ("expected five cases and rows, got " ^ string_of_int (List.length cs)
       ^ " cases and " ^ string_of_int (List.length rows) ^ " rows") in
  let rec walk i remaining actual =
    match remaining, actual with
    | [], [] -> Ok []
    | [], _ :: _ | _ :: _, [] -> Error "case and row count mismatch"
    | c :: more, r :: rest ->
        let* line = validate_row i c r in
        Result.map (fun lines -> line :: lines) (walk (i + 1) more rest)
  in
  walk 0 cs rows

let rows_of cfg pairs js_lines =
  let* () = need
      (Int.equal (List.length pairs) 5 && Int.equal (List.length js_lines) 5)
      ("expected five Rust and JS rows, got " ^ string_of_int (List.length pairs)
       ^ " Rust and " ^ string_of_int (List.length js_lines) ^ " JS rows") in
  let rec walk ps js =
    match ps, js with
    | [], [] -> Ok []
    | [], _ :: _ | _ :: _, [] -> Error "Rust and JS row count mismatch"
    | (s, d) :: more, j :: rest ->
        let* observation =
          match j.Wire_js.jl_body with
          | Wire_js.Jl_obs (obs, _) -> Ok obs
          | Wire_js.Jl_js_error (_, _) | Wire_js.Jl_skipped _
          | Wire_js.Jl_driver_error (_, _) | Wire_js.Jl_lossy _ ->
              Error ("JS case " ^ string_of_int j.Wire_js.jl_case
                     ^ " has no observation: " ^ Js_leg.cell j)
        in
        let row =
          { index = d.Wire.d_case; js_index = j.Wire_js.jl_case;
            rust = d.Wire.d_obs; js = observation;
            reference = Ref_leg.observe cfg s } in
        Result.map (fun rows -> row :: rows) (walk more rest)
  in
  walk pairs js_lines

let run root clone out =
  let* () = need
      (not (Filename.is_relative root) && String.equal (Filename.basename root) "oracle"
       && String.equal clone (Filename.concat (Filename.dirname root) "topcoat"))
      "root and clone must be absolute sibling paths named oracle and topcoat" in
  let* () = need (String.equal out (root ^ "/_emit/m36/out/probe"))
      "out must be <root>/_emit/m36/out/probe for the six-level dependency prefix" in
  let cs = cases () in
  let* () = check_cases cs in
  let cfg = { (Legs.default_config ~root ~clone ~out Plant.No_plant)
              with Legs.l_name = "m36probe" } in
  let* pairs, js_lines = Result.map_error Legs.batch_error_text
      (Legs.legs_lines cfg ~dir:(Legs.start_dir cfg) (List.map (fun c -> c.sample) cs)) in
  let* rows = rows_of cfg.Legs.l_ref pairs js_lines in
  let* lines = validate cs rows in
  Ok (List.append lines [ "m36 signal writers 5 verified" ])

(* Adversarial checks exercise the production validator without spawning any
   leg. In Signal_writing mode Differ alone ignores the Rust panic class. *)
let self_test () =
  let cs = cases () in
  let* () = check_cases cs in
  let rows = List.mapi
      (fun i c ->
        { index = i; js_index = i;
          rust = { Obs.outcome = Obs.O_panic (Obs.P_signal_write, "expected");
                   rendered = ""; signals = [] };
          js = c.expected; reference = c.expected }) cs in
  let* lines = validate cs rows in
  let* () = need (Int.equal (List.length lines) 5) "baseline validator failed" in
  let* () = List.fold_left
      (fun acc c ->
        let* () = acc in
        let built = Driver.add_case Driver.empty_built c.sample in
        let* () = need (Int.equal built.Driver.kept 1) (c.name ^ " driver dropped fixture") in
        exact c.name "reference fixture" c.expected
          (Ref_leg.observe Ref_leg.default_config c.sample)) (Ok ()) cs in
  let rejects label bad =
    Result.fold ~ok:(fun _ -> Error (label ^ " was accepted"))
      ~error:(fun _ -> Ok ()) (validate cs bad) in
  let change_first f = List.mapi (fun i r -> if Int.equal i 0 then f r else r) rows in
  let wrong = { Obs.outcome = Obs.O_value Obs.V_unit; rendered = "";
                signals = [ (3, Obs.V_f64_bits (0x3ff80000, 0)) ] } in
  let* () = rejects "missing row" (List.filter (fun r -> not (Int.equal r.index 0)) rows) in
  let* () = rejects "extra row" (List.append rows rows) in
  let* () = rejects "wrong Rust class"
      (change_first (fun r -> { r with rust = { r.rust with
           Obs.outcome = Obs.O_panic (Obs.P_other, "expected") } })) in
  let* () = rejects "wrong JS state" (change_first (fun r -> { r with js = wrong })) in
  let* () = rejects "wrong reference state"
      (change_first (fun r -> { r with reference = wrong })) in
  let* () = rejects "both states wrong but agreeing"
      (change_first (fun r -> { r with js = wrong; reference = wrong })) in
  let* () = rejects "wrong case index" (change_first (fun r -> { r with index = 1 })) in
  let* () = rejects "wrong JS case index" (change_first (fun r -> { r with js_index = 1 })) in
  Ok [ "m36 probe validator 9 checks verified" ]

let main args =
  match args with
  | [ _; root; clone; out ] -> run root clone out
  | [ _; "--self-test" ] -> self_test ()
  | [] | _ :: _ -> Error "usage: probe.exe <root> <clone> <out>"

let () =
  Result.fold
    ~ok:(List.iter print_endline)
    ~error:(fun why -> prerr_endline ("m36 probe: " ^ why); exit 1)
    (main (Array.to_list Sys.argv))
