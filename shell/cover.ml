(* M22 coverage report over a drawn batch (DESIGN.md M22).

   Six sections, in this order: the header (asked for, kept, dropped,
   seed, mode, scope), the constructor tally with the required BODY
   names that stayed unreached, the required INIT shapes that stayed
   unreached and the excluded names that were reached, the
   mode counters, the environment coverage (signal counts, signal
   element types, initial-value classes, the five write methods), the
   target-type and expression-size histograms, and the drops.

   The drop contract.  A DROP is any sample the pipeline did not keep,
   for ANY reason.  Each dropped sample gets one line that carries its
   draw index, its reason, the full escaped byte length of its printed
   text and that text.  There is NO cap on the number of drop lines,
   and only KEPT samples feed a histogram, so a dropped sample can
   never inflate a coverage number.  If a future milestone needs a cap
   on the drop lines, it must print `drop_lines_capped_at N` in the
   header section: a silent cap is the one thing this milestone exists
   to prevent.

   No drop path exists in the generator at this pin.  Every reason in
   `drop_reason` is a tripwire against drift, and M23 adds the first
   real one (a driver timeout).

   Cap, bound and drop inventory.  This is the sweep over shell/ and
   bin/ at this pin for min, max, take, truncate, filter, keep, retry,
   assume, size, fuel, bound, cap and limit.  Every site, and whether
   the report surfaces it as a drop:
   - gen.ml `G.int_bound 2` (the type-draw fuel 0..2) and
     `G.int_bound 6` (the expression fuel 0..6).  NOT drops: fuel
     shapes a draw and discards nothing.  Visible indirectly as the
     target-type histogram and as expr_size_min, expr_size_mean_milli
     and expr_size_max.
   - gen.ml `sub = fuel - 1` with `if fuel <= 0 then []` for types and
     `if fuel <= 0 then leaf ..` for expressions, the recursion
     depth.  NOT drops: a fuel draw, not a discard.
   - gen.ml `keep`, `vars_at`, `option_vars`, `result_vars`,
     `fn_sites`, `async_fn_sites`, which environment variables a
     production may use.  NOT a drop: a type filter on the production
     list, not on samples.
   - gen.ml `G.int_bound (len rest)` in pick_elt and
     `max 0 (total - 1)` in pick_w, the index range.  NOT a drop:
     draw mechanics.
   - gen.ml `G.int_bound 65535` twice, one 32-bit half from two
     16-bit draws.  NOT a drop: draw mechanics, documented there.
   - gen.ml `gen_stmts` `G.int_bound 2` (0..2 statements per block)
     and `gen_tys` `G.int_bound 2` (0..2 type parameters).  NOT
     drops: they shape the draw.
   - gen.ml `loop_suffix` and the m20 forced `[E_break]`.  NOT a
     drop: a scope rule, reported as the scope name in the header.
   - gen.ml `f64_pool_m20` and `gen_f64_bits_m20`, which leave the
     non-finite specials out under m20.  No discard: visible as
     init_nan, init_pos_inf and init_neg_inf going to zero in the m20
     scope.
   - weights.ml `m20`, the zero weights (`ty_signal = 0` and the
     reject families).  No discard: visible as zeros in the tally,
     and it is why `required_for` applies the 77-name list only in
     scope m18.
   - sample_gen.ml `G.int_bound 8` (the random alnum init string
     length) and `G.int_bound (List.length init_str_pool)` (the pool
     index plus the random branch).  NOT drops: they shape the draw.
   - sample_gen.ml `G.int_bound 2`, the signal count 1..3.  No
     discard: reported directly as signals_1, signals_2, signals_3.
   - sample_gen.ml the four tripwire arms of `gen_init`.  A fn,
     async-fn, future or signal input would get an init that fails
     wf.  DROP: it becomes drop_init_wf, one line per sample.
   - strops.ml `min (i + fst d) n`, the trim scan index.  NOT a drop:
     a string-operation internal.
   - floatops.ml the `p` cap on the shortest-roundtrip digit search.
     NOT a drop: unreachable for binary64, documented there.
   - the interpreter fuel, `init_fuel` below, the value
     test/test_sample.ml uses.  DROP: exhaustion becomes
     drop_init_stuck.
   - emit_m20.ml `~n:1000` at seed 0x4d3230, the M20 batch size.  NOT
     a drop: another milestone's fixed batch, not a cap on this
     report.
   - `drop_text_max` below, the printed text on a drop LINE.  DROP,
     and never silent: the line prints the clamp as `[+N]` and the
     full escaped length as `bytes=`.
   - the drop LIST length.  There is NO cap.  A future cap must print
     `drop_lines_capped_at N` in the header section.

   The rule the table encodes: a generator fuel draw is NOT a drop.
   Fuel shapes a sample;  it never discards one.  Only the six
   `drop_reason` constructors discard, and each one prints a line. *)

open Ast

(* ---------- options ---------- *)

type scope =
  | Sc_default
  | Sc_m20
  | Sc_m18

type mode_arg =
  | Ma_mixed
  | Ma_read_only
  | Ma_signal_writing

type format =
  | F_text
  | F_json

type opts = {
  samples : int;
  seed : int;
  mode : mode_arg;
  scope : scope;
  strict : bool;
  format : format;
}

(* The M18 seed, so a default run compares with the M18 counter
   report. *)
let default_opts =
  {
    samples = 10_000;
    seed = 0x4d3138;
    mode = Ma_mixed;
    scope = Sc_default;
    strict = false;
    format = F_text;
  }

let scope_name s =
  match s with
  | Sc_default -> "default"
  | Sc_m20 -> "m20"
  | Sc_m18 -> "m18"

let mode_arg_name m =
  match m with
  | Ma_mixed -> "mixed"
  | Ma_read_only -> "read-only"
  | Ma_signal_writing -> "signal-writing"

(* ---------- total text helpers ---------- *)

let hex_lower = "0123456789abcdef"
let hex_upper = "0123456789ABCDEF"

(* String.sub behind an explicit bounds guard, the one form the
   no-exception rule allows.  String.get is denied and Char.chr
   raises, so a one-byte String.sub is how a digit table is read. *)
let table_digit table n =
  if n >= 0 && n < String.length table then
    String.sub table n 1 (* @total-accessor *)
  else "0"

(* Division goes through Prelude.div_opt;  the remainder is the
   subtraction, so no bare / and no mod appear here. *)
let rec hex_of_nat table n =
  match () with
  | () when n <= 0 -> ""
  | () ->
      Option.fold ~none:""
        ~some:(fun q -> hex_of_nat table q ^ table_digit table (n - (q * 16)))
        (Prelude.div_opt n 16)

(* "0x" plus lowercase hex, the spelling the M18 report prints. *)
let hex_str n =
  match () with
  | () when n <= 0 -> "0x0"
  | () -> "0x" ^ hex_of_nat hex_lower n

(* Exactly two uppercase hex digits for one byte. *)
let hex_byte n =
  Option.fold ~none:"00"
    ~some:(fun q ->
      table_digit hex_upper q ^ table_digit hex_upper (n - (q * 16)))
    (Prelude.div_opt n 16)

(* ---------- names shared with the M18 gate ---------- *)

(* The reachability claim of Gen.gen_target Gen.default_genv at
   N=10k, asserted by test/test_gen.ml's "required reached at 10k".
   test_gen reads this list, so one definition serves the gate and
   the CLI.  It holds ONLY for the m18 scope: the sample scopes draw
   a different stream, and Weights.m20 sets ty_signal to 0. *)
let required_m18 =
  [
    "E_lit"; "E_var"; "E_unary"; "E_binary"; "E_some"; "E_none"; "E_ok";
    "E_err"; "E_call"; "E_method"; "E_let"; "E_block"; "E_block_unit";
    "E_if"; "E_if_else"; "E_loop"; "E_while"; "E_break"; "E_continue";
    "E_return_unit"; "E_return"; "E_closure"; "E_async_closure"; "E_await";
    "L_f64_bits"; "L_bool"; "L_str"; "U_neg"; "U_not"; "B_add"; "B_sub";
    "B_mul"; "B_div"; "B_eq"; "B_ne"; "B_lt"; "B_le"; "B_gt"; "B_ge";
    "M_then"; "M_then_some"; "M_len"; "M_is_empty"; "M_trim";
    "M_trim_start"; "M_trim_end"; "M_starts_with"; "M_ends_with";
    "M_contains"; "M_to_owned"; "M_is_some"; "M_is_none"; "M_is_ok";
    "M_is_err"; "M_ok"; "M_err"; "M_unwrap_err"; "M_expect_err";
    "M_unwrap"; "M_expect"; "M_get"; "M_set"; "M_toggle"; "M_increment";
    "M_decrement"; "M_push_str"; "M_clone"; "T_f64"; "T_bool"; "T_string";
    "T_unit"; "T_option"; "T_result"; "T_fn"; "T_async_fn"; "T_future";
    "T_signal";
  ]

(* Unconstructible under expr! or wf-rejected;  test/test_gen.ml reads
   this list too. *)
let excluded_ast = [ "E_tuple"; "E_field"; "E_index"; "U_deref"; "T_tuple" ]

let write_meths =
  [ "M_set"; "M_toggle"; "M_increment"; "M_decrement"; "M_push_str" ]

let init_shapes =
  [ "E_none"; "E_some"; "E_ok"; "E_err"; "L_bool"; "L_str"; "L_f64_bits" ]

(* The required set has two halves, and the two halves live in two
   different tallies, so they are two functions.

   `required_for` is the BODY claim.  It is scored against the tally
   of the kept bodies.  `required_inits` is the INIT claim: the seven
   init shapes name what test_sample's `init coverage` case asserts
   about the drawn initial values (spec 2.B), so they are scored
   against `tally_inits`, the tally of those initial values.

   One tally for both halves gives a category error in both
   directions.  A body that holds `E_some` reported the init shape
   reached even when every init was a plain f64 literal, and a scope
   whose bodies cannot hold `E_none` (m20 at signal-writing) reported
   the init shape unreached even when every init was an option.

   The required and the excluded set are functions of the run.  Every
   match is exhaustive over scope and over mode_arg. *)
let required_for (sc : scope) (m : mode_arg) =
  match sc with
  | Sc_m18 -> (
      match m with
      | Ma_mixed -> required_m18
      | Ma_read_only | Ma_signal_writing -> [])
  | Sc_default | Sc_m20 -> (
      match m with
      | Ma_read_only -> []
      | Ma_mixed | Ma_signal_writing -> write_meths)

(* Scope m18 redraws the M18 stream, which carries no environment, so
   it has no init to require.  The set does not vary with the mode:
   every mode draws the same environment shapes.  The caller also
   skips this set when no kept item drew an init. *)
let required_inits (sc : scope) (m : mode_arg) =
  match sc with
  | Sc_m18 -> (
      match m with
      | Ma_mixed | Ma_read_only | Ma_signal_writing -> [])
  | Sc_default | Sc_m20 -> (
      match m with
      | Ma_mixed | Ma_read_only | Ma_signal_writing -> init_shapes)

let excluded_for (sc : scope) (m : mode_arg) =
  match sc with
  | Sc_default | Sc_m20 | Sc_m18 -> (
      match m with
      | Ma_read_only -> List.append excluded_ast write_meths
      | Ma_mixed | Ma_signal_writing -> excluded_ast)

(* ---------- argument parsing ---------- *)

type parse =
  | P_ok of opts
  | P_usage of string

let usage =
  "usage: coverage [--samples N] [--seed S] [--mode \
   mixed|read-only|signal-writing]\n\
  \                [--scope default|m20|m18] [--strict] [--json]\n"

(* int_of_string_opt is total.  It takes a decimal literal, the 0x,
   0o and 0b prefixes and the _ separator, so --seed 10000 and
   --seed 0x4d3138 both parse in one call and 1_000 parses as 1000.
   That is wider than the flag table states, and is accepted. *)
let int_at_least lo s =
  Option.bind (int_of_string_opt s) (fun n -> if n >= lo then Some n else None)

let mode_of_name s =
  match s with
  | "mixed" -> Some Ma_mixed
  | "read-only" -> Some Ma_read_only
  | "signal-writing" -> Some Ma_signal_writing
  | _ -> None

let scope_of_name s =
  match s with
  | "default" -> Some Sc_default
  | "m20" -> Some Sc_m20
  | "m18" -> Some Sc_m18
  | _ -> None

(* Left to right, so a repeated flag takes the LAST value. *)
let rec parse_flags acc args =
  match args with
  | [] -> P_ok acc
  | "--strict" :: rest -> parse_flags { acc with strict = true } rest
  | "--json" :: rest -> parse_flags { acc with format = F_json } rest
  | "--samples" :: [] -> P_usage "--samples needs a value"
  | "--samples" :: v :: rest ->
      Option.fold
        ~none:(P_usage ("--samples wants an integer of 1 or more: " ^ v))
        ~some:(fun n -> parse_flags { acc with samples = n } rest)
        (int_at_least 1 v)
  | "--seed" :: [] -> P_usage "--seed needs a value"
  | "--seed" :: v :: rest ->
      Option.fold
        ~none:(P_usage ("--seed wants an integer of 0 or more: " ^ v))
        ~some:(fun n -> parse_flags { acc with seed = n } rest)
        (int_at_least 0 v)
  | "--mode" :: [] -> P_usage "--mode needs a value"
  | "--mode" :: v :: rest ->
      Option.fold
        ~none:(P_usage ("--mode wants mixed, read-only or signal-writing: " ^ v))
        ~some:(fun m -> parse_flags { acc with mode = m } rest)
        (mode_of_name v)
  | "--scope" :: [] -> P_usage "--scope needs a value"
  | "--scope" :: v :: rest ->
      Option.fold
        ~none:(P_usage ("--scope wants default, m20 or m18: " ^ v))
        ~some:(fun sc -> parse_flags { acc with scope = sc } rest)
        (scope_of_name v)
  | a :: _ -> P_usage ("unknown flag: " ^ a)

(* Scope m18 has no mode parameter, because Gen.gen_target takes
   none.  In that scope "mixed" means the classifier reads the mode
   off each body.  The check runs after the whole list, so the flag
   order does not change the verdict. *)
let check_cross (o : opts) =
  match o.scope with
  | Sc_m18 -> (
      match o.mode with
      | Ma_mixed -> P_ok o
      | Ma_read_only | Ma_signal_writing ->
          P_usage "--scope m18 accepts --mode mixed only")
  | Sc_default | Sc_m20 -> P_ok o

let parse_args acc args =
  match parse_flags acc args with
  | P_usage m -> P_usage m
  | P_ok o -> check_cross o

(* ---------- the draw ---------- *)

type item = {
  it_idx : int; (* 0-based draw index *)
  it_target : ty;
  it_body : expr;
  it_mode : Taxonomy.mode; (* requested, or classified in Sc_m18 *)
  it_env : (int * ty) list; (* the wf environment for it_body *)
  it_bindings : Sample.binding list; (* signals then inputs;  [] in Sc_m18 *)
  it_signals : Sample.binding list; (* [] in Sc_m18 *)
  it_inits_drawn : bool; (* false in Sc_m18 *)
}

let item_of_sample idx (s : Sample.t) =
  {
    it_idx = idx;
    it_target = s.Sample.target;
    it_body = s.Sample.body;
    it_mode = s.Sample.mode;
    it_env = Sample.wf_env s;
    it_bindings = List.append s.Sample.signals s.Sample.inputs;
    it_signals = s.Sample.signals;
    it_inits_drawn = true;
  }

(* The M18 stream carries no environment draw, so the mode is read off
   the body and no init exists to check. *)
let item_of_pair idx p =
  {
    it_idx = idx;
    it_target = fst p;
    it_body = snd p;
    it_mode = Taxonomy.mode_of (snd p);
    it_env = Gen.wf_env Gen.default_genv;
    it_bindings = [];
    it_signals = [];
    it_inits_drawn = false;
  }

let gen_for m20 w (m : mode_arg) =
  match m with
  | Ma_mixed -> Sample_gen.gen_sample m20 w
  | Ma_read_only -> Sample_gen.gen_sample_at m20 w Taxonomy.Read_only
  | Ma_signal_writing -> Sample_gen.gen_sample_at m20 w Taxonomy.Signal_writing

(* The Sc_m18 arm copies test/test_gen.ml's draw expression: the same
   QCheck.Gen.generate call over the same Random.State.make seed
   array, so at n=10000 and seed 0x4d3138 the two streams are one
   stream and the two constructor blocks are byte-identical. *)
let draw (o : opts) =
  match o.scope with
  | Sc_default ->
      List.mapi item_of_sample
        (QCheck.Gen.generate ~n:o.samples
           ~rand:(Random.State.make [| o.seed |])
           (gen_for false Weights.default o.mode))
  | Sc_m20 ->
      List.mapi item_of_sample
        (QCheck.Gen.generate ~n:o.samples
           ~rand:(Random.State.make [| o.seed |])
           (gen_for true Weights.m20 o.mode))
  | Sc_m18 ->
      List.mapi item_of_pair
        (QCheck.Gen.generate ~n:o.samples
           ~rand:(Random.State.make [| o.seed |])
           (Gen.gen_target Gen.default_genv))

(* ---------- drops ---------- *)

type drop_reason =
  | Dr_wf_error (* Wf.check_top returned Error *)
  | Dr_wf_type_mismatch (* the inferred type is not ty_eq to the target *)
  | Dr_mode_mismatch (* Sample.mode_ok is false *)
  | Dr_init_wf (* an init is not wf at its declared type *)
  | Dr_init_stuck (* Interp.eval_init returned None on an init *)
  | Dr_print_empty (* Printer_rust.print returned "" *)

let drop_reason_name r =
  match r with
  | Dr_wf_error -> "wf_error"
  | Dr_wf_type_mismatch -> "wf_type_mismatch"
  | Dr_mode_mismatch -> "mode_mismatch"
  | Dr_init_wf -> "init_wf"
  | Dr_init_stuck -> "init_stuck"
  | Dr_print_empty -> "print_empty"

let drop_reasons_all =
  [
    Dr_wf_error; Dr_wf_type_mismatch; Dr_mode_mismatch; Dr_init_wf;
    Dr_init_stuck; Dr_print_empty;
  ]

let drop_reason_eq a b = String.equal (drop_reason_name a) (drop_reason_name b)

type verdict =
  | V_kept
  | V_dropped of drop_reason

let is_kept v =
  match v with
  | V_kept -> true
  | V_dropped _ -> false

(* The interpreter step budget per init, the value test/test_sample.ml
   already uses. *)
let init_fuel = 10_000

let init_wf_ok (b : Sample.binding) =
  Result.fold
    ~ok:(fun t -> ty_eq b.Sample.ty t)
    ~error:(fun _e -> false)
    (Wf.check_top [] b.Sample.init)

let init_reduces (b : Sample.binding) =
  Option.fold ~none:false
    ~some:(fun _v -> true)
    (Interp.eval_init Ops.interp_ops init_fuel b.Sample.init)

(* mode_ok reads the recorded mode and the body only, so an item can
   answer it through a sample that carries just those two. *)
let item_mode_ok (it : item) =
  Sample.mode_ok
    {
      Sample.mode = it.it_mode;
      inputs = [];
      signals = [];
      target = it.it_target;
      body = it.it_body;
    }

(* The checks run in the order of drop_reasons_all and the FIRST
   failure wins, so one sample gets exactly one reason and the reason
   table counts samples, not faults.  Dr_init_wf and Dr_init_stuck
   are skipped when the scope drew no inits.

   The renderer is a parameter, not Ops.printer_renderer inline, for
   one reason: Dr_print_empty is unreachable through the real
   renderer, and a test renderer whose lit_str returns "" is the only
   way to force it. *)
let classify (r : Printer_rust.renderer) (it : item) =
  let inferred = Wf.check_top it.it_env it.it_body in
  let wf_ok =
    Result.fold ~ok:(fun _t -> true) ~error:(fun _e -> false) inferred
  in
  let ty_ok =
    Result.fold
      ~ok:(fun t -> ty_eq it.it_target t)
      ~error:(fun _e -> false)
      inferred
  in
  let mode_ok = item_mode_ok it in
  let inits_wf =
    (not it.it_inits_drawn) || List.for_all init_wf_ok it.it_bindings
  in
  let inits_live =
    (not it.it_inits_drawn) || List.for_all init_reduces it.it_bindings
  in
  let printed = Printer_rust.print r it.it_body in
  match () with
  | () when not wf_ok -> V_dropped Dr_wf_error
  | () when not ty_ok -> V_dropped Dr_wf_type_mismatch
  | () when not mode_ok -> V_dropped Dr_mode_mismatch
  | () when not inits_wf -> V_dropped Dr_init_wf
  | () when not inits_live -> V_dropped Dr_init_stuck
  | () when String.length printed = 0 -> V_dropped Dr_print_empty
  | () -> V_kept

type drop = {
  dr_idx : int;
  dr_reason : drop_reason;
  dr_bytes : int; (* the length of the FULL escaped text *)
  dr_text : string; (* escaped, then truncated *)
}

(* ---------- escaping and truncation ---------- *)

let drop_text_max = 200

(* Percent escaping.  The result is printable ASCII with no quote and
   no backslash, so the same string is legal inside a JSON string
   with no second escaping pass, and a truncation can never split an
   escape into something ambiguous.  The scan is String.fold_left
   because String.get is denied. *)
let esc_byte c =
  let n = Char.code c in
  match () with
  | () when n = 0x25 -> "%25"
  | () when n = 0x22 -> "%22"
  | () when n = 0x5C -> "%5C"
  | () when n < 0x20 || n > 0x7E -> "%" ^ hex_byte n
  | () -> String.make 1 c

let esc_pct s = String.fold_left (fun acc c -> acc ^ esc_byte c) "" s

let sub_prefix s k =
  if k >= 0 && k <= String.length s then String.sub s 0 k (* @total-accessor *)
  else s

(* Truncation is by escaped BYTES.  The [+N] suffix is the truncation
   marker and N is how many escaped bytes were cut. *)
let clamp_text s =
  let e = esc_pct s in
  let n = String.length e in
  match () with
  | () when n <= drop_text_max -> (e, n)
  | () ->
      ( sub_prefix e drop_text_max ^ "[+"
        ^ string_of_int (n - drop_text_max)
        ^ "]",
        n )

(* ---------- counters ---------- *)

(* Only KEPT items feed every histogram.  A dropped item appears in
   the drops section and the reason table and nowhere else, so it can
   never inflate a coverage number. *)
let kept scored = List.map fst (List.filter (fun p -> is_kept (snd p)) scored)

let drops_of (r : Printer_rust.renderer) scored =
  List.filter_map
    (fun p ->
      match snd p with
      | V_kept -> None
      | V_dropped reason ->
          let it = fst p in
          let ct = clamp_text (Printer_rust.print r it.it_body) in
          Some
            {
              dr_idx = it.it_idx;
              dr_reason = reason;
              dr_bytes = snd ct;
              dr_text = fst ct;
            })
    scored

let tally_of items =
  Tally.of_samples (List.map (fun it -> (it.it_target, it.it_body)) items)

let all_bindings items = List.concat_map (fun it -> it.it_bindings) items

let tally_inits items =
  Tally.of_samples
    (List.map
       (fun (b : Sample.binding) -> (b.Sample.ty, b.Sample.init))
       (all_bindings items))

let unreached names m = List.filter (fun k -> Tally.count k m = 0) names
let reached names m = List.filter (fun k -> Tally.count k m > 0) names

(* Literal predicates, copied from test/test_sample.ml so the two
   agree.  test_sample's is_inf_lit covers both signs at once;  M22
   splits it into a positive and a negative form, because the report
   wants +inf and -inf as separate classes.  Both are reachable:
   Gen.f64_pool holds infinity and neg_infinity. *)
let is_nan_lit (l : lit) =
  match l with
  | L_f64_bits (hi, lo) ->
      hi land 0x7FF00000 = 0x7FF00000 && (lo <> 0 || hi land 0xFFFFF <> 0)
  | L_bool _ | L_str _ -> false

let is_pos_inf_lit (l : lit) =
  match l with
  | L_f64_bits (hi, lo) -> hi = 0x7FF00000 && lo = 0
  | L_bool _ | L_str _ -> false

let is_neg_inf_lit (l : lit) =
  match l with
  | L_f64_bits (hi, lo) -> hi = 0xFFF00000 && lo = 0
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

(* Literals inside an initializer, exhaustive over expr as
   test_sample's own walk is. *)
let rec init_lits (e : expr) : lit list =
  match e with
  | E_lit l -> [ l ]
  | E_some a -> init_lits a
  | E_ok (a, _) -> init_lits a
  | E_err (a, _) -> init_lits a
  | E_tuple es -> List.concat_map init_lits es
  | E_none _ | E_block_unit _ | E_var _
  | E_unary (_, _)
  | E_binary (_, _, _)
  | E_call (_, _)
  | E_method (_, _, _)
  | E_field (_, _)
  | E_index (_, _)
  | E_let (_, _)
  | E_block (_, _)
  | E_if (_, _)
  | E_if_else (_, _, _)
  | E_loop _
  | E_while (_, _)
  | E_break | E_continue | E_return_unit | E_return _
  | E_closure (_, _, _)
  | E_async_closure (_, _, _)
  | E_await _ ->
      []

(* The TOP constructor of a type.  Ast.ty_to_string is unbounded on a
   nested type and must not key a histogram. *)
let ty_head (t : ty) =
  match t with
  | T_f64 -> "T_f64"
  | T_bool -> "T_bool"
  | T_string -> "T_string"
  | T_unit -> "T_unit"
  | T_option _ -> "T_option"
  | T_result (_, _) -> "T_result"
  | T_tuple _ -> "T_tuple"
  | T_fn (_, _) -> "T_fn"
  | T_async_fn (_, _) -> "T_async_fn"
  | T_future _ -> "T_future"
  | T_signal _ -> "T_signal"

let ty_heads_all =
  [
    "T_f64"; "T_bool"; "T_string"; "T_unit"; "T_option"; "T_result";
    "T_tuple"; "T_fn"; "T_async_fn"; "T_future"; "T_signal";
  ]

(* One plus the sizes of the children, one arm per Ast.expr
   constructor. *)
let rec expr_size (e : expr) =
  match e with
  | E_lit _ -> 1
  | E_var _ -> 1
  | E_unary (_, a) -> 1 + expr_size a
  | E_binary (_, a, b) -> 1 + expr_size a + expr_size b
  | E_tuple es -> 1 + expr_size_list es
  | E_some a -> 1 + expr_size a
  | E_none _ -> 1
  | E_ok (a, _) -> 1 + expr_size a
  | E_err (a, _) -> 1 + expr_size a
  | E_call (f, args) -> 1 + expr_size f + expr_size_list args
  | E_method (recv, _, args) -> 1 + expr_size recv + expr_size_list args
  | E_field (a, _) -> 1 + expr_size a
  | E_index (a, b) -> 1 + expr_size a + expr_size b
  | E_let (_, a) -> 1 + expr_size a
  | E_block (ss, tail) -> 1 + expr_size_list ss + expr_size tail
  | E_block_unit ss -> 1 + expr_size_list ss
  | E_if (c, t) -> 1 + expr_size c + expr_size t
  | E_if_else (c, t, f) -> 1 + expr_size c + expr_size t + expr_size f
  | E_loop b -> 1 + expr_size b
  | E_while (c, b) -> 1 + expr_size c + expr_size b
  | E_break -> 1
  | E_continue -> 1
  | E_return_unit -> 1
  | E_return a -> 1 + expr_size a
  | E_closure (_, _, b) -> 1 + expr_size b
  | E_async_closure (_, _, b) -> 1 + expr_size b
  | E_await a -> 1 + expr_size a

and expr_size_list es = List.fold_left (fun acc x -> acc + expr_size x) 0 es

let size_min sizes =
  match sizes with
  | [] -> 0
  | h :: rest -> List.fold_left min h rest

let size_max sizes =
  match sizes with
  | [] -> 0
  | h :: rest -> List.fold_left max h rest

let size_mean_milli sizes =
  let total = List.fold_left (fun acc x -> acc + x) 0 sizes in
  Option.fold ~none:0
    ~some:(fun x -> x)
    (Prelude.div_opt (total * 1000) (List.length sizes))

let count_if p xs = List.length (List.filter p xs)

(* ---------- the report as data ---------- *)

type field =
  | F_int of string * int
  | F_str of string * string
  | F_names of string * string list
  | F_tally of string * (string * int) list
  | F_drops of string * drop list

type section = {
  s_title : string;
  s_fields : field list;
}

type run = {
  r_opts : opts;
  r_scored : (item * verdict) list;
  r_drops : drop list;
}

let run_of (r : Printer_rust.renderer) (o : opts) =
  let scored = List.map (fun it -> (it, classify r it)) (draw o) in
  { r_opts = o; r_scored = scored; r_drops = drops_of r scored }

let mode_source (sc : scope) =
  match sc with
  | Sc_m18 -> "classifier"
  | Sc_default | Sc_m20 -> "generator"

let env_source (sc : scope) =
  match sc with
  | Sc_m18 -> "none"
  | Sc_default | Sc_m20 -> "drawn"

let mode_is m (it : item) = Taxonomy.mode_eq it.it_mode m

let classified_is m (it : item) =
  Taxonomy.mode_eq (Taxonomy.mode_of it.it_body) m

let header_section (run : run) items =
  {
    s_title = "coverage report";
    s_fields =
      [
        F_int ("samples_requested", run.r_opts.samples);
        F_int ("samples_kept", List.length items);
        F_int ("samples_dropped", List.length run.r_drops);
        F_str ("seed", hex_str run.r_opts.seed);
        F_str ("mode", mode_arg_name run.r_opts.mode);
        F_str ("scope", scope_name run.r_opts.scope);
      ];
  }

(* The init half of the required set applies only where an init
   exists.  Scope m18 draws no environment, and a hand-built run may
   carry no binding, so an empty init tally in either case is not a
   miss. *)
let inits_drawn items = List.exists (fun it -> it.it_inits_drawn) items

let required_inits_for (run : run) items =
  match inits_drawn items with
  | true -> required_inits run.r_opts.scope run.r_opts.mode
  | false -> []

let tally_section (run : run) items t =
  {
    s_title =
      "constructor tally (n="
      ^ string_of_int run.r_opts.samples
      ^ ", seed " ^ hex_str run.r_opts.seed ^ ", scope "
      ^ scope_name run.r_opts.scope
      ^ ", mode "
      ^ mode_arg_name run.r_opts.mode
      ^ ")";
    s_fields =
      [
        F_tally ("tally", t);
        F_names
          ( "unreached_required",
            unreached (required_for run.r_opts.scope run.r_opts.mode) t );
        F_names
          ( "unreached_required_inits",
            unreached (required_inits_for run items) (tally_inits items) );
        F_names
          ( "reached_excluded",
            reached (excluded_for run.r_opts.scope run.r_opts.mode) t );
      ];
  }

(* mode_mismatches counts the KEPT items, and a mismatch is itself a
   drop reason, so this counter is 0 by construction and stays a
   tripwire.  The mismatched samples are in the drops section. *)
let mode_section (run : run) items =
  {
    s_title = "mode counters";
    s_fields =
      [
        F_str ("mode_source", mode_source run.r_opts.scope);
        F_int
          ("requested_read_only", count_if (mode_is Taxonomy.Read_only) items);
        F_int
          ( "requested_signal_writing",
            count_if (mode_is Taxonomy.Signal_writing) items );
        F_int
          ( "classified_read_only",
            count_if (classified_is Taxonomy.Read_only) items );
        F_int
          ( "classified_signal_writing",
            count_if (classified_is Taxonomy.Signal_writing) items );
        F_int
          ("mode_mismatches", count_if (fun it -> not (item_mode_ok it)) items);
      ];
  }

(* Section (d).  Every key up to init_f64 reads the drawn
   environment, so scope m18, which draws none, prints them all at 0.
   The five write_M_* keys do NOT: they are a BODY count, taken from
   tally_of over the kept bodies, the same tally section (b) reports.
   They stay non-zero in a scope that has no environment at all.
   Spec 2.G states both "the section (d) counters are all 0 in m18"
   and "write_M_* come from tally_of on the kept bodies".  The two
   sentences disagree;  the code follows the second one, and this
   comment is here so a later reader does not read write_M_* as an
   environment counter. *)
let env_section (run : run) items =
  let sigs = List.concat_map (fun it -> it.it_signals) items in
  let lits =
    List.concat_map
      (fun (b : Sample.binding) -> init_lits b.Sample.init)
      (all_bindings items)
  in
  let ti = tally_inits items in
  let tb = tally_of items in
  let sig_count k = count_if (fun it -> List.length it.it_signals = k) items in
  let elem_count name =
    count_if
      (fun (b : Sample.binding) -> String.equal (ty_head b.Sample.ty) name)
      sigs
  in
  {
    s_title = "environment coverage";
    s_fields =
      List.append
        [
          F_str ("env_source", env_source run.r_opts.scope);
          F_int ("signals_1", sig_count 1);
          F_int ("signals_2", sig_count 2);
          F_int ("signals_3", sig_count 3);
          F_int ("elem_T_f64", elem_count "T_f64");
          F_int ("elem_T_bool", elem_count "T_bool");
          F_int ("elem_T_string", elem_count "T_string");
          F_int ("init_nan", count_if is_nan_lit lits);
          F_int ("init_pos_inf", count_if is_pos_inf_lit lits);
          F_int ("init_neg_inf", count_if is_neg_inf_lit lits);
          F_int ("init_empty_str", count_if is_empty_str_lit lits);
          F_int ("init_multibyte_str", count_if is_multibyte_str_lit lits);
          F_int ("init_none", Tally.count "E_none" ti);
          F_int ("init_some", Tally.count "E_some" ti);
          F_int ("init_ok", Tally.count "E_ok" ti);
          F_int ("init_err", Tally.count "E_err" ti);
          F_int ("init_bool", Tally.count "L_bool" ti);
          F_int ("init_str", Tally.count "L_str" ti);
          F_int ("init_f64", Tally.count "L_f64_bits" ti);
        ]
        (List.map (fun k -> F_int ("write_" ^ k, Tally.count k tb)) write_meths);
  }

let size_section items =
  let sizes = List.map (fun it -> expr_size it.it_body) items in
  {
    s_title = "target types and size";
    s_fields =
      List.append
        (List.map
           (fun k ->
             F_int
               ( "target_" ^ k,
                 count_if
                   (fun it -> String.equal (ty_head it.it_target) k)
                   items ))
           ty_heads_all)
        [
          F_int ("expr_size_min", size_min sizes);
          F_int ("expr_size_mean_milli", size_mean_milli sizes);
          F_int ("expr_size_max", size_max sizes);
        ];
  }

let drops_section (run : run) =
  {
    s_title = "drops";
    s_fields =
      F_drops ("drops", run.r_drops)
      :: List.map
           (fun r ->
             F_int
               ( "drop_" ^ drop_reason_name r,
                 count_if (fun d -> drop_reason_eq d.dr_reason r) run.r_drops ))
           drop_reasons_all;
  }

(* Six sections, always the same key set, so the JSON schema does not
   move with the scope.  In scope m18 env_source is none and every
   counter that reads the environment is 0.  The five write_M_* keys
   are body counts, not environment counters, so they stay non-zero
   there;  see env_section. *)
let sections (run : run) =
  let items = kept run.r_scored in
  [
    header_section run items;
    tally_section run items (tally_of items);
    mode_section run items;
    env_section run items;
    size_section items;
    drops_section run;
  ]

(* ---------- text ---------- *)

let drop_line d =
  "drop idx=" ^ string_of_int d.dr_idx ^ " reason="
  ^ drop_reason_name d.dr_reason
  ^ " bytes=" ^ string_of_int d.dr_bytes ^ " text=" ^ d.dr_text ^ "\n"

(* F_tally renders Tally.report verbatim, with no added prefix and no
   reordering, so the block is byte-comparable with the M18 block.
   text= is always the LAST field on a drop line, because the escaped
   text may hold a space. *)
let field_text f =
  match f with
  | F_int (k, n) -> k ^ " " ^ string_of_int n ^ "\n"
  | F_str (k, v) -> k ^ " " ^ v ^ "\n"
  | F_names (k, ns) -> (
      match ns with
      | [] -> k ^ " none\n"
      | _ :: _ -> k ^ " " ^ String.concat " " ns ^ "\n")
  | F_tally (_, m) -> Tally.report m
  | F_drops (_, ds) -> (
      match ds with
      | [] -> "drop_none\n"
      | _ :: _ -> String.concat "" (List.map drop_line ds))

let section_text s =
  s.s_title ^ "\n" ^ String.concat "" (List.map field_text s.s_fields)

(* One blank line after every section except the last. *)
let rec sections_text ss =
  match ss with
  | [] -> ""
  | s :: [] -> section_text s
  | s :: rest -> section_text s ^ "\n" ^ sections_text rest

let text_report (run : run) = sections_text (sections run)

(* ---------- json ---------- *)

(* No string needs an escaping pass here.  The only strings that
   reach the JSON are the fixed key names, the fixed enum spellings,
   the 0x seed and esc_pct output, and esc_pct emits printable ASCII
   with no quote and no backslash.  That invariant is what keeps this
   writer short. *)
let json_str s = "\"" ^ s ^ "\""
let json_names ns = "[" ^ String.concat "," (List.map json_str ns) ^ "]"

let json_tally m =
  let sorted = List.sort (fun a b -> compare (fst a) (fst b)) m in
  "{"
  ^ String.concat ","
      (List.map
         (fun kv -> json_str (fst kv) ^ ":" ^ string_of_int (snd kv))
         sorted)
  ^ "}"

let json_drop d =
  "{\"idx\":" ^ string_of_int d.dr_idx ^ ",\"reason\":"
  ^ json_str (drop_reason_name d.dr_reason)
  ^ ",\"bytes\":" ^ string_of_int d.dr_bytes ^ ",\"text\":"
  ^ json_str d.dr_text ^ "}"

let field_json f =
  match f with
  | F_int (k, n) -> json_str k ^ ":" ^ string_of_int n
  | F_str (k, v) -> json_str k ^ ":" ^ json_str v
  | F_names (k, ns) -> json_str k ^ ":" ^ json_names ns
  | F_tally (k, m) -> json_str k ^ ":" ^ json_tally m
  | F_drops (k, ds) ->
      json_str k ^ ":[" ^ String.concat "," (List.map json_drop ds) ^ "]"

(* One line, then one newline.  The section titles do not appear. *)
let json_report (run : run) =
  "{"
  ^ String.concat ","
      (List.concat_map (fun s -> List.map field_json s.s_fields) (sections run))
  ^ "}\n"

let render (run : run) =
  match run.r_opts.format with
  | F_text -> text_report run
  | F_json -> json_report run

(* ---------- verdict ---------- *)

(* Four conjuncts, one per claim the gate makes: nothing was dropped,
   every required BODY name was reached in the kept bodies, every
   required INIT shape was reached in the drawn initial values, and no
   excluded name was reached. *)
let strict_ok (run : run) =
  let items = kept run.r_scored in
  let t = tally_of items in
  List.length run.r_drops = 0
  && unreached (required_for run.r_opts.scope run.r_opts.mode) t = []
  && unreached (required_inits_for run items) (tally_inits items) = []
  && reached (excluded_for run.r_opts.scope run.r_opts.mode) t = []

(* The report prints in both cases. *)
let exit_code (run : run) =
  match () with
  | () when run.r_opts.strict && not (strict_ok run) -> 1
  | () -> 0

(* ---------- entry point ---------- *)

type out = {
  o_stdout : string;
  o_stderr : string;
  o_code : int;
}

(* The list is Array.to_list Sys.argv, argv0 included;  it is dropped
   with a list match, never with an index. *)
let main (r : Printer_rust.renderer) argv =
  match argv with
  | [] -> { o_stdout = ""; o_stderr = usage; o_code = 2 }
  | _ :: rest -> (
      match parse_args default_opts rest with
      | P_usage msg ->
          { o_stdout = ""; o_stderr = msg ^ "\n" ^ usage; o_code = 2 }
      | P_ok o ->
          let run = run_of r o in
          { o_stdout = render run; o_stderr = ""; o_code = exit_code run })
