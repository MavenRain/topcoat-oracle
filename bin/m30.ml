(** m30: the repro writer.  It runs the M29 walk for one plant, earns one
    witness run of the final sample, captures the two repository shas and
    writes a [repro.md] beside them.  This is the only M30 module that
    prints. *)

(** What can go wrong, in the order it can go wrong. *)
type failure =
  | F_argv  (** the argv is not [repro <dir> --plant P ...] *)
  | F_walk of string  (** the walk itself failed *)
  | F_witness of string  (** the extra run failed or did not preserve *)
  | F_sha of string  (** a repository sha could not be read *)
  | F_write of string  (** the repro file could not be written *)

(** [usage ()] is the one usage line. *)
let usage () =
  "usage: m30 repro <dir> --plant P [--clone C] [--root R] [--fuel N]"

(** [failure_text f] names one failure for stderr. *)
let failure_text f =
  match f with
  | F_argv -> usage ()
  | F_walk t -> "m30 walk: " ^ t
  | F_witness t -> "m30 witness: " ^ t
  | F_sha t -> "m30 sha: " ^ t
  | F_write t -> "m30 write: " ^ t

(** [after n xs] answers [xs] without its first [n] items. *)
let after n xs =
  snd
    (Prelude.fold
       (fun acc x ->
         if fst acc < n then (fst acc + 1, snd acc)
         else (fst acc + 1, Prelude.append (snd acc) [ x ]))
       (0, []) xs)

(** [repro_dir argv] answers the directory of a [repro] argv, AS GIVEN.  M30
    refuses NOTHING about its shape (ruling Q4).  The goldens hold no absolute
    path because the gate passes a root relative directory after its own
    [cd "$ROOT"], not because of a check here, and the directory is printed
    into the repro file exactly as it arrived on argv. *)
let repro_dir argv =
  Option.fold ~none:(Error F_argv)
    ~some:(fun v ->
      Option.fold ~none:(Error F_argv)
        ~some:(fun d -> if String.equal v "repro" then Ok d else Error F_argv)
        (Prelude.nth_opt argv 2))
    (Prelude.nth_opt argv 1)

(** [flags_of dir argv] reads the M29 flags with the SHIPPED reader, from the
    SHIPPED defaults for the same directory.  [Walk.read_flags] takes the
    defaults record and the remaining ARGUMENTS, and no program name, so the
    argv is cut after the directory and the m30 defaults are the m29 defaults
    by construction. *)
let flags_of dir argv =
  Result.map_error
    (fun m -> F_walk m)
    (Walk.read_flags (Walk.defaults dir) (after 3 argv))

(** [cells wi] answers the four cells of the witness, in the M27 row order.
    The MODE rides the reference cell: a [Wire.decoded] carries no mode at all
    and [Legs.refcell] is exactly [{ r_mode; r_obs }]. *)
let cells (wi : Legs.witness) =
  ( Obs.encode wi.Legs.wi_rust.Wire.d_obs,
    Js_leg.cell wi.Legs.wi_js,
    Obs.encode wi.Legs.wi_ref.Legs.r_obs,
    Taxonomy.mode_name wi.Legs.wi_ref.Legs.r_mode
    ^ " "
    ^ Differ.verdict_text wi.Legs.wi_verdict )

(** [preserved w wi] answers the witness when its verdict is the one the walk
    preserved, and names both verdicts when it is not.  [Minimize.preserves]
    takes the TARGET verdict and an [answer], so the witness verdict is
    wrapped in [A_verdict] (ruling M30-V3). *)
let preserved (w : Walk.run) (wi : Legs.witness) =
  if Minimize.preserves w.Walk.wk_keep (Minimize.A_verdict wi.Legs.wi_verdict)
  then Ok wi
  else
    Error
      (F_witness
         ("the witness run is "
         ^ Differ.verdict_text wi.Legs.wi_verdict
         ^ " and the walk preserved "
         ^ Differ.verdict_text w.Walk.wk_keep))

(** [shas cfg ~dir ~clone ~root] reads both explicitly selected repositories,
    independently of the caller's working directory. *)
let shas cfg ~dir ~clone ~root =
  Result.bind
    (Result.map_error
       (fun e -> F_sha (Provenance.error_text e))
       (Provenance.read_sha cfg ~out:dir ~name:"topcoat" ~repo:clone))
    (fun c ->
      Result.map
        (fun o -> (c, o))
        (Result.map_error
           (fun e -> F_sha (Provenance.error_text e))
           (Provenance.read_sha cfg ~out:dir ~name:"topcoat-oracle" ~repo:root)))

(** [input w wi dir sp] fills the pure renderer's record.  Every field comes
    from a value the run already holds: the FLAGS carry the plant, the origin
    and the fuel, because [Legs.config] carries none of the three;  the walk
    record carries the two sizes and the text;  the witness carries the four
    cells and the emitted js. *)
let input (w : Walk.run) (wi : Legs.witness) dir sp =
  let c = cells wi in
  let f = w.Walk.wk_flags in
  {
    Repro.rp_plant = Plant.name f.Walk.fl_plant;
    rp_origin = Repro.Origin_case (Plant.name f.Walk.fl_plant);
    rp_clone_sha = fst sp;
    rp_oracle_sha = snd sp;
    rp_fuel = f.Walk.fl_fuel;
    rp_start_size = w.Walk.wk_start_size;
    rp_final_size = Minimize.size_of w.Walk.wk_sample;
    rp_bindings = Walk.let_lines w.Walk.wk_sample;
    rp_body = Walk.body_text w.Walk.wk_sample;
    rp_js_src = wi.Legs.wi_rust.Wire.d_js;
    rp_js_form = Wire.js_form_wire wi.Legs.wi_rust.Wire.d_js_form;
    rp_rust = (fun (r, _, _, _) -> r) c;
    rp_js = (fun (_, j, _, _) -> j) c;
    rp_ref = (fun (_, _, f, _) -> f) c;
    rp_verdict = (fun (_, _, _, v) -> v) c;
    rp_walk = w.Walk.wk_text;
    rp_root = f.Walk.fl_root;
    rp_clone = f.Walk.fl_clone;
    rp_dir = dir;
  }

(** [job argv] is the whole run: walk, witness, shas, file, two lines. *)
let job argv =
  Result.bind (repro_dir argv) (fun dir ->
      Result.bind (flags_of dir argv) (fun f ->
          Result.bind
            (Result.map_error
               (fun e -> F_walk (Walk.failure_text e))
               (Walk.run ~dir f))
            (fun w ->
              print_string w.Walk.wk_text;
              Result.bind
                (Result.bind
                   (Result.map_error
                      (fun t -> F_witness t)
                      (Legs.witness w.Walk.wk_cfg w.Walk.wk_sample))
                   (preserved w))
                (fun wi ->
                  Result.bind
                    (shas w.Walk.wk_cfg.Legs.l_rust ~dir ~clone:f.Walk.fl_clone
                       ~root:f.Walk.fl_root)
                    (fun sp ->
                      Result.bind
                        (Result.map_error
                           (fun e -> F_write (Rust_leg.error_text e))
                           (Rust_leg.write_file (dir ^ "/repro.md")
                              (Repro.render (input w wi dir sp))))
                        (fun () ->
                          print_string
                            ("m30 witness: "
                            ^ Differ.verdict_text wi.Legs.wi_verdict
                            ^ "\n");
                          print_string ("m30 repro: " ^ dir ^ "/repro.md\n");
                          Ok ()))))))

(** [main ()] runs the job and turns a failure into stderr and exit 1. *)
let main () =
  Result.fold ~ok:(fun () -> ())
    ~error:(fun f ->
      prerr_string (failure_text f ^ "\n");
      exit 1)
    (job (Array.to_list Sys.argv))

let () = main ()
