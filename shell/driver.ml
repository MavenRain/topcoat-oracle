(* M23 rust-leg driver-crate builders (DESIGN.md M23).

   Pure: every builder maps its inputs to text, byte-deterministically,
   so emitting twice yields identical crates.  bin/emit_m23.ml prints
   one file to stdout and m23_gate.sh owns every mkdir and redirect,
   exactly as shell/emit.ml and bin/emit_m20.ml split M20.  Rust
   flow-keyword text enters only through Printer_rust.print at run
   time, never as a source literal here.

   The harness is NOT emitted: driver-rs/harness.rs is a static file
   the gate copies into the crate as src/harness.rs, so the file rustc
   compiles is the file in the repo.  This module decides only which
   case functions call into it.

   Each case function is its own fn with fresh lets, and each of the
   two expr! sites inside it re-derives its externals from a mirror
   local: every expr! takes each non-Copy external by value (M20 round
   1), so two invocations must never share a binding.

   Caps, bounds and drops:

   | item | value | why |
   | --- | --- | --- |
   | one case fn per kept sample | 1 | one fn per sample, as M20 |
   | expr! sites per case | 1 or 2 | the closure site only when the body may panic |
   | mirror local per binding | 1 | the value channel of a signal, and the source of both sites' externals |
   | Signal handle per site | 1 per signal | Signal has no Clone (crates/topcoat-runtime/src/signal.rs:35-39), so each site mints its own |
   | drop rust_ty | a binding type with no Rust spelling | tuples and the four tripwire types |
   | drop init_rust | a binding init with no closed Rust form | same four, through gen_init's tripwire |
   | drop target | a target type outside the Observe set | tuples, fn, future, signal |

   The m20 input shape (shell/sample_gen.ml:142-157) holds only f64,
   bool, String, the two Results and the two Options, and signal
   elements are only f64, bool and String, so at the m20 scope no
   drop reason can fire.  They exist because a scope drift must drop a
   sample loudly, with a named reason in the count sidecar, instead of
   emitting a crate rustc rejects. *)

open Prelude
open Ast

(* ---------- drops ---------- *)

type drop_reason =
  | Dr_rust_ty
  | Dr_init_rust
  | Dr_target

let drop_reason_name (r : drop_reason) : string =
  match r with
  | Dr_rust_ty -> "rust_ty"
  | Dr_init_rust -> "init_rust"
  | Dr_target -> "target"

let all_drop_reasons = [ Dr_rust_ty; Dr_init_rust; Dr_target ]

let drop_reason_eq (a : drop_reason) (b : drop_reason) : bool =
  match a with
  | Dr_rust_ty -> (match b with Dr_rust_ty -> true | Dr_init_rust | Dr_target -> false)
  | Dr_init_rust -> (match b with Dr_init_rust -> true | Dr_rust_ty | Dr_target -> false)
  | Dr_target -> (match b with Dr_target -> true | Dr_rust_ty | Dr_init_rust -> false)

let req (r : drop_reason) (o : 'a option) : ('a, drop_reason) result =
  Option.fold ~none:(Error r) ~some:(fun v -> Ok v) o

let rec seq_result (xs : ('a, drop_reason) result list) :
    ('a list, drop_reason) result =
  match xs with
  | [] -> Ok []
  | x :: rest ->
      Result.bind x (fun v -> Result.map (fun vs -> v :: vs) (seq_result rest))

let keep p xs =
  rev (fold (fun acc x -> match () with () when p x -> x :: acc | () -> acc) [] xs)

(* ---------- the static panic-class hint (build brief R2) ---------- *)

(* std gives Option::expect(m) and Result::expect_err(m) the user
   message and nothing else, so the panic text alone cannot name those
   two classes.  The emitter reads the body instead: Expect when the
   body mentions expect and not expect_err, ExpectErr for the
   converse, Both when it mentions both, None otherwise.  The harness
   consults it only when no prefix matched, and Both yields class
   other, which the gate accepts only on a line whose hint is both. *)
type hint =
  | H_none
  | H_expect
  | H_expect_err
  | H_both

let hint_ctor (h : hint) : string =
  match h with
  | H_none -> "harness::Hint::None"
  | H_expect -> "harness::Hint::Expect"
  | H_expect_err -> "harness::Hint::ExpectErr"
  | H_both -> "harness::Hint::Both"

let hint_wire (h : hint) : string =
  match h with
  | H_none -> "none"
  | H_expect -> "expect"
  | H_expect_err -> "expect_err"
  | H_both -> "both"

let rec any_meth (p : meth -> bool) (e : expr) : bool =
  let here =
    match e with
    | E_method (_, m, _) -> p m
    | E_lit _ | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_some _
    | E_none _ | E_ok _ | E_err _ | E_call _ | E_field _ | E_index _
    | E_let _ | E_block _ | E_block_unit _ | E_if _ | E_if_else _
    | E_loop _ | E_while _ | E_break | E_continue | E_return_unit
    | E_return _ | E_closure _ | E_async_closure _ | E_await _ -> false
  in
  here || Shrink.exists (any_meth p) (Shrink.children e)

let is_expect (m : meth) : bool =
  match m with
  | M_expect -> true
  | M_then | M_then_some | M_len | M_is_empty | M_trim | M_trim_start
  | M_trim_end | M_starts_with | M_ends_with | M_contains | M_to_owned
  | M_is_some | M_is_none | M_is_ok | M_is_err | M_ok | M_err
  | M_unwrap_err | M_expect_err | M_unwrap | M_get | M_set | M_toggle
  | M_increment | M_decrement | M_push_str | M_clone -> false

let is_expect_err (m : meth) : bool =
  match m with
  | M_expect_err -> true
  | M_then | M_then_some | M_len | M_is_empty | M_trim | M_trim_start
  | M_trim_end | M_starts_with | M_ends_with | M_contains | M_to_owned
  | M_is_some | M_is_none | M_is_ok | M_is_err | M_ok | M_err
  | M_unwrap_err | M_expect | M_unwrap | M_get | M_set | M_toggle
  | M_increment | M_decrement | M_push_str | M_clone -> false

let hint_of (e : expr) : hint =
  let ex = any_meth is_expect e in
  let er = any_meth is_expect_err e in
  match () with
  | () when ex && er -> H_both
  | () when ex -> H_expect
  | () when er -> H_expect_err
  | () -> H_none

(* A body may panic when it can unwrap, expect, unwrap_err, expect_err
   or write a signal.  Signal writes panic server-side at this pin (all
   five writers reach write_in_browser_only,
   crates/topcoat-runtime/src/surrogate/signal.rs:50-108), so
   every Signal_writing sample panics at its first write.  f64
   arithmetic never panics and the m20 scope has no indexing. *)
let is_panicky (m : meth) : bool =
  match m with
  | M_unwrap | M_expect | M_unwrap_err | M_expect_err -> true
  | M_then | M_then_some | M_len | M_is_empty | M_trim | M_trim_start
  | M_trim_end | M_starts_with | M_ends_with | M_contains | M_to_owned
  | M_is_some | M_is_none | M_is_ok | M_is_err | M_ok | M_err | M_get
  | M_set | M_toggle | M_increment | M_decrement | M_push_str | M_clone ->
      Taxonomy.is_write m

let may_panic (e : expr) : bool = any_meth is_panicky e

(* ---------- Rust types, inits and renderability ---------- *)

let rec rust_ty (t : ty) : string option =
  match t with
  | T_f64 -> Some "f64"
  | T_bool -> Some "bool"
  | T_string -> Some "String"
  | T_unit -> Some "()"
  | T_option a -> Option.map (fun s -> "Option<" ^ s ^ ">") (rust_ty a)
  | T_result (a, b) ->
      Option.fold ~none:None
        ~some:(fun sa ->
          Option.map (fun sb -> "Result<" ^ sa ^ ", " ^ sb ^ ">") (rust_ty b))
        (rust_ty a)
  | T_tuple _ | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> None

(* NodeViewParts membership, probed: yes for f64, bool, String and
   Option of a renderable, NO for () (topcoat-view node.rs:233 starts
   impl_tuple! at T1) and Result (no impl).  A target outside the set
   goes through observed_plain and reports an empty rendered_hex. *)
let rec renderable (t : ty) : bool =
  match t with
  | T_f64 | T_bool | T_string -> true
  | T_option a -> renderable a
  | T_unit | T_result _ | T_tuple _ | T_fn _ | T_async_fn _ | T_future _
  | T_signal _ -> false

(* The Observe set of driver-rs/harness.rs. *)
let rec observable (t : ty) : bool =
  match t with
  | T_f64 | T_bool | T_string | T_unit -> true
  | T_option a -> observable a
  | T_result (a, b) -> observable a && observable b
  | T_tuple _ | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> false

let hex8 (n : int) : string = Printf.sprintf "%08x" n

(* Inits are rendered here, not through Printer_rust: outside expr!
   there are no surrogates, a string literal has to become
   String::from(..) (Sample docs, m21 review), and an f64 must survive
   bit for bit, which only from_bits does. *)
let rec init_rust (t : ty) (e : expr) : string option =
  match e with
  | E_lit l -> lit_rust t l
  | E_some e1 -> (
      match t with
      | T_option a -> Option.map (fun s -> "Some(" ^ s ^ ")") (init_rust a e1)
      | T_f64 | T_bool | T_string | T_unit | T_result _ | T_tuple _ | T_fn _
      | T_async_fn _ | T_future _ | T_signal _ -> None)
  | E_none _ -> (
      match t with
      | T_option _ -> Some "None"
      | T_f64 | T_bool | T_string | T_unit | T_result _ | T_tuple _ | T_fn _
      | T_async_fn _ | T_future _ | T_signal _ -> None)
  | E_ok (e1, _) -> (
      match t with
      | T_result (a, _) -> Option.map (fun s -> "Ok(" ^ s ^ ")") (init_rust a e1)
      | T_f64 | T_bool | T_string | T_unit | T_option _ | T_tuple _ | T_fn _
      | T_async_fn _ | T_future _ | T_signal _ -> None)
  | E_err (e1, _) -> (
      match t with
      | T_result (_, b) -> Option.map (fun s -> "Err(" ^ s ^ ")") (init_rust b e1)
      | T_f64 | T_bool | T_string | T_unit | T_option _ | T_tuple _ | T_fn _
      | T_async_fn _ | T_future _ | T_signal _ -> None)
  | E_var _ | E_unary _ | E_binary _ | E_tuple _ | E_call _ | E_method _
  | E_field _ | E_index _ | E_let _ | E_block _ | E_block_unit _ | E_if _
  | E_if_else _ | E_loop _ | E_while _ | E_break | E_continue
  | E_return_unit | E_return _ | E_closure _ | E_async_closure _ | E_await _ ->
      None

and lit_rust (t : ty) (l : lit) : string option =
  match l with
  | L_f64_bits (hi, lo) -> (
      match t with
      | T_f64 -> Some ("f64::from_bits(0x" ^ hex8 hi ^ hex8 lo ^ "u64)")
      | T_bool | T_string | T_unit | T_option _ | T_result _ | T_tuple _
      | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> None)
  | L_bool b -> (
      match t with
      | T_bool -> Some (match b with true -> "true" | false -> "false")
      | T_f64 | T_string | T_unit | T_option _ | T_result _ | T_tuple _
      | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> None)
  | L_str s -> (
      match t with
      | T_string -> Some ("String::from(" ^ Strops.debug s ^ ")")
      | T_f64 | T_bool | T_unit | T_option _ | T_result _ | T_tuple _
      | T_fn _ | T_async_fn _ | T_future _ | T_signal _ -> None)

(* ---------- one case function ---------- *)

(* A binding whose Rust type and init both rendered. *)
type rb = {
  rid : int;
  rty : string;
  rinit : string;
}

let resolve (b : Sample.binding) : (rb, drop_reason) result =
  Result.bind
    (req Dr_rust_ty (rust_ty b.Sample.ty))
    (fun t ->
      Result.map
        (fun i -> { rid = b.Sample.id; rty = t; rinit = i })
        (req Dr_init_rust (init_rust b.Sample.ty b.Sample.init)))

let vname (id : int) : string = "v" ^ nat_to_string id
let iname (id : int) : string = "v" ^ nat_to_string id ^ "_init"
let case_name (i : int) : string = "case_" ^ Emit.pad4 i
let ind (n : int) (s : string) : string = String.make n ' ' ^ s

let mirror_line (b : rb) : string =
  "let " ^ iname b.rid ^ ": " ^ b.rty ^ " = " ^ b.rinit ^ ";"

let signals_line (sigs : rb list) : string =
  match sigs with
  | [] -> "let signals: Vec<harness::SigInit> = Vec::new();"
  | _ :: _ ->
      "let signals: Vec<harness::SigInit> = vec!["
      ^ joined ", "
          (map
             (fun b ->
               "harness::sig(" ^ nat_to_string b.rid ^ ", &" ^ iname b.rid ^ ")")
             sigs)
      ^ "];"

let sig_debug_line (sigs : rb list) : string =
  match sigs with
  | [] -> "let sig_debug: Vec<String> = Vec::new();"
  | _ :: _ ->
      "let sig_debug: Vec<String> = vec!["
      ^ joined ", "
          (map (fun b -> "harness::debug_of(&" ^ vname b.rid ^ ")") sigs)
      ^ "];"

(* The externals of ONE expr! site, re-derived from the mirrors.  The
   Signal handle is minted here and not outside, because Signal has no
   Clone and the macro consumes it. *)
let site_head (ins : rb list) (sigs : rb list) : string list =
  append
    [ "let cx = Cx::default();" ]
    (append
       (map
          (fun b ->
            "let " ^ vname b.rid ^ ": " ^ b.rty ^ " = " ^ iname b.rid
            ^ ".clone();")
          ins)
       (append
          (map
             (fun b ->
               "let " ^ vname b.rid ^ " = Signal::new(" ^ iname b.rid
               ^ ".clone());")
             sigs)
          [ sig_debug_line sigs ]))

let value_tail (body : string) (rend : bool) : string list =
  [
    "let (evaluated, js) = expr!(" ^ body ^ ").into_evaluated_and_js();";
    "let js_bytes = js.render(&cx).into_bytes();";
    (match rend with
    | true -> "let observed = harness::observed_rendered(&cx, evaluated);"
    | false -> "let observed = harness::observed_plain(evaluated);");
    "harness::Triple { value: observed.0, rendered: observed.1, js: \
     js_bytes, sig_debug }";
  ]

(* The closure site (build brief R6).  The move is mandatory: a bare
   expr!(|| BODY) is three E0597 borrows of the surrogate temporaries
   (probe log 139, 150, 161).  Surrogate::into_real is skipped for a
   closure top level (grammar expr.rs:60-62), so the Rust half is an
   uncalled closure and the JS is captured even when the value site
   panics. *)
let closure_tail (body : string) : string list =
  [
    "let (_evaluated, js) = expr!(move || " ^ body
    ^ ").into_evaluated_and_js();";
    "harness::JsSite { js: js.render(&cx).into_bytes(), sig_debug }";
  ]

let block ~(head : string) ~(lines : string list) ~(tail : string) :
    string list =
  append [ head ] (append (map (ind 8) lines) [ tail ])

let case_lines (i : int) (s : Sample.t) : (string list, drop_reason) result =
  let used = keep (fun (b : Sample.binding) -> Shrink.mentions b.Sample.id s.Sample.body) s.Sample.inputs in
  Result.bind
    (match observable s.Sample.target with
    | true -> Ok ()
    | false -> Error Dr_target)
    (fun () ->
      Result.bind (seq_result (map resolve used)) (fun ins ->
          Result.map
            (fun sigs ->
              let body = Printer_rust.print Ops.printer_renderer s.Sample.body in
              let h = hint_ctor (hint_of s.Sample.body) in
              let site = site_head ins sigs in
              let value_site =
                block
                  ~head:("let inner = harness::catch_value(" ^ h ^ ", || {")
                  ~lines:(append site (value_tail body (renderable s.Sample.target)))
                  ~tail:"});"
              in
              let closure_site =
                match may_panic s.Sample.body with
                | true ->
                    append
                      (block ~head:"let js_closure = harness::catch_js(|| {"
                         ~lines:(append site (closure_tail body))
                         ~tail:"});")
                      [ "harness::assemble(inner, js_closure, signals, " ^ h ^ ")" ]
                | false ->
                    [ "harness::assemble(inner, None, signals, " ^ h ^ ")" ]
              in
              let inner_lines =
                append
                  (map mirror_line (append ins sigs))
                  (append [ signals_line sigs ]
                     (append value_site closure_site))
              in
              append
                [ "fn " ^ case_name i ^ "() -> harness::Observed {" ]
                (append (map (ind 4) inner_lines) [ "}" ]))
            (seq_result (map resolve s.Sample.signals))))

(* case_fn i s: the case function text, or None when the sample was
   dropped.  The reason is kept by build below. *)
let case_fn (i : int) (s : Sample.t) : string option =
  Result.fold ~ok:(fun ls -> Some (concat (map (fun l -> l ^ "\n") ls)))
    ~error:(fun (_ : drop_reason) -> None)
    (case_lines i s)

(* ---------- the crate ---------- *)

let header =
  [
    "#![allow(dead_code, unused_variables)]";
    "";
    "mod harness;";
    "";
    "use topcoat_core::context::Cx;";
    "use topcoat_runtime::Signal;";
    "use topcoat_runtime_macro::expr;";
  ]

type built = {
  lines : string list;
  spans : (int * int * int) list; (* case index, 1-based first and last line *)
  hints : hint list;
  kept : int;
  drops : drop_reason list;
}

let empty_built = { lines = header; spans = []; hints = []; kept = 0; drops = [] }

let add_case (a : built) (s : Sample.t) : built =
  Result.fold
    ~ok:(fun blk ->
      {
        lines = append a.lines ("" :: blk);
        spans = (a.kept, len a.lines + 2, len a.lines + 1 + len blk) :: a.spans;
        hints = hint_of s.Sample.body :: a.hints;
        kept = a.kept + 1;
        drops = a.drops;
      })
    ~error:(fun r -> { a with drops = r :: a.drops })
    (case_lines a.kept s)

let cases_const (hints : hint list) : string list =
  let rows =
    rev
      (fst
         (fold
            (fun acc h ->
              ( ind 4
                  ("harness::Case { run: " ^ case_name (snd acc) ^ ", hint: "
                 ^ hint_ctor h ^ " },")
                :: fst acc,
                snd acc + 1 ))
            ([], 0) hints))
  in
  append
    [ ""; "const CASES: [harness::Case; " ^ nat_to_string (len hints) ^ "] = [" ]
    (append rows
       [
         "];";
         "";
         "fn main() {";
         ind 4 "std::process::exit(harness::run(&CASES));";
         "}";
       ])

let build (samples : Sample.t list) : built =
  let b = fold add_case empty_built samples in
  { b with lines = append b.lines (cases_const (rev b.hints)) }

let main_rs (samples : Sample.t list) : string =
  concat (map (fun l -> l ^ "\n") (build samples).lines)

let cargo_toml (name : string) (dep_prefix : string) : string =
  concat
    (map
       (fun l -> l ^ "\n")
       [
         "[package]";
         "name = \"" ^ name ^ "\"";
         "version = \"0.0.0\"";
         "edition = \"2024\"";
         "publish = false";
         "";
         "[dependencies]";
         "topcoat-runtime = { path = \"" ^ dep_prefix
         ^ "topcoat/crates/topcoat-runtime\" }";
         "topcoat-runtime-macro = { path = \"" ^ dep_prefix
         ^ "topcoat/crates/topcoat-runtime/macro\" }";
         "topcoat-view = { path = \"" ^ dep_prefix
         ^ "topcoat/crates/topcoat-view\" }";
         "topcoat-core = { path = \"" ^ dep_prefix
         ^ "topcoat/crates/topcoat-core\" }";
         "";
         "[workspace]";
       ])

let span_text (b : built) : string =
  concat
    (map
       (fun sp ->
         let i = match sp with i, _, _ -> i in
         let a = match sp with _, a, _ -> a in
         let z = match sp with _, _, z -> z in
         nat_to_string i ^ " " ^ nat_to_string a ^ " " ^ nat_to_string z ^ "\n")
       (rev b.spans))

(* Line 1 is "<kept> <dropped>", then one "<reason> <n>" line per drop
   reason that fired.  A reader that wants the totals takes line 1 and
   ignores the rest. *)
let count_text (b : built) : string =
  let dropped = len b.drops in
  let per =
    keep
      (fun p -> snd p > 0)
      (map
         (fun r ->
           ( drop_reason_name r,
             fold
               (fun acc d -> match () with () when drop_reason_eq d r -> acc + 1 | () -> acc)
               0 b.drops ))
         all_drop_reasons)
  in
  concat
    (map
       (fun l -> l ^ "\n")
       (append
          [ nat_to_string b.kept ^ " " ^ nat_to_string dropped ]
          (map (fun p -> fst p ^ " " ^ nat_to_string (snd p)) per)))

(* Files of a driver crate: (relative path, content).  src/harness.rs
   is NOT here: the gate copies driver-rs/harness.rs into place. *)
let crate_files ~(name : string) ~(dep_prefix : string)
    (samples : Sample.t list) : (string * string) list =
  let b = build samples in
  [
    ("Cargo.toml", cargo_toml name dep_prefix);
    ("src/main.rs", concat (map (fun l -> l ^ "\n") b.lines));
    ("cases.span", span_text b);
    ("count", count_text b);
  ]

(* ---------- the seed vector ---------- *)

let fb (x : float) : lit =
  let p = Floatops.of_float x in
  L_f64_bits (fst p, snd p)

let binding (id : int) (t : ty) (init : expr) : Sample.binding =
  { Sample.id = id; ty = t; init }

let sample mode inputs signals target body : Sample.t =
  { Sample.mode; inputs; signals; target; body }

let clone_of (v : int) : expr = E_method (E_var v, M_clone, [])

(* Twelve hand-picked cases, one per channel the M24 parser has to
   read: a bare f64, a String with HTML-significant bytes, the empty
   String, Some and None, a panic with a prefix (unwrap), a signal
   read, a signal write (the whole Signal_writing mode at this pin), a
   panic with NO prefix (expect_err, the hint path), a bare expect
   message (the Expect hint, which no prefix can reach), a body that
   mentions BOTH expect and expect_err (the Both hint, class other),
   and a body that never terminates.

   The last case must stay last:  it spins, the harness exits 3 the
   moment its timeout fires, and every line after it would be lost. *)
let seed_cases : Sample.t list =
  [
    sample Taxonomy.Read_only
      [ binding 0 T_f64 (E_lit (fb 1.5)) ]
      [] T_f64 (E_var 0);
    sample Taxonomy.Read_only
      [ binding 2 T_string (E_lit (L_str "a<b>+c")) ]
      [] T_string (clone_of 2);
    sample Taxonomy.Read_only
      [ binding 2 T_string (E_lit (L_str "")) ]
      [] T_string (clone_of 2);
    sample Taxonomy.Read_only
      [ binding 8 (T_option T_f64) (E_some (E_lit (fb 1.5))) ]
      [] (T_option T_f64) (clone_of 8);
    sample Taxonomy.Read_only
      [ binding 8 (T_option T_f64) (E_none T_f64) ]
      [] (T_option T_f64) (clone_of 8);
    sample Taxonomy.Read_only
      [ binding 8 (T_option T_f64) (E_none T_f64) ]
      [] T_f64
      (E_method (clone_of 8, M_unwrap, []));
    sample Taxonomy.Read_only []
      [ binding 3 T_f64 (E_lit (fb 2.5)) ]
      T_f64
      (E_method (E_var 3, M_get, []));
    sample Taxonomy.Signal_writing []
      [ binding 4 T_bool (E_lit (L_bool true)) ]
      T_unit
      (E_method (E_var 4, M_toggle, []));
    sample Taxonomy.Read_only
      [
        binding 7
          (T_result (T_string, T_f64))
          (E_ok (E_lit (L_str "ok"), T_f64));
      ]
      [] T_f64
      (E_method (clone_of 7, M_expect_err, [ E_lit (L_str "nope") ]));
    (* std gives Option::expect(m) the message m and nothing else, so
       the panic text carries no prefix at all and only the static hint
       can name the class (build brief R2).  Case 8 pins ExpectErr
       through a message that at least has a colon;  this one pins
       Expect through a message that has nothing. *)
    sample Taxonomy.Read_only
      [ binding 8 (T_option T_f64) (E_none T_f64) ]
      [] T_f64
      (E_method (clone_of 8, M_expect, [ E_lit (L_str "boom") ]));
    (* A body that mentions BOTH expect and expect_err.  It panics at
       the left operand, and the message would be the user string
       whichever site raised it, so the hint is Both and the class is
       other:  the one line the gate accepts as other, which the M26
       adapter later refines from the reference leg. *)
    sample Taxonomy.Read_only
      [
        binding 7
          (T_result (T_string, T_f64))
          (E_ok (E_lit (L_str "ok"), T_f64));
        binding 8 (T_option T_f64) (E_some (E_lit (fb 2.5)));
      ]
      [] T_f64
      (E_binary
         ( B_add,
           E_method (clone_of 7, M_expect_err, [ E_lit (L_str "nope") ]),
           E_method (clone_of 8, M_expect, [ E_lit (L_str "boom") ]) ));
    sample Taxonomy.Read_only
      [ binding 1 T_bool (E_lit (L_bool true)) ]
      [] T_unit
      (E_while (E_var 1, E_block_unit []));
  ]
