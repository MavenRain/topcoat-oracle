(* M29 three-leg batch runner (DESIGN.md M29, spec section 4).  One call
   runs ONE candidate batch through all three legs and answers one
   verdict per candidate, in the batch's own order.

   The cost model is the reason this module exists.  A round of the
   minimizer offers up to a dozen candidates and the rust leg pays per
   crate and not per sample, so the whole round is ONE crate with one
   case per candidate, one build, one run and one node start.  A
   per-candidate runner would multiply the gate's fourteen builds by ten.

   The four helpers below were bin/m27.ml's (bin/m27.ml:161-186 at
   commit eca3372) and are MOVED here unchanged, so the M27 table, the
   M28 table and the M29 verdicts cannot drift apart.  bin/m27.ml now
   calls them from here and its printed table stays byte identical.
   js_cell is a FIVE-ARM match and not an alias: Js_leg.cell answers a
   string (shell/js_leg.ml:298), which is the Absent reason text, and
   the rust cell is built inline because there is no Rust_leg.cell.

   A dropped sample gets NO line.  Driver.add_case refuses a sample the
   crate writer cannot render and Rust_leg.pair zips the KEPT samples
   with the decoded lines by position (shell/rust_leg.ml:533-534), so
   this module rebuilds the same keep flags with the same fold and
   spreads the answers back over the whole batch.  Anything without a
   line answers A_no_verdict, which never preserves a divergence
   (core/minimize.ml, preserves).  A drop is therefore invisible to the
   walk apart from a candidate that is never accepted. *)

open Prelude

(* The reference leg's answer for one sample: the mode it was recorded
   with and the observation the interpreter produced. *)
type refcell = { r_mode : Taxonomy.mode; r_obs : Obs.observation }

(* Run the reference leg over one sample. *)
let ref_cell_of (cfg : Ref_leg.config) (s : Sample.t) : refcell =
  { r_mode = s.Sample.mode; r_obs = Ref_leg.observe cfg s }

(* Four of the five Wire_js constructors carry no observation.  The
   Absent reason is Js_leg.cell itself, so it is BYTE-IDENTICAL to the
   J cell this program prints for the same line, by construction and
   not by a second spelling. *)
let js_cell (l : Wire_js.jline) : Differ.cell =
  match l.Wire_js.jl_body with
  | Wire_js.Jl_obs (o, _x) -> Differ.Present o
  | Wire_js.Jl_skipped _ | Wire_js.Jl_js_error (_, _)
  | Wire_js.Jl_driver_error (_, _) | Wire_js.Jl_lossy _ ->
      Differ.Absent (Js_leg.cell l)

(* The rust and the reference cells are always Present today.  The type
   carries Absent for M36's browser leg and for a rust line that fails
   to decode, and no M27 path builds one (spec section 10). *)
let cells_of (d : Wire.decoded) (l : Wire_js.jline) (o : Obs.observation) :
    Differ.cells =
  {
    Differ.rust = Differ.Present d.Wire.d_obs;
    js = js_cell l;
    reference = Differ.Present o;
  }

(* SIX "../" segments, not the three of Rust_leg.default_config.
   Driver.cargo_toml prepends this prefix to the four clone paths
   literally (shell/driver.ml:470-477), and Rust_leg.default_config
   ships three segments for a crate directory two segments below the
   root (shell/rust_leg.ml:77-89).  An M29 crate sits at
   <root>/_emit/m29/out/<plant>/r<k>, five segments below the root, so
   the prefix is five segments to climb back to the root plus the one
   the shipped value already spends to climb out of it: six.  Every
   directory this module writes is at that same depth, the start
   measurement and the control run included, so ONE prefix serves all of
   them. *)
let dep_prefix : string = "../../../../../../"

(* Everything one M29 run needs.  l_out is the plant's own output
   directory, <root>/_emit/m29/out/<plant>, and every crate this module
   writes is one level below it. *)
type config = {
  l_out : string;
  l_name : string;
  l_plant : Plant.t;
  l_rust : Rust_leg.config;
  l_js : Js_leg.config;
  l_ref : Ref_leg.config;
}

(* The shipped configuration for one plant.  The rust leg keeps every
   shipped value but the dep prefix.  The js leg takes the clone and the
   plant, which is what puts the plant on the node argv
   (shell/plant.ml, js_args).  The reference leg takes the plant's ops,
   which is what puts the plant inside the interpreter. *)
let default_config ~(root : string) ~(clone : string) ~(out : string)
    (p : Plant.t) : config =
  {
    l_out = out;
    l_name = "m29round";
    l_plant = p;
    l_rust = { (Rust_leg.default_config ~root) with Rust_leg.dep_prefix };
    l_js =
      { (Js_leg.default_config ~root) with Js_leg.clone; Js_leg.plant = p };
    l_ref = { Ref_leg.default_config with Ref_leg.ops = Plant.ops p };
  }

(* The CONTROL configuration: the same paths and the same shapes with NO
   plant.  Plant.ops answers the shipped interpreter ops for No_plant
   and Plant.js_args answers the empty argv, so this runs the shipped
   world. *)
let unplanted (cfg : config) : config =
  {
    cfg with
    l_plant = Plant.No_plant;
    l_js = { cfg.l_js with Js_leg.plant = Plant.No_plant };
    l_ref = { cfg.l_ref with Ref_leg.ops = Plant.ops Plant.No_plant };
  }

(* The crate directory of round k. *)
let round_dir (cfg : config) (k : int) : string =
  cfg.l_out ^ "/r" ^ nat_to_string k

(* The crate directory of the start measurement.  Beside the rounds and
   at the same depth, so the one dep prefix holds. *)
let start_dir (cfg : config) : string = cfg.l_out ^ "/rs"

(* The crate directory of the control run.  Beside the rounds and at the
   same depth.  A nested control/r0 would be one segment deeper and the
   single dep prefix would be wrong there. *)
let control_dir (cfg : config) : string = cfg.l_out ^ "/rc"

(* The keep flags of a batch, rebuilt with the SAME fold
   Rust_leg.kept_samples uses (shell/rust_leg.ml:447-458).  A sample the
   fold does not count as kept is a sample the crate writer dropped, and
   it gets no line in run.jsonl. *)
let keep_flags (samples : Sample.t list) : bool list =
  rev
    (snd
       (fold
          (fun acc s ->
            let before = fst acc in
            let after = Driver.add_case before s in
            match () with
            | () when after.Driver.kept > before.Driver.kept ->
                (after, true :: snd acc)
            | () -> (after, false :: snd acc))
          (Driver.empty_built, [])
          samples))

(* The reason texts.  They are printed by nothing in the green path and
   read by a human in the red one. *)
let dropped_text : string = "the rust crate writer dropped the candidate"
let lost_text : string = "the rust leg wrote no line for the candidate"

(* Spread the KEPT answers back over the whole batch.  A kept position
   takes the next answer; a dropped position takes a no-verdict and does
   NOT consume one.  A kept position with no answer left takes a
   no-verdict too, which is the shape a truncated js file produces. *)
let rec spread (flags : bool list) (kept : Minimize.answer list) :
    Minimize.answer list =
  match (flags, kept) with
  | [], [] -> []
  | [], _ :: _ -> []
  | f :: rest, [] ->
      (if f then Minimize.A_no_verdict lost_text
       else Minimize.A_no_verdict dropped_text)
      :: spread rest []
  | f :: rest, a :: more ->
      if f then a :: spread rest more
      else Minimize.A_no_verdict dropped_text :: spread rest kept

(* One verdict per KEPT candidate.  The paired (sample, rust line) list
   of Rust_leg.pair walks beside the js lines of the one Js_leg.run,
   which the node driver writes one per rust line.  Any shape but the
   head-head one ends the walk, and the caller has already refused a
   length mismatch, so the truncating arms are unreachable in the green
   path and safe in the red one. *)
let rec verdicts (cfg : Ref_leg.config) (ps : (Sample.t * Wire.decoded) list)
    (ls : Wire_js.jline list) : Minimize.answer list =
  match (ps, ls) with
  | [], [] -> []
  | [], _ :: _ -> []
  | _ :: _, [] -> []
  | p :: ps1, l :: ls1 ->
      let rc = ref_cell_of cfg (fst p) in
      let cs = cells_of (snd p) l rc.r_obs in
      Minimize.A_verdict (Differ.verdict rc.r_mode (Differ.known_seed ()) cs)
      :: verdicts cfg ps1 ls1

(* One leg failure is a statement about the RUN and not about any one
   candidate, so every candidate of the batch answers the same
   no-verdict and none of them can be accepted.  That shared text is
   also the batch-level reason Minimize.blind_reason reads off the first
   answer when it reports a Stuck stop (spec section 3, ruling Q8). *)
let all_no (samples : Sample.t list) (why : string) : Minimize.answer list =
  map (fun _ -> Minimize.A_no_verdict why) samples

(* Run one batch in one directory and answer one entry per candidate, in
   the candidates' own order.  Every failure of every leg becomes a
   no-verdict for the whole batch with a named reason, so the loop never
   sees an exception and never sees a partial batch. *)
let run_batch (cfg : config) ~(dir : string) (samples : Sample.t list) :
    Minimize.answer list =
  Result.fold
    ~ok:(fun answers -> answers)
    ~error:(fun why -> all_no samples why)
    (Result.bind
       (Result.map_error
          (fun e -> "rust leg: " ^ Rust_leg.error_text e)
          (Rust_leg.run cfg.l_rust ~name:cfg.l_name ~dir samples))
       (fun rep ->
         Result.bind
           (Result.map_error
              (fun e -> "rust pairing: " ^ Rust_leg.error_text e)
              (Rust_leg.pair samples rep))
           (fun ps ->
             Result.bind
               (Result.map_error
                  (fun e -> "js leg: " ^ Js_leg.error_text e)
                  (Js_leg.run cfg.l_js ~rust:(dir ^ "/run.jsonl") ~dir))
               (fun jrep ->
                 match () with
                 | () when not (jrep.Js_leg.j_exit = 0) ->
                     Error
                       ("the js driver exited "
                       ^ nat_to_string jrep.Js_leg.j_exit)
                 | () when not (len ps = len jrep.Js_leg.j_lines) ->
                     Error
                       ("the rust leg kept "
                       ^ nat_to_string (len ps)
                       ^ " candidates and the js leg decoded "
                       ^ nat_to_string (len jrep.Js_leg.j_lines)
                       ^ " lines")
                 | () ->
                     Ok
                       (spread (keep_flags samples)
                          (verdicts cfg.l_ref ps jrep.Js_leg.j_lines))))))

(* R1 and R2, the injected function core/minimize.ml runs on.  The round
   index names the directory, which is the only use it has here. *)
let oracle (cfg : config) : Minimize.oracle =
  {
    Minimize.o_run =
      (fun ~round samples -> run_batch cfg ~dir:(round_dir cfg round) samples);
  }

(* The start measurement: the same three legs over the one start sample,
   in its own directory.  The CLI needs it because core/minimize.ml
   takes the divergence to preserve as an argument and measures
   nothing. *)
let start (cfg : config) (s : Sample.t) : Minimize.answer =
  Option.fold
    ~none:(Minimize.A_no_verdict "the start run answered nothing")
    ~some:(fun a -> a)
    (nth_opt (run_batch cfg ~dir:(start_dir cfg) (s :: [])) 0)

(* The CONTROL: the minimized sample run once more with no plant at all.
   Anything but Agree means the surviving divergence is not the planted
   one, and the gate reads this line. *)
let control (cfg : config) (s : Sample.t) : Minimize.answer =
  Option.fold
    ~none:(Minimize.A_no_verdict "the control run answered nothing")
    ~some:(fun a -> a)
    (nth_opt (run_batch (unplanted cfg) ~dir:(control_dir cfg) (s :: [])) 0)
