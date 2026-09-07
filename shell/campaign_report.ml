(* M34: validate an unplanted campaign and reconstruct its construct groups.
   This module returns data and text. Only bin/m34.ml writes stdout/stderr. *)

open Prelude

type error =
  | E_minimum of int
  | E_journal of Pipeline.failure
  | E_trace of Pipeline.failure
  | E_correspond of Correspond.failure
  | E_plant of string
  | E_short of int * int
  | E_generator_count of int * int
  | E_generator_drift of int * string
  | E_campaign of Campaign.error
  | E_modes of int * int
  | E_no_adjudication

let error_text (e : error) : string =
  match e with
  | E_minimum n ->
      "minimum " ^ string_of_int n ^ " must be at least 1"
  | E_journal f -> "journal: " ^ Pipeline.failure_text f
  | E_trace f -> "trace: " ^ Pipeline.failure_text f
  | E_correspond f ->
      "correspondence at line "
      ^ nat_to_string (Correspond.failure_line f)
      ^ ": " ^ Correspond.failure_text f
  | E_plant p -> "campaign baseline requires plant none, found " ^ p
  | E_short (minimum, actual) ->
      "campaign has " ^ nat_to_string actual ^ " samples; minimum is "
      ^ nat_to_string minimum
  | E_generator_count (expected, actual) ->
      "generator drift: expected " ^ nat_to_string expected ^ " samples, drew "
      ^ nat_to_string actual
  | E_generator_drift (i, field) ->
      "generator drift at sample " ^ nat_to_string i ^ ": " ^ field
      ^ " does not match the seeded draw"
  | E_campaign e -> Campaign.error_text e
  | E_modes (read_only, signal_writing) ->
      "campaign requires both modes; read_only " ^ nat_to_string read_only
      ^ ", signal_writing " ^ nat_to_string signal_writing
  | E_no_adjudication ->
      "campaign contains only losses: no agree, known, or diverge result"

let default_minimum : int = 5000

(** A versioned, canonical constructor-count map. Labels keep the target,
    body, input types/initializers and signal types/initializers distinct.
    Tally ignores variable names and literal values. Mode belongs to the
    Campaign group key, outside this signature. *)
let counts_text (counts : (string * int) list) : string =
  joined ","
    (map
       (fun kv -> fst kv ^ "=" ^ nat_to_string (snd kv))
       (List.sort (fun a b -> String.compare (fst a) (fst b)) counts))

let binding_types (bs : Sample.binding list) : (string * int) list =
  fold (fun acc b -> Tally.ty_walk acc b.Sample.ty) [] bs

let binding_inits (bs : Sample.binding list) : (string * int) list =
  fold (fun acc b -> Tally.expr_walk acc b.Sample.init) [] bs

let constructor_sections (s : Sample.t) :
    (string * (string * int) list) list =
  [ ("target", Tally.ty_walk [] s.Sample.target);
    ("body", Tally.expr_walk [] s.Sample.body);
    ("input_type", binding_types s.Sample.inputs);
    ("input_init", binding_inits s.Sample.inputs);
    ("signal_type", binding_types s.Sample.signals);
    ("signal_init", binding_inits s.Sample.signals) ]

let signature_of (s : Sample.t) : string =
  "v1;"
  ^ joined ";"
      (map
         (fun part -> fst part ^ "{" ^ counts_text (snd part) ^ "}")
         (constructor_sections s))

(** This coverage describes generated constructs across all attempts,
    including losses. It does not claim that every constructor executed. *)
let coverage_text (samples : Sample.t list) : string =
  let add_count acc key count =
    (key, Tally.count key acc + count) :: List.remove_assoc key acc
  in
  let counts =
    fold
      (fun acc s ->
        fold
          (fun sofar part ->
            fold
              (fun tally kv ->
                add_count tally (fst part ^ "." ^ fst kv) (snd kv))
              sofar (snd part))
          acc (constructor_sections s))
      [] samples
  in
  let unique = len (List.sort_uniq String.compare (map signature_of samples)) in
  "\n## Construct coverage\n\nAll " ^ nat_to_string (len samples)
  ^ " attempts contribute, including losses. Counts describe generated "
  ^ "constructors and do not imply execution coverage. Unique v1 signatures "
  ^ "are counted across both modes; divergence groups also distinguish mode.\n\n"
  ^ "```text\nm34 signatures " ^ nat_to_string unique ^ " samples "
  ^ nat_to_string (len samples) ^ "\n" ^ Tally.report counts ^ "```\n"

(** Replay identity is stronger than a constructor signature. Every field
    recorded from the generated sample must match before any signature is
    constructed, including rows whose legs were lost. *)
let check_sample (i : int) (row : Journal.line) (s : Sample.t) :
    (unit, error) result =
  match () with
  | () when not (Int.equal row.Journal.jl_i i) ->
      Error (E_generator_drift (i, "index"))
  | () when
      not
        (String.equal row.Journal.jl_mode
           (Taxonomy.mode_name s.Sample.mode)) ->
      Error (E_generator_drift (i, "mode"))
  | () when not (Int.equal row.Journal.jl_size (Minimize.size_of s)) ->
      Error (E_generator_drift (i, "size"))
  | () when
      not (list_eq String.equal row.Journal.jl_env (Walk.let_lines s)) ->
      Error (E_generator_drift (i, "environment"))
  | () when not (String.equal row.Journal.jl_body (Walk.body_text s)) ->
      Error (E_generator_drift (i, "body"))
  | () -> Ok ()

let samples_of (rows : Journal.line list) (samples : Sample.t list) :
    ((Journal.line * Sample.t) list, error) result =
  let expected = len rows in
  let actual = len samples in
  let rec go i acc rs ss =
    match (rs, ss) with
    | [], [] -> Ok (rev acc)
    | [], _ :: _ -> Error (E_generator_count (expected, actual))
    | _ :: _, [] -> Error (E_generator_count (expected, actual))
    | r :: rrest, s :: srest ->
        Result.bind (check_sample i r s) (fun () ->
            go (i + 1) ((r, s) :: acc) rrest srest)
  in
  go 0 [] rows samples

type verified = {
  v_header : Journal.header;
  v_members : (Journal.line * Sample.t) list;
  v_report : Campaign.report;
}

(** Correspond.check validates both directions between journal cells and
    model transitions. Reconstructing the seed then proves that the program
    behind each row is the program whose signature enters the report. *)
let check ?(minimum = default_minimum) (jh : Journal.header)
    (rows : Journal.line list) (th : Correspond.trace_header)
    (traces : Correspond.trace_line list) : (verified, error) result =
  Result.bind
    (Result.map_error (fun e -> E_correspond e)
       (Correspond.check jh rows th traces))
    (fun _ ->
      match () with
      | () when minimum < 1 -> Error (E_minimum minimum)
      | () when not (String.equal jh.Journal.jh_plant (Plant.name Plant.No_plant)) ->
          Error (E_plant jh.Journal.jh_plant)
      | () when len rows < minimum -> Error (E_short (minimum, len rows))
      | () ->
          Result.bind
            (samples_of rows (Pipeline.draw (len rows) jh.Journal.jh_seed))
            (fun members ->
              let signatures = map (fun rs -> signature_of (snd rs)) members in
              Result.bind
                (Result.map_error (fun e -> E_campaign e)
                   (Campaign.analyze rows signatures))
                (fun r ->
                  let tally = r.Campaign.r_tally in
                  match () with
                  | () when
                      r.Campaign.r_read_only < 1
                      || r.Campaign.r_signal_writing < 1 ->
                      Error
                        (E_modes
                           (r.Campaign.r_read_only, r.Campaign.r_signal_writing))
                  | () when
                      tally.Journal.t_agree + tally.Journal.t_known
                      + tally.Journal.t_diverge < 1 ->
                      Error E_no_adjudication
                  | () ->
                      Ok
                        { v_header = jh; v_members = members; v_report = r })))

let read ?(minimum = default_minimum) (dir : string) :
    (verified, error) result =
  match () with
  | () when minimum < 1 -> Error (E_minimum minimum)
  | () ->
      Result.bind
        (Result.map_error (fun e -> E_journal e)
           (Pipeline.read_journal (Pipeline.journal_path dir)))
        (fun journal ->
          Result.bind
            (Result.map_error (fun e -> E_trace e)
               (Pipeline.read_trace (Pipeline.trace_path dir)))
            (fun trace ->
              check ~minimum (fst journal) (snd journal) (fst trace) (snd trace)))

(** M35 and plant controls receive the same validated row/sample pairs as
    the report. No consumer needs to parse a Rust body or trust its index. *)
let read_samples ?(minimum = default_minimum) (dir : string) :
    (Journal.header * (Journal.line * Sample.t) list, error) result =
  Result.map (fun v -> (v.v_header, v.v_members)) (read ~minimum dir)

let report ?(minimum = default_minimum) (dir : string) :
    (string, error) result =
  Result.map
    (fun v ->
      Campaign.markdown v.v_header v.v_report
      ^ coverage_text (map snd v.v_members))
    (read ~minimum dir)
