(* M20 driver-crate writer (DESIGN.md M20): batch printed exprs into
   one rustc-checkable crate.

   Pure: every builder maps its inputs to (relative path, file
   content) pairs, byte-deterministically, so emitting twice yields
   identical crates; bin/emit_m20.ml does the file IO. Rust
   flow-keyword text enters only through Printer_rust.print at run
   time, never as a source literal here.

   Each case is its own fn with fresh let bindings: round 1 proved
   every expr! takes each non-Copy external by value, so two
   invocations must never share a binding. *)

open Prelude
open Ast

type body =
  | B_expr of expr (* printed through the real renderer *)
  | B_raw of string list
    (* verbatim body lines, for probes the printer cannot produce *)

type case = {
  cname : string;
  note : string list; (* comment lines; "// " is added here *)
  body : body;
}

(* Binding text per m20 genv variable id. std Option/Result annotations
   are fine OUTSIDE the macro; the typed lets pin the elided sides. *)
let binding_line id =
  match id with
  | 0 -> Some "let v0: f64 = 1.5;"
  | 1 -> Some "let v1: bool = true;"
  | 2 -> Some "let v2: String = String::new();"
  | 3 -> Some "let v3 = Signal::new(0.0f64);"
  | 4 -> Some "let v4 = Signal::new(true);"
  | 5 -> Some "let v5 = Signal::new(String::new());"
  | 6 -> Some "let v6: Result<f64, String> = Ok(1.5);"
  | 7 -> Some "let v7: Result<String, f64> = Err(1.5);"
  | 8 -> Some "let v8: Option<f64> = None;"
  | 9 -> Some "let v9: Option<String> = None;"
  | _ -> None

let genv_ids = [ 0; 1; 2; 3; 4; 5; 6; 7; 8; 9 ]

(* Free-var bindings for a printed expr, via the conservative
   Shrink.mentions walk. Let-bound ids start at 10 in the m20 genv, so
   they never collide with these. *)
let bindings_for e =
  rev
    (fold
       (fun acc id ->
         match () with
         | () when Shrink.mentions id e ->
             Option.fold ~none:acc ~some:(fun l -> l :: acc)
               (binding_line id)
         | () -> acc)
       [] genv_ids)

let body_lines b =
  match b with
  | B_expr e ->
      append (bindings_for e)
        [ "let _ = expr!(" ^ Printer_rust.print Ops.printer_renderer e ^ ");" ]
  | B_raw lines -> lines

let case_lines c =
  append
    (map (fun n -> "// " ^ n) c.note)
    (append
       [ "fn " ^ c.cname ^ "() {" ]
       (append (map (fun l -> "    " ^ l) (body_lines c.body)) [ "}" ]))

let header =
  [
    "#![allow(dead_code, unused_variables)]";
    "";
    "use topcoat_runtime::Signal;";
    "use topcoat_runtime_macro::expr;";
  ]

(* lib.rs text plus each case's 1-based line span (comment lines
   included; every span starts after a blank separator line). *)
let lib_rs cases =
  let folded =
    fold
      (fun acc c ->
        let lines = fst acc in
        let block = case_lines c in
        let start = len lines + 2 in
        let stop = len lines + 1 + len block in
        (append lines ("" :: block), (c.cname, (start, stop)) :: snd acc))
      (header, []) cases
  in
  (concat (map (fun l -> l ^ "\n") (fst folded)), rev (snd folded))

let cargo_toml name dep_prefix =
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
         "";
         "[workspace]";
       ])

(* Files of a driver crate: (relative path, content). When a case
   named case_neg is present, a sidecar records its 1-based line span
   in src/lib.rs as "start end" so the gate can check that every
   rustc error lands inside it. *)
let crate_files ~name ~dep_prefix cases =
  let lr = lib_rs cases in
  let sidecar =
    Option.fold ~none:[]
      ~some:(fun span ->
        [
          ( "case_neg.span",
            nat_to_string (fst span) ^ " " ^ nat_to_string (snd span) ^ "\n"
          );
        ])
      (assoc_opt String.equal "case_neg" (snd lr))
  in
  append
    [ ("Cargo.toml", cargo_toml name dep_prefix); ("src/lib.rs", fst lr) ]
    sidecar

let pad4 n =
  let s = nat_to_string n in
  let p = 4 - String.length s in
  if p <= 0 then s else String.make p '0' ^ s

(* The 1k batch: one fn per sample, then the case_neg negative
   control, a verified macro-level reject (integer literals are
   unsupported), as raw text because the AST has no int literal. *)
let batch_cases samples =
  let numbered =
    rev
      (fst
         (fold
            (fun acc s ->
              ( {
                  cname = "case_" ^ pad4 (snd acc);
                  note = [];
                  body = B_expr (snd s);
                }
                :: fst acc,
                snd acc + 1 ))
            ([], 0) samples))
  in
  append numbered
    [
      {
        cname = "case_neg";
        note =
          [ "negative control: macro-level reject (unsupported literal type)" ];
        body = B_raw [ "let _ = expr!(1 + 2);" ];
      };
    ]
