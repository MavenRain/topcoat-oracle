(* M21 sample environment generator (DESIGN.md M21).

   Draws a whole Sample.t: the input bindings, the signal bindings,
   the mode, and the body at that mode through Gen.gen_at_mode.

   Inputs keep the fixed shape of Gen.default_genv MINUS the fn-typed
   v10, with DRAWN initial values. expr! lowers every call to
   .call(), which rustc rejects outside a #[procedure] value
   (research/m20-expr-macro-probe.md), so a function-typed input
   cannot appear in a sample the rust leg has to compile. The ids
   stay the driver's: 0, 1, 2 for the scalars and 6..9 for the
   annotated Result and Option inputs, so a sample and the M20 batch
   crate name the same variables.

   Signals: 1..3 of them at ids 3, 4, 5, element type drawn per
   signal from f64 / bool / String. Those are the three element types
   the corpus declares (census: String x4, f64 x2, bool x1) and the
   three SignalSurrogate implements the write shorthands for.
   Duplicates are allowed, so two signals can share a type; the
   corpus has four String signals in one file. Fresh let ids start
   above the highest id in scope, which Gen.first_fresh computes from
   the genv, so a drawn let can never shadow an input or a signal.

   The initial-value pool is NEW and local to this module on purpose.
   The literal pools in gen.ml feed the M18 counter report and the
   M20 batch, both of which must stay byte-identical, so nothing here
   touches them. The one reuse is Gen.gen_f64_bits, which keeps the
   full f64 pool including the non-finite specials and the random bit
   patterns: NaN and infinity inputs are a target risk class, so the
   generator draws them. How a non-finite BINDING renders outside
   expr! (f64::NAN is a path expression, not a literal, and the
   driver writes the binding outside the macro) is M23's call, not
   this module's.

   String pool escaping: Printer_rust renders L_str through the
   injected renderer, which is Strops.debug. That escapes the quote,
   the backslash, newline, carriage return, tab and NUL, maps the
   remaining C0 bytes and DEL to \u{..}, and passes printable
   non-ASCII bytes through verbatim, so a multibyte UTF-8 entry
   round-trips as itself. Every entry below therefore prints as a
   valid Rust string literal; checked against shell/strops.ml
   escape_char at this pin. *)

open Ast

module G = QCheck.Gen

let ( >>= ) = G.( >>= )

(* ---------- initial-value pools ---------- *)

let init_str_pool =
  [
    "" (* empty: the is_empty and len=0 surface *);
    "a";
    "hello";
    " pad " (* leading and trailing space: the trim surface *);
    "\xc3\xa9" (* e acute: 2 UTF-8 bytes, 1 UTF-16 unit *);
    "\xe2\x82\xac" (* euro sign: 3 bytes, 1 UTF-16 unit *);
    "\xf0\x9f\x98\x80" (* grinning face: 4 bytes, 2 UTF-16 units *);
    "a\"b" (* quote escape *);
    "a\\b" (* backslash escape *);
    "line\nbreak";
    "tab\t";
  ]

let alnum_pool =
  [
    'a'; 'b'; 'c'; 'd'; 'e'; 'f'; 'g'; 'h'; 'i'; 'j'; 'k'; 'l'; 'm'; 'n';
    'o'; 'p'; 'q'; 'r'; 's'; 't'; 'u'; 'v'; 'w'; 'x'; 'y'; 'z'; 'A'; 'B';
    'C'; 'D'; 'E'; 'F'; 'G'; 'H'; 'I'; 'J'; 'K'; 'L'; 'M'; 'N'; 'O'; 'P';
    'Q'; 'R'; 'S'; 'T'; 'U'; 'V'; 'W'; 'X'; 'Y'; 'Z'; '0'; '1'; '2'; '3';
    '4'; '5'; '6'; '7'; '8'; '9';
  ]

let gen_alnum_char =
  match alnum_pool with
  | [] -> G.return 'a'
  | c :: cs -> Gen.pick_elt c cs

let rec gen_alnum_chars n =
  if n <= 0 then G.return []
  else
    gen_alnum_char >>= fun c ->
    gen_alnum_chars (n - 1) >>= fun cs -> G.return (c :: cs)

let gen_alnum_str =
  G.int_bound 8 >>= fun n ->
  gen_alnum_chars n >>= fun cs ->
  G.return (String.concat "" (List.map (String.make 1) cs))

(* Uniform over the fixed entries plus one random ASCII alnum string
   of length 0..8: the out-of-range index is the random branch, so
   all twelve alternatives are equally likely. *)
let gen_init_str =
  G.int_bound (List.length init_str_pool) >>= fun i ->
  Option.fold ~none:gen_alnum_str ~some:G.return
    (List.nth_opt init_str_pool i)

(* A CLOSED initializer at a type: no free variables, no signals, no
   calls, so Wf.check_top [] accepts it and Interp.eval_init reduces
   it in the empty environment. Total over ty; the four arms the
   input shape never asks for are tripwires. *)
let rec gen_init (w : Weights.t) (t : ty) =
  match t with
  | T_f64 ->
      Gen.gen_f64_bits w >>= fun p ->
      G.return (E_lit (L_f64_bits (fst p, snd p)))
  | T_bool -> G.bool >>= fun b -> G.return (E_lit (L_bool b))
  | T_string -> gen_init_str >>= fun s -> G.return (E_lit (L_str s))
  | T_unit -> G.return (E_block_unit [])
  | T_option a ->
      G.bool >>= fun is_some ->
      if is_some then gen_init w a >>= fun e -> G.return (E_some e)
      else G.return (E_none a)
  | T_result (a, e) ->
      G.bool >>= fun is_ok ->
      if is_ok then gen_init w a >>= fun x -> G.return (E_ok (x, e))
      else gen_init w e >>= fun x -> G.return (E_err (x, a))
  | T_tuple ts -> gen_init_list w ts >>= fun es -> G.return (E_tuple es)
  | T_fn (_, _) | T_async_fn (_, _) | T_future _ | T_signal _ ->
      (* Tripwire. None of the four has a closed literal form the
         driver can write outside expr!, and the input shape below
         holds none of them. E_block_unit [] fails
         Wf.check_top [] init = Ok t, so the gate's init check goes
         red the moment a drift adds such an input, instead of
         emitting an init the rust driver cannot render. *)
      G.return (E_block_unit [])

and gen_init_list w ts =
  match ts with
  | [] -> G.return []
  | t :: rest ->
      gen_init w t >>= fun e ->
      gen_init_list w rest >>= fun es -> G.return (e :: es)

(* ---------- environment shape ---------- *)

let input_shape =
  [
    (0, T_f64);
    (1, T_bool);
    (2, T_string);
    (6, T_result (T_f64, T_string));
    (7, T_result (T_string, T_f64));
    (8, T_option T_f64);
    (9, T_option T_string);
  ]

let sig_elem_first = T_f64
let sig_elem_rest = [ T_bool; T_string ]
let sig_id_first = 3

let binding id t init : Sample.binding =
  { Sample.id = id; ty = t; init = init }

let rec gen_input_list w shape =
  match shape with
  | [] -> G.return []
  | kv :: rest ->
      gen_init w (snd kv) >>= fun e ->
      gen_input_list w rest >>= fun more ->
      G.return (binding (fst kv) (snd kv) e :: more)

let gen_inputs w = gen_input_list w input_shape

let rec gen_signal_list w k id =
  if k <= 0 then G.return []
  else
    Gen.pick_elt sig_elem_first sig_elem_rest >>= fun t ->
    gen_init w t >>= fun e ->
    gen_signal_list w (k - 1) (id + 1) >>= fun more ->
    G.return (binding id t e :: more)

let gen_signals w =
  G.int_bound 2 >>= fun extra -> gen_signal_list w (extra + 1) sig_id_first

let gen_env w =
  gen_inputs w >>= fun ins ->
  gen_signals w >>= fun sigs -> G.return (ins, sigs)

(* The generation environment the expression draw needs: same ids and
   types, signal element types left unwrapped (Gen.wf_env does the
   T_signal wrapping, exactly as Sample.wf_env does). *)
let genv_of ins sigs : Gen.genv =
  {
    Gen.inputs = List.map (fun b -> (b.Sample.id, b.Sample.ty)) ins;
    signals = List.map (fun b -> (b.Sample.id, b.Sample.ty)) sigs;
  }

let sample_of mode ins sigs p : Sample.t =
  {
    Sample.mode = mode;
    inputs = ins;
    signals = sigs;
    target = fst p;
    body = snd p;
  }

(* ---------- entry points ---------- *)

let gen_sample_at m20 (w : Weights.t) (mode : Taxonomy.mode) =
  gen_env w >>= fun env ->
  Gen.gen_at_mode m20 w (genv_of (fst env) (snd env)) mode >>= fun p ->
  G.return (sample_of mode (fst env) (snd env) p)

(* The mode draw sits between the environment and the body, so both
   modes see the same environment stream. *)
let gen_mode (w : Weights.t) =
  Gen.pick_w
    (w.mode_read, fun () -> G.return Taxonomy.Read_only)
    [ (w.mode_write, fun () -> G.return Taxonomy.Signal_writing) ]

let gen_sample m20 (w : Weights.t) =
  gen_env w >>= fun env ->
  gen_mode w >>= fun mode ->
  Gen.gen_at_mode m20 w (genv_of (fst env) (snd env)) mode >>= fun p ->
  G.return (sample_of mode (fst env) (snd env) p)
