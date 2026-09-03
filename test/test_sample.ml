(* M21 gate: the taxonomy classifier, whole-sample runs, and the
   sample generator at N=10_000 in both weight scopes.

   Three suites:
   - taxonomy: hand vectors for Taxonomy.mode_of, including the two
     that make the classification SYNTACTIC (a write under a dead
     branch and a write inside a closure body both classify as
     Signal_writing).
   - run_sample: the interpreter's whole-sample entry point on a
     writer, a reader, and a sample whose initializer cannot reduce.
   - m21: the generator, drawn at a fixed seed in the default and the
     m20 weight scope, plus one pure-Read_only and one
     pure-Signal_writing batch. *)

open Ast

module G = QCheck.Gen

let n_m21 = 10_000

(* "M21" for the mixed batch; the pure batches append 'R' and 'W' so
   the three streams are independent. *)
let seed_mixed = 0x4d3231
let seed_read = 0x4d3252
let seed_write = 0x4d3257

let fuel = 10_000
let ops = Ops.interp_ops

(* ---------- helpers ---------- *)

let f64 x =
  let p = Floatops.of_float x in
  E_lit (L_f64_bits (fst p, snd p))

let bind id t init : Sample.binding = { Sample.id = id; ty = t; init = init }

let count_if p xs = List.length (List.filter p xs)

let chk_mode name expected e =
  Alcotest.(check string) name
    (Taxonomy.mode_name expected)
    (Taxonomy.mode_name (Taxonomy.mode_of e))

(* The top shape of a drawn writer body. Exhaustive with no wildcard:
   the six shapes gen_writer builds, everything else grouped. *)
let shape_name (e : expr) =
  match e with
  | E_method (_, _, _) -> "E_method"
  | E_block_unit _ -> "E_block_unit"
  | E_if (_, _) -> "E_if"
  | E_if_else (_, _, _) -> "E_if_else"
  | E_while (_, _) -> "E_while"
  | E_loop _ -> "E_loop"
  | E_lit _ | E_var _ | E_unary (_, _) | E_binary (_, _, _) | E_tuple _
  | E_some _ | E_none _ | E_ok (_, _) | E_err (_, _) | E_call (_, _)
  | E_field (_, _) | E_index (_, _) | E_let (_, _) | E_block (_, _)
  | E_break | E_continue | E_return_unit | E_return _
  | E_closure (_, _, _) | E_async_closure (_, _, _) | E_await _ ->
      "other"

let writer_shapes =
  [ "E_method"; "E_block_unit"; "E_if"; "E_if_else"; "E_while"; "E_loop" ]

let write_meths =
  [ "M_set"; "M_toggle"; "M_increment"; "M_decrement"; "M_push_str" ]

(* Literals inside an initializer. The generator builds inits from
   E_lit, E_some, E_ok, E_err, E_tuple and E_block_unit [] only, so
   the grouped arm holds no literal; a drift that puts one under
   another constructor makes the coverage checks below go red, which
   is the safe direction. *)
let rec init_lits (e : expr) : lit list =
  match e with
  | E_lit l -> [ l ]
  | E_some a -> init_lits a
  | E_ok (a, _) -> init_lits a
  | E_err (a, _) -> init_lits a
  | E_tuple es -> List.concat_map init_lits es
  | E_none _ | E_block_unit _ | E_var _ | E_unary (_, _)
  | E_binary (_, _, _) | E_call (_, _) | E_method (_, _, _)
  | E_field (_, _) | E_index (_, _) | E_let (_, _) | E_block (_, _)
  | E_if (_, _) | E_if_else (_, _, _) | E_loop _ | E_while (_, _)
  | E_break | E_continue | E_return_unit | E_return _
  | E_closure (_, _, _) | E_async_closure (_, _, _) | E_await _ ->
      []

(* IEEE-754 binary64 exponent field all ones: NaN when the mantissa
   is nonzero, infinity when it is zero. *)
let is_nan_lit (l : lit) =
  match l with
  | L_f64_bits (hi, lo) ->
      hi land 0x7FF00000 = 0x7FF00000 && (lo <> 0 || hi land 0xFFFFF <> 0)
  | L_bool _ | L_str _ -> false

let is_inf_lit (l : lit) =
  match l with
  | L_f64_bits (hi, lo) -> hi land 0x7FFFFFFF = 0x7FF00000 && lo = 0
  | L_bool _ | L_str _ -> false

let is_empty_str_lit (l : lit) =
  match l with
  | L_str s -> String.length s = 0
  | L_f64_bits (_, _) | L_bool _ -> false

let has_high_byte s =
  String.fold_left (fun acc c -> acc || Char.code c >= 0x80) false s

let is_multibyte_str_lit (l : lit) =
  match l with
  | L_str s -> has_high_byte s
  | L_f64_bits (_, _) | L_bool _ -> false

(* ---------- suite: taxonomy ---------- *)

let set3 = E_method (E_var 3, M_set, [ f64 1.0 ])
let get3 = E_method (E_var 3, M_get, [])

let tax_get () = chk_mode "get" Taxonomy.Read_only get3

let tax_clone () =
  chk_mode "clone" Taxonomy.Read_only (E_method (E_var 3, M_clone, []))

let tax_read_nested () =
  chk_mode "nested read" Taxonomy.Read_only
    (E_block_unit [ E_if (E_lit (L_bool true), get3); E_await get3 ])

let tax_set () = chk_mode "set" Taxonomy.Signal_writing set3

let tax_toggle () =
  chk_mode "toggle" Taxonomy.Signal_writing (E_method (E_var 4, M_toggle, []))

let tax_increment () =
  chk_mode "increment" Taxonomy.Signal_writing
    (E_method (E_var 3, M_increment, []))

let tax_decrement () =
  chk_mode "decrement" Taxonomy.Signal_writing
    (E_method (E_var 3, M_decrement, []))

let tax_push_str () =
  chk_mode "push_str" Taxonomy.Signal_writing
    (E_method (E_var 5, M_push_str, [ E_lit (L_str "x") ]))

let tax_if_arm () =
  chk_mode "write in if arm" Taxonomy.Signal_writing
    (E_if (E_lit (L_bool true), set3))

(* Syntactic on purpose: the else arm never runs, but the panic stays
   reachable as far as the rust leg is concerned, so the diff arity
   must be the two-way one. *)
let tax_dead_arm () =
  chk_mode "write in dead arm" Taxonomy.Signal_writing
    (E_if_else (E_lit (L_bool true), get3, set3))

let tax_closure () =
  chk_mode "write in closure body" Taxonomy.Signal_writing
    (E_closure ([], T_unit, set3))

let tax_async_closure () =
  chk_mode "write in async closure body" Taxonomy.Signal_writing
    (E_async_closure ([], T_unit, set3))

let tax_receiver () =
  chk_mode "write under a receiver" Taxonomy.Signal_writing
    (E_method (E_block ([ set3 ], E_var 3), M_get, []))

(* The two arms the writer generator never leaves as the only write:
   a method argument and a let initializer. *)
let tax_argument () =
  chk_mode "write inside a method argument" Taxonomy.Signal_writing
    (E_method
       (E_var 2, M_starts_with, [ E_block ([ set3 ], E_lit (L_str "a")) ]))

let tax_let_init () =
  chk_mode "write inside a let initializer" Taxonomy.Signal_writing
    (E_let (11, E_block ([ set3 ], f64 1.0)))

(* ---------- suite: run_sample ---------- *)

let chk_out name expected (r : Interp.run_result) =
  Alcotest.(check string) name
    (Obs.encode_outcome expected)
    (Obs.encode_outcome r.Interp.outcome)

let chk_sigs name expected (r : Interp.run_result) =
  Alcotest.(check string) name
    (Obs.encode_signals expected)
    (Obs.encode_signals r.Interp.signals)

let writer_sample : Sample.t =
  {
    Sample.mode = Taxonomy.Signal_writing;
    inputs = [];
    signals = [ bind 3 T_f64 (f64 1.0) ];
    target = T_unit;
    body = E_method (E_var 3, M_increment, []);
  }

let reader_sample : Sample.t =
  {
    Sample.mode = Taxonomy.Read_only;
    inputs = [ bind 0 T_f64 (f64 2.5) ];
    signals = [];
    target = T_f64;
    body = E_binary (B_mul, E_var 0, f64 2.0);
  }

(* An initializer that panics instead of reducing. run_sample must
   surface that on the observation channel, not drop the sample. *)
let broken_sample : Sample.t =
  {
    Sample.mode = Taxonomy.Read_only;
    inputs = [ bind 0 T_f64 (E_method (E_none T_f64, M_unwrap, [])) ];
    signals = [];
    target = T_f64;
    body = E_var 0;
  }

let f64_value x =
  let p = Floatops.of_float x in
  Obs.V_f64_bits (fst p, snd p)

let run_writer () =
  let r = Interp.run_sample ops fuel writer_sample in
  chk_out "writer outcome" (Obs.O_value Obs.V_unit) r;
  chk_sigs "writer signals" [ (3, f64_value 2.0) ] r

let run_reader () =
  let r = Interp.run_sample ops fuel reader_sample in
  chk_out "reader outcome" (Obs.O_value (f64_value 5.0)) r;
  chk_sigs "reader signals" [] r

let run_broken () =
  let r = Interp.run_sample ops fuel broken_sample in
  chk_out "stuck init" (Obs.O_panic (Obs.P_other, "stuck:init")) r;
  chk_sigs "stuck init signals" [] r

(* ---------- suite: m21 generator ---------- *)

let draw_mixed m20 w seed =
  QCheck.Gen.generate ~n:n_m21
    ~rand:(Random.State.make [| seed |])
    (Sample_gen.gen_sample m20 w)

let draw_at m20 w mode seed =
  QCheck.Gen.generate ~n:n_m21
    ~rand:(Random.State.make [| seed |])
    (Sample_gen.gen_sample_at m20 w mode)

let is_read (s : Sample.t) = Taxonomy.mode_eq s.Sample.mode Taxonomy.Read_only

let is_write_mode (s : Sample.t) =
  Taxonomy.mode_eq s.Sample.mode Taxonomy.Signal_writing

let wf_at_target (s : Sample.t) =
  Result.fold
    ~ok:(fun t -> ty_eq s.Sample.target t)
    ~error:(fun _e -> false)
    (Wf.check_top (Sample.wf_env s) s.Sample.body)

let init_ok (b : Sample.binding) =
  Result.fold
    ~ok:(fun t -> ty_eq b.Sample.ty t)
    ~error:(fun _e -> false)
    (Wf.check_top [] b.Sample.init)
  && Option.fold ~none:false
       ~some:(fun _v -> true)
       (Interp.eval_init ops fuel b.Sample.init)

let bindings_of (s : Sample.t) = List.append s.Sample.signals s.Sample.inputs
let all_bindings samples = List.concat_map bindings_of samples

let writer_is_unit (s : Sample.t) =
  match s.Sample.mode with
  | Taxonomy.Read_only -> true
  | Taxonomy.Signal_writing -> ty_eq s.Sample.target T_unit

let ids_distinct (s : Sample.t) =
  let ids = Sample.ids s in
  List.length (List.sort_uniq compare ids) = List.length ids

let tally_of samples =
  Tally.of_samples
    (List.map (fun (s : Sample.t) -> (s.Sample.target, s.Sample.body)) samples)

let tally_inits samples =
  Tally.of_samples
    (List.map
       (fun (b : Sample.binding) -> (b.Sample.ty, b.Sample.init))
       (all_bindings samples))

(* One scope's checks. `label` names the weight scope in the failure
   message, so a red test says which batch broke. *)
let mode_agreement label samples () =
  Alcotest.(check int)
    (label ^ ": mode disagreements")
    0
    (count_if (fun s -> not (Sample.mode_ok s)) samples)

let target_wf label samples () =
  Alcotest.(check int)
    (label ^ ": bodies not wf at target")
    0
    (count_if (fun s -> not (wf_at_target s)) samples)

let inits_wf label samples () =
  Alcotest.(check int)
    (label ^ ": inits not wf or not reducible")
    0
    (count_if (fun b -> not (init_ok b)) (all_bindings samples))

let writers_unit label samples () =
  Alcotest.(check int)
    (label ^ ": writers not at T_unit")
    0
    (count_if (fun s -> not (writer_is_unit s)) samples)

let ids_ok label samples () =
  Alcotest.(check int)
    (label ^ ": samples with duplicate ids")
    0
    (count_if (fun s -> not (ids_distinct s)) samples)

let both_modes label samples () =
  Alcotest.(check bool)
    (label ^ ": both modes reached at least 3000 times")
    true
    (count_if is_read samples >= 3000 && count_if is_write_mode samples >= 3000)

(* The pure-Read_only batch is the tooth for the mode gate in
   sig_writes: no write method may appear anywhere in the batch, by
   the tally AND by the classifier. *)
let read_batch_has_no_writes label samples () =
  let t = tally_of samples in
  Alcotest.(check int)
    (label ^ ": write methods in the read-only batch")
    0
    (List.fold_left (fun acc k -> acc + Tally.count k t) 0 write_meths);
  Alcotest.(check int)
    (label ^ ": bodies the classifier calls writers")
    0
    (count_if (fun (s : Sample.t) -> Taxonomy.writes s.Sample.body) samples)

let write_batch_all_write label samples () =
  Alcotest.(check int)
    (label ^ ": writer bodies that do not write")
    0
    (count_if
       (fun (s : Sample.t) -> not (Taxonomy.writes s.Sample.body))
       samples)

let write_batch_reaches_meths label samples () =
  let t = tally_of samples in
  Alcotest.(check int)
    (label ^ ": write methods never reached")
    0
    (count_if (fun k -> Tally.count k t = 0) write_meths)

let write_batch_reaches_shapes label samples () =
  let tops =
    List.map (fun (s : Sample.t) -> shape_name s.Sample.body) samples
  in
  Alcotest.(check int)
    (label ^ ": writer top shapes never reached")
    0
    (count_if (fun k -> not (List.mem k tops)) writer_shapes);
  Alcotest.(check int)
    (label ^ ": writer bodies with an unexpected top shape")
    0
    (count_if (fun k -> String.equal k "other") tops)

let sig_counts samples =
  List.map (fun (s : Sample.t) -> List.length s.Sample.signals) samples

let env_coverage label samples () =
  let counts = sig_counts samples in
  Alcotest.(check int)
    (label ^ ": signal counts never reached")
    0
    (count_if (fun k -> not (List.mem k counts)) [ 1; 2; 3 ]);
  Alcotest.(check int)
    (label ^ ": signal counts out of range")
    0
    (count_if (fun k -> k < 1 || k > 3) counts);
  let elems =
    List.map
      (fun (b : Sample.binding) -> ty_to_string b.Sample.ty)
      (List.concat_map (fun (s : Sample.t) -> s.Sample.signals) samples)
  in
  Alcotest.(check int)
    (label ^ ": signal element types never reached")
    0
    (count_if
       (fun k -> not (List.mem k elems))
       (List.map ty_to_string [ T_f64; T_bool; T_string ]))

let init_coverage label samples () =
  let lits =
    List.concat_map (fun b -> init_lits b.Sample.init) (all_bindings samples)
  in
  let t = tally_inits samples in
  Alcotest.(check bool) (label ^ ": a NaN init") true (List.exists is_nan_lit lits);
  Alcotest.(check bool)
    (label ^ ": an infinite init")
    true (List.exists is_inf_lit lits);
  Alcotest.(check bool)
    (label ^ ": an empty-string init")
    true
    (List.exists is_empty_str_lit lits);
  Alcotest.(check bool)
    (label ^ ": a multibyte-string init")
    true
    (List.exists is_multibyte_str_lit lits);
  Alcotest.(check int)
    (label ^ ": option and result init shapes never reached")
    0
    (count_if
       (fun k -> Tally.count k t = 0)
       [ "E_none"; "E_some"; "E_ok"; "E_err"; "L_bool"; "L_str"; "L_f64_bits" ])

(* ---------- batches ---------- *)

let samples_default = draw_mixed false Weights.default seed_mixed
let samples_m20 = draw_mixed true Weights.m20 seed_mixed
let samples_read = draw_at false Weights.default Taxonomy.Read_only seed_read
let samples_write = draw_at false Weights.default Taxonomy.Signal_writing seed_write
let samples_read_m20 = draw_at true Weights.m20 Taxonomy.Read_only seed_read
let samples_write_m20 = draw_at true Weights.m20 Taxonomy.Signal_writing seed_write

(* ---------- report ---------- *)

let hist_line name samples =
  let counts = sig_counts samples in
  Printf.sprintf "%s_signals_1_2_3 %d %d %d\n" name
    (count_if (fun k -> k = 1) counts)
    (count_if (fun k -> k = 2) counts)
    (count_if (fun k -> k = 3) counts)

let meth_lines name samples =
  let t = tally_of samples in
  String.concat ""
    (List.map
       (fun k -> Printf.sprintf "%s_%s %d\n" name k (Tally.count k t))
       write_meths)

let shape_lines name samples =
  let tops =
    List.map (fun (s : Sample.t) -> shape_name s.Sample.body) samples
  in
  String.concat ""
    (List.map
       (fun k ->
         Printf.sprintf "%s_top_%s %d\n" name k
           (count_if (fun x -> String.equal x k) tops))
       writer_shapes)

let init_lines name samples =
  let t = tally_inits samples in
  let lits =
    List.concat_map (fun b -> init_lits b.Sample.init) (all_bindings samples)
  in
  String.concat ""
    (List.map
       (fun kv -> Printf.sprintf "%s_init_%s %d\n" name (fst kv) (snd kv))
       [
         ("nan", count_if is_nan_lit lits);
         ("inf", count_if is_inf_lit lits);
         ("empty_str", count_if is_empty_str_lit lits);
         ("multibyte_str", count_if is_multibyte_str_lit lits);
         ("none", Tally.count "E_none" t);
         ("some", Tally.count "E_some" t);
         ("ok", Tally.count "E_ok" t);
         ("err", Tally.count "E_err" t);
       ])

let mode_lines name samples =
  Printf.sprintf "%s_read_only %d\n%s_signal_writing %d\n" name
    (count_if is_read samples) name
    (count_if is_write_mode samples)

let report =
  Printf.sprintf
    "m21 mode report (n=%d, seeds 0x%x mixed, 0x%x read, 0x%x write)\n" n_m21
    seed_mixed seed_read seed_write
  ^ mode_lines "default" samples_default
  ^ mode_lines "m20" samples_m20
  ^ hist_line "default" samples_default
  ^ hist_line "m20" samples_m20
  ^ meth_lines "default" samples_default
  ^ shape_lines "write" samples_write
  ^ meth_lines "write" samples_write
  ^ (let tr = tally_of samples_read in
     Printf.sprintf "read_write_methods %d\n"
       (List.fold_left (fun acc k -> acc + Tally.count k tr) 0 write_meths))
  ^ init_lines "default" samples_default

(* ---------- runner ---------- *)

let scope_cases label samples =
  [
    Alcotest.test_case (label ^ " mode agreement") `Quick
      (mode_agreement label samples);
    Alcotest.test_case (label ^ " target wf") `Quick (target_wf label samples);
    Alcotest.test_case (label ^ " inits wf") `Quick (inits_wf label samples);
    Alcotest.test_case (label ^ " writers unit") `Quick
      (writers_unit label samples);
    Alcotest.test_case (label ^ " ids distinct") `Quick (ids_ok label samples);
    Alcotest.test_case (label ^ " both modes") `Quick (both_modes label samples);
    Alcotest.test_case (label ^ " env coverage") `Quick
      (env_coverage label samples);
  ]

let () =
  print_string report;
  flush stdout;
  Alcotest.run "sample"
    [
      ( "taxonomy",
        [
          Alcotest.test_case "get is read" `Quick tax_get;
          Alcotest.test_case "clone is read" `Quick tax_clone;
          Alcotest.test_case "nested read" `Quick tax_read_nested;
          Alcotest.test_case "set writes" `Quick tax_set;
          Alcotest.test_case "toggle writes" `Quick tax_toggle;
          Alcotest.test_case "increment writes" `Quick tax_increment;
          Alcotest.test_case "decrement writes" `Quick tax_decrement;
          Alcotest.test_case "push_str writes" `Quick tax_push_str;
          Alcotest.test_case "if arm writes" `Quick tax_if_arm;
          Alcotest.test_case "dead arm writes" `Quick tax_dead_arm;
          Alcotest.test_case "closure body writes" `Quick tax_closure;
          Alcotest.test_case "async closure body writes" `Quick
            tax_async_closure;
          Alcotest.test_case "receiver writes" `Quick tax_receiver;
          Alcotest.test_case "argument writes" `Quick tax_argument;
          Alcotest.test_case "let init writes" `Quick tax_let_init;
        ] );
      ( "run_sample",
        [
          Alcotest.test_case "writer" `Quick run_writer;
          Alcotest.test_case "reader" `Quick run_reader;
          Alcotest.test_case "stuck init" `Quick run_broken;
        ] );
      ( "m21",
        List.concat
          [
            scope_cases "default" samples_default;
            scope_cases "m20" samples_m20;
            [
              Alcotest.test_case "read-only batch has no writes" `Quick
                (read_batch_has_no_writes "read" samples_read);
              Alcotest.test_case "read-only batch mode agreement" `Quick
                (mode_agreement "read" samples_read);
              Alcotest.test_case "read-only batch target wf" `Quick
                (target_wf "read" samples_read);
              Alcotest.test_case "read-only batch inits wf" `Quick
                (inits_wf "read" samples_read);
              Alcotest.test_case "read-only batch writers unit" `Quick
                (writers_unit "read" samples_read);
              Alcotest.test_case "read-only batch ids distinct" `Quick
                (ids_ok "read" samples_read);
              Alcotest.test_case "writer batch all write" `Quick
                (write_batch_all_write "write" samples_write);
              Alcotest.test_case "writer batch reaches every write method"
                `Quick
                (write_batch_reaches_meths "write" samples_write);
              Alcotest.test_case "writer batch reaches every top shape" `Quick
                (write_batch_reaches_shapes "write" samples_write);
              Alcotest.test_case "writer batch target wf" `Quick
                (target_wf "write" samples_write);
              Alcotest.test_case "writer batch mode agreement" `Quick
                (mode_agreement "write" samples_write);
              Alcotest.test_case "writer batch inits wf" `Quick
                (inits_wf "write" samples_write);
              Alcotest.test_case "writer batch writers unit" `Quick
                (writers_unit "write" samples_write);
              Alcotest.test_case "writer batch ids distinct" `Quick
                (ids_ok "write" samples_write);
              Alcotest.test_case "m20 read-only batch has no writes" `Quick
                (read_batch_has_no_writes "read_m20" samples_read_m20);
              Alcotest.test_case "m20 read-only batch mode agreement" `Quick
                (mode_agreement "read_m20" samples_read_m20);
              Alcotest.test_case "m20 read-only batch target wf" `Quick
                (target_wf "read_m20" samples_read_m20);
              Alcotest.test_case "m20 read-only batch inits wf" `Quick
                (inits_wf "read_m20" samples_read_m20);
              Alcotest.test_case "m20 read-only batch writers unit" `Quick
                (writers_unit "read_m20" samples_read_m20);
              Alcotest.test_case "m20 read-only batch ids distinct" `Quick
                (ids_ok "read_m20" samples_read_m20);
              Alcotest.test_case "m20 writer batch all write" `Quick
                (write_batch_all_write "write_m20" samples_write_m20);
              Alcotest.test_case "m20 writer batch reaches every write method"
                `Quick
                (write_batch_reaches_meths "write_m20" samples_write_m20);
              Alcotest.test_case "m20 writer batch reaches every top shape"
                `Quick
                (write_batch_reaches_shapes "write_m20" samples_write_m20);
              Alcotest.test_case "m20 writer batch target wf" `Quick
                (target_wf "write_m20" samples_write_m20);
              Alcotest.test_case "m20 writer batch mode agreement" `Quick
                (mode_agreement "write_m20" samples_write_m20);
              Alcotest.test_case "m20 writer batch inits wf" `Quick
                (inits_wf "write_m20" samples_write_m20);
              Alcotest.test_case "m20 writer batch writers unit" `Quick
                (writers_unit "write_m20" samples_write_m20);
              Alcotest.test_case "m20 writer batch ids distinct" `Quick
                (ids_ok "write_m20" samples_write_m20);
              Alcotest.test_case "init coverage" `Quick
                (init_coverage "default" samples_default);
            ];
          ] );
    ]
