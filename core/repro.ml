(** Repro renders the text of an M30 [repro.md].  It is pure: the whole input
    arrives as strings, ints and string lists, and the answer is one string.
    No channel, clock or host lookup appears here.  Paths arrive from the
    caller, and the same input renders the same bytes. *)

(** Where the start sample came from.  [Origin_case] carries the PLANT NAME of
    the M29 case, which is the only case identity the tree ships (ruling R6
    and section 0.8);  [Origin_seed] carries an M31 generator seed. *)
type origin =
  | Origin_case of string  (** the plant name of an M29 case *)
  | Origin_seed of int  (** a seed handed to the generator *)

(** Every field the renderer needs.  [rp_walk] is the walk stdout verbatim,
    newline terminated, and [rp_dir] is the directory AS GIVEN on argv, which
    the gate passes root relative after its [cd "$ROOT"] (ruling Q4).  The
    renderer neither checks nor rewrites it. *)
type input = {
  rp_plant : string;  (** [Plant.name] of the plant, "none" when there is none *)
  rp_origin : origin;
  rp_clone_sha : string;  (** 40 lowercase hex, the topcoat clone *)
  rp_oracle_sha : string;  (** 40 lowercase hex, this repository *)
  rp_fuel : int;
  rp_start_size : int;
  rp_final_size : int;
  rp_bindings : string list;  (** one Rust [let] line per binding, inputs first *)
  rp_body : string;  (** the body expression, printed, no trailing newline *)
  rp_js_src : string;  (** [Wire.decoded.d_js] of the witness rust line *)
  rp_js_form : string;  (** [Wire.js_form_wire] of its [d_js_form] *)
  rp_rust : string;  (** the R cell of the witness run *)
  rp_js : string;  (** the J cell *)
  rp_ref : string;  (** the F cell *)
  rp_verdict : string;  (** the V cell, mode name then verdict text *)
  rp_walk : string;  (** the M29 walk text, verbatim *)
  rp_root : string;  (** effective oracle root, relative to the invocation cwd *)
  rp_clone : string;  (** effective clone path, relative to the invocation cwd *)
  rp_dir : string;  (** e.g. [_emit/m30/out/ref:display_sign] *)
}

(** The one name [Plant.name] answers when nothing is planted. *)
let no_plant_name () = "none"

(** The sixteen lowercase hex digits.  A unit function, not a constant, so
    zxlint trap 2 cannot fire on it from another module. *)
let hex_digits () = "0123456789abcdef"

(** [is_hex_byte b] answers whether the ONE BYTE STRING [b] is one lowercase
    hex digit.  The table is walked with [Prelude.byte_at], which answers a
    one byte string option, so there is no [String.sub], no [String.get] and
    no index arithmetic here.  Ruling R7 asks for exactly that. *)
let is_hex_byte b =
  let rec go k =
    Option.fold ~none:false
      ~some:(fun d -> String.equal d b || go (k + 1))
      (Prelude.byte_at (hex_digits ()) k)
  in
  go 0

(** [hex_run s k n] answers whether the [n] bytes of [s] from index [k] are
    all lowercase hex digits.  [Prelude.byte_at] answers [None] past the end,
    which ends the walk with [false] and needs no length test of its own. *)
let rec hex_run s k n =
  Int.equal n 0
  || Option.fold ~none:false
       ~some:(fun b -> is_hex_byte b && hex_run s (k + 1) (n - 1))
       (Prelude.byte_at s k)

(** [is_sha40 s] answers whether [s] is exactly 40 lowercase hex digits. *)
let is_sha40 s = Int.equal (String.length s) 40 && hex_run s 0 40

(** [sha_of_line l] answers the sha carried by one line of
    [git rev-parse HEAD] output, or the offending text.  The trailing newline
    and any surrounding blanks are trimmed first.  No dirty marker is
    accepted: the shape is the forty digits and nothing else. *)
let sha_of_line l =
  let s = String.trim l in
  if is_sha40 s then Ok s
  else Error ("the sha line is not 40 lowercase hex digits: " ^ s)

(** [line s] answers [s] with exactly one newline after it. *)
let line s = s ^ "\n"

(** [block ls] answers the lines of [ls], each newline terminated. *)
let block ls = Prelude.concat (Prelude.map line ls)

(** [origin_text o] names the origin in one field. *)
let origin_text o =
  match o with
  | Origin_case c -> "case " ^ c
  | Origin_seed n -> "seed " ^ string_of_int n

(** Quote one POSIX shell argument.  Apostrophes close the quoted span,
    emit an escaped apostrophe, then reopen it.  Byte traversal keeps this
    renderer in the core subset and preserves paths verbatim. *)
let shell_arg s =
  let rec go k =
    Option.fold ~none:"'"
      ~some:(fun b ->
        (if String.equal b "'" then "'\\''" else b) ^ go (k + 1))
      (Prelude.byte_at s k)
  in
  "'" ^ go 0

(** [selector i] is the flag that names the START SAMPLE of a reproduce
    command: the plant for an M29 case, the M31 [--seed] flag for a generated
    one.  M30 never PARSES [--seed];  the flag is a forward reference to M31
    (ruling R6), and the pure test of section 10 is the only place it is
    exercised. *)
let selector i =
  match i.rp_origin with
  | Origin_case _ -> "--plant " ^ shell_arg i.rp_plant
  | Origin_seed n -> "--seed " ^ string_of_int n

(** [fuel_flag i] is the EFFECTIVE fuel of the run.  It is printed on both
    reproduce commands ALWAYS, so a reader never has to know which default the
    shipped [Minimize.default_config] carries (decision sheet Q8). *)
let fuel_flag i = "--fuel " ^ string_of_int i.rp_fuel

(** [witness_dir i] is the root relative crate directory of the witness run.
    [Legs.witness_dir] builds the same path in the shell (ruling R8), and the
    renderer spells it here so the provenance block needs no extra field. *)
let witness_dir i = i.rp_dir ^ "/rp"

(** [walk_dir i] is the root relative M29 output directory of the same plant,
    which is the directory the second reproduce command names (Q8). *)
let walk_dir i = "_emit/m29/out/" ^ i.rp_plant

(** The planted sentence, in FIXED words.  Ruling R5(b) puts it in the
    provenance block, so a reader meets it before the program and cannot
    mistake this file for a bug report against the clone. *)
let planted i =
  if String.equal i.rp_plant (no_plant_name ()) then
    "No plant is injected in this run: the difference below is a difference \
     between the legs themselves."
  else
    "The divergence below is PLANTED.  The " ^ i.rp_plant
    ^ " plant is injected on purpose, so this file proves the harness sees \
       the difference;  it is not a bug report against the clone and it must \
       not be filed."

(** Block (a): the title.  It names the verdict and the plant (R5(a)).  The
    verdict text arrives inside [rp_verdict], the V cell, which is the mode
    name, one space, and the verdict text. *)
let title i = block [ "# m30 repro: " ^ i.rp_verdict ^ " in " ^ i.rp_plant; "" ]

(** Block (b): provenance.  The two shas, the plant, the origin, the fuel and
    the witness crate directory, then the planted sentence (R5(b)). *)
let provenance i =
  block
    [
      "## provenance";
      "";
      "- topcoat: " ^ i.rp_clone_sha;
      "- topcoat-oracle: " ^ i.rp_oracle_sha;
      "- plant: " ^ i.rp_plant;
      "- origin: " ^ origin_text i.rp_origin;
      "- fuel: " ^ string_of_int i.rp_fuel;
      "- witness: " ^ witness_dir i;
      "";
      planted i;
      "";
    ]

(** Block (c): the minimized program as Rust, bindings first and body last.
    [rp_bindings] holds one [let] line per binding, inputs then signals. *)
let program i =
  block [ "## program"; ""; "```rust" ]
  ^ block i.rp_bindings
  ^ block [ i.rp_body; "```"; "" ]

(** Block (d): the emitted JS of the witness rust line, verbatim, with its
    wire form (ruling R5(d)).  This is the datum DESIGN.md:328-330 names the
    milestone for, so it has a block of its own and not a footnote. *)
let emitted i =
  block [ "## emitted js"; ""; "- form: " ^ i.rp_js_form; ""; "```js" ]
  ^ block [ i.rp_js_src ]
  ^ block [ "```"; "" ]

(** Block (e): the two sizes the walk moved between. *)
let sizes i =
  block
    [
      "## size";
      "";
      "- start: " ^ string_of_int i.rp_start_size;
      "- final: " ^ string_of_int i.rp_final_size;
      "";
    ]

(** Block (f): the four cells of the witness run, in the M27 row order. *)
let witness i =
  block
    [
      "## witness";
      "";
      "- rust: " ^ i.rp_rust;
      "- js: " ^ i.rp_js;
      "- ref: " ^ i.rp_ref;
      "- verdict: " ^ i.rp_verdict;
      "";
    ]

(** Block (g): the walk text, fenced and verbatim.  [rp_walk] already ends in
    a newline, so no line is added or dropped here. *)
let trace i = block [ "## trace"; ""; "```" ] ^ i.rp_walk ^ block [ "```"; "" ]

(** Preserve the effective paths even when they differ from CLI defaults.
    Replay commands are run from the same working directory as the original. *)
let path_flags i =
  " --root " ^ shell_arg i.rp_root ^ " --clone " ^ shell_arg i.rp_clone

(** [m30_command i] is the command that regenerates THIS file. *)
let m30_command i =
  "dune exec bin/m30.exe -- repro " ^ shell_arg i.rp_dir ^ " " ^ selector i ^ " "
  ^ fuel_flag i ^ path_flags i

(** [m29_command i] is the command that repeats the WALK alone, in the M29
    output directory of the same plant. *)
let m29_command i =
  "dune exec bin/m29.exe -- minimize " ^ shell_arg (walk_dir i) ^ " " ^ selector i ^ " "
  ^ fuel_flag i ^ path_flags i

(** Block (h): how to reproduce.  EXACTLY two fenced commands, the m30 one
    first and the m29 one second (decision sheet Q8).  No gate script is
    named: a gate also runs the other plant, the m29 ladder and the masks,
    which is not what a reader of ONE repro needs. *)
let reproduce i =
  block
    [
      "## reproduce";
      "";
      "```sh";
      m30_command i;
      "```";
      "";
      "```sh";
      m29_command i;
      "```";
      "";
    ]

(** Block (i): what to look for.  It takes no input: the planted sentence
    moved to the provenance block (R5(b)), so nothing here varies.  It is
    last, so its final line is the last line of the file. *)
let look () =
  block
    [
      "## what to look for";
      "";
      "The four cells above are the one witness run.  The verdict line names \
       the difference.";
      "The program block is the smallest sample the walk reached that still \
       shows it.";
    ]

(** [render i] answers the whole [repro.md] text.  NINE blocks, in this
    order, and the file ends in exactly one newline. *)
let render i =
  Prelude.concat
    [
      title i;
      provenance i;
      program i;
      emitted i;
      sizes i;
      witness i;
      trace i;
      reproduce i;
      look ();
    ]
