(* M34 adds two corpus-backed plants beyond the display and debug operations
   reached by the frozen seed table.  These records are local to this command;
   the global Plant vocabulary and the older seed gates keep their meanings. *)

type plant = Add_sign | Length_plus_one

type config = {
  cp_campaign : string;
  cp_out : string;
  cp_root : string;
  cp_clone : string;
}

type error =
  | E_campaign of string
  | E_witness of string
  | E_output of string
  | E_provenance of string
  | E_control of string * int * string
  | E_plant of string * int * string

(** Every refusal names the operation or the input that prevented evidence. *)
let error_text (e : error) : string =
  match e with
  | E_campaign s -> "campaign: " ^ s
  | E_witness s -> "no corpus witness for " ^ s
  | E_output s -> "output: " ^ s
  | E_provenance s -> "provenance: " ^ s
  | E_control (p, i, s) ->
      p ^ " index " ^ Prelude.nat_to_string i ^ " control: " ^ s
  | E_plant (p, i, s) ->
      p ^ " index " ^ Prelude.nat_to_string i ^ " planted: " ^ s

(** Stable names also identify each operation in the campaign evidence. *)
let name (p : plant) : string =
  match p with
  | Add_sign -> "ref:add_sign"
  | Length_plus_one -> "ref:length_plus_one"

(** String length reaches f_of_int in core/interp.ml's M_len arm. *)
let op_name (p : plant) : string =
  match p with Add_sign -> "f_add" | Length_plus_one -> "f_of_int"

(** Direct child directories keep witness crates at the normal five levels. *)
let stem (p : plant) : string =
  match p with Add_sign -> "add" | Length_plus_one -> "length"

(** Each plant replaces exactly one shipped closure and retains all others. *)
let ops (p : plant) : Interp.ops =
  match p with
  | Add_sign ->
      {
        Ops.interp_ops with
        Interp.f_add =
          (fun ah al bh bl ->
            let v = Ops.interp_ops.Interp.f_add ah al bh bl in
            (fst v lxor 0x80000000, snd v));
      }
  | Length_plus_one ->
      {
        Ops.interp_ops with
        Interp.f_of_int =
          (fun n ->
            let v = Ops.interp_ops.Interp.f_of_int n in
            Ops.interp_ops.Interp.f_add (fst v) (snd v) 0x3ff00000 0);
      }

(** Read-only witnesses identify the reference as the third, differing party. *)
let expected_read_only (v : Differ.verdict) : bool =
  match v with
  | Differ.Diverge (channel, split) ->
      (Differ.channel_eq channel Differ.Ch_value
       || Differ.channel_eq channel Differ.Ch_rendered)
      && Differ.split_eq split (Differ.Odd Differ.L_ref)
  | Differ.Agree | Differ.Known _ | Differ.Leg_fail _ -> false

(** The addition plant also reaches signal increment in the agreeing corpus.
    That mode compares JS with the reference, and only its final signals
    channel is accepted here.  String length keeps its read-only witness. *)
let expected_for (p : plant) (mode : Taxonomy.mode) (v : Differ.verdict) : bool =
  match mode with
  | Taxonomy.Read_only -> expected_read_only v
  | Taxonomy.Signal_writing ->
      (match p with
      | Length_plus_one -> false
      | Add_sign ->
          (match v with
          | Differ.Diverge (channel, split) ->
              Differ.channel_eq channel Differ.Ch_signals
              && Differ.split_eq split Differ.Two_way
          | Differ.Agree | Differ.Known _ | Differ.Leg_fail _ -> false))

(** Failure text describes the same plant and mode fence used for selection. *)
let expected_description (p : plant) (mode : Taxonomy.mode) : string =
  match mode with
  | Taxonomy.Read_only -> "value or rendered odd:ref"
  | Taxonomy.Signal_writing ->
      (match p with
      | Add_sign -> "signals two_way"
      | Length_plus_one ->
          "a read_only sample with value or rendered odd:ref")

(** Selection is pure: it reads neither files nor processes.  Literal presence
    alone cannot qualify a row; executing the changed closure must alter its
    allowed observation channel.  The stored reference must still match too. *)
let eligible (p : plant) (row : Journal.line) (sample : Sample.t) : bool =
  String.equal row.Journal.jl_verdict "agree"
  &&
  let base = Ref_leg.observe Ref_leg.default_config sample in
  String.equal row.Journal.jl_f (Obs.encode base)
  &&
  let changed =
    Ref_leg.observe { Ref_leg.default_config with Ref_leg.ops = ops p } sample
  in
  expected_for p sample.Sample.mode
    (Differ.verdict sample.Sample.mode (Known.allow ())
       {
         Differ.rust = Differ.Present base;
         js = Differ.Present base;
         reference = Differ.Present changed;
       })

(** Pick the first qualifying corpus row in validated journal order. *)
let rec select (p : plant) (rows : (Journal.line * Sample.t) list) :
    (Journal.line * Sample.t, error) result =
  match rows with
  | [] -> Error (E_witness (name p ^ " (" ^ op_name p ^ ")"))
  | row :: rest ->
      if eligible p (fst row) (snd row) then Ok row else select p rest

(** One sample must produce exactly one answer; infrastructure losses are errors. *)
let run_one (cfg : Legs.config) (dir : string) (sample : Sample.t) :
    (Differ.verdict, string) result =
  match Legs.run_batch cfg ~dir [ sample ] with
  | [ Minimize.A_verdict v ] -> Ok v
  | [ Minimize.A_no_verdict s ] -> Error s
  | [] -> Error "the legs answered no row"
  | _ :: _ :: _ -> Error "the legs answered more than one row"

(** The global plant stays absent in both runs, so the JS and Rust legs receive
    the same configuration.  Only the reference operation record changes. *)
let run_witness (cfg : Legs.config) (out : string) (p : plant)
    (row : Journal.line) (sample : Sample.t) : (string, error) result =
  let i = row.Journal.jl_i in
  let n = name p in
  let control = { cfg with Legs.l_name = "m34_" ^ stem p ^ "_control" } in
  Result.bind
    (Result.map_error (fun s -> E_control (n, i, s))
       (run_one control (out ^ "/" ^ stem p ^ "-control") sample))
    (fun before ->
      match before with
      | Differ.Diverge _ | Differ.Known _ | Differ.Leg_fail _ ->
          Error (E_control (n, i, "expected agree, got " ^ Differ.verdict_text before))
      | Differ.Agree ->
          let changed =
            {
              cfg with
              Legs.l_name = "m34_" ^ stem p ^ "_planted";
              l_ref = { cfg.Legs.l_ref with Ref_leg.ops = ops p };
            }
          in
          Result.bind
            (Result.map_error (fun s -> E_plant (n, i, s))
               (run_one changed (out ^ "/" ^ stem p ^ "-planted") sample))
            (fun after ->
              if expected_for p sample.Sample.mode after then
                Ok
                  ("m34 plant " ^ n ^ " op " ^ op_name p ^ " index "
                 ^ Prelude.nat_to_string i ^ " control agree planted "
                 ^ Differ.verdict_text after ^ "\n")
              else
                Error
                  (E_plant
                     ( n, i,
                       "expected " ^ expected_description p sample.Sample.mode
                       ^ ", got "
                       ^ Differ.verdict_text after ))))

(** A witness must use the clone revision named by the baseline campaign. *)
let check_clone (cfg : Legs.config) (out : string) (clone : string)
    (header : Journal.header) : (unit, error) result =
  Result.bind
    (Result.map_error
       (fun e -> E_provenance (Provenance.error_text e))
       (Provenance.read_sha cfg.Legs.l_rust ~out ~name:"topcoat" ~repo:clone))
    (fun sha ->
      if String.equal sha header.Journal.jh_topcoat then Ok ()
      else
        Error
          (E_provenance
             ("campaign names " ^ header.Journal.jh_topcoat
            ^ " but the clone is " ^ sha)))

(** Validate and select both rows before starting a process.  A failed second
    plant leaves no partial success text because the CLI prints only on Ok. *)
let run (c : config) : (string, error) result =
  Result.bind
    (Result.map_error
       (fun e -> E_campaign (Campaign_report.error_text e))
       (Campaign_report.read_samples c.cp_campaign))
    (fun input ->
      Result.bind (select Add_sign (snd input)) (fun add ->
          Result.bind (select Length_plus_one (snd input)) (fun length ->
              let cfg =
                Legs.default_config ~root:c.cp_root ~clone:c.cp_clone
                  ~out:c.cp_out Plant.No_plant
              in
              Result.bind
                (Result.map_error
                   (fun e -> E_output (Rust_leg.error_text e))
                   (Rust_leg.mkdir_parents c.cp_out))
                (fun () ->
                  Result.bind
                    (check_clone cfg c.cp_out c.cp_clone (fst input))
                    (fun () ->
                      Result.bind
                        (run_witness cfg c.cp_out Add_sign (fst add) (snd add))
                        (fun add_text ->
                          Result.map (fun text -> add_text ^ text)
                            (run_witness cfg c.cp_out Length_plus_one
                               (fst length) (snd length))))))))
