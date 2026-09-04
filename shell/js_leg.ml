(* M26 js leg (DESIGN.md M26, spec section 5).  The node driver runs
   over the SAME rust capture the M24 gate wrote, and every line it
   writes decodes through Wire_js.

   Nothing here edits shell/rust_leg.ml.  The Unix primitives of
   shell/rust_leg.ml:154-216 are reused through thin adapters that
   rename the Rust leg's error into this module's error.  The one
   primitive that is NOT reused is spawn_once (:335):  it hands the
   JSONL path to the child as stdout, and the node driver writes that
   path itself through --out, so reuse would put two writers on one
   file.  spawn_node below opens ONE file, seed.js.err, and passes that
   single descriptor for both stdout and stderr. *)

open Prelude

type config = {
  node : string;
  driver_dir : string;
  clone : string;
  timeout_ms : int;
  startup_timeout_ms : int;
}

(* The shape mirrors Rust_leg.default_config ~root
   (shell/rust_leg.ml:80-89):  one labelled root, every path derived
   from it, every budget a named field.  The four defaults are the
   driver's own (README:108-110, m25_gate.sh:84-90). *)
let default_config ~(root : string) : config =
  {
    node = "node";
    driver_dir = root ^ "/driver-js";
    clone = root ^ "/../topcoat";
    timeout_ms = 2000;
    startup_timeout_ms = 30000;
  }

type error =
  | Er_mkdir of string * string (* path, the Unix error text *)
  | Er_read of string * string
  | Er_write of string * string
  | Er_spawn of string * string
  | Er_wait of string
  | Er_signalled of int
  | Er_stopped of int
  | Er_io (* the driver exited 1 *)
  | Er_usage (* the driver exited 2 *)
  | Er_exit of int (* any code outside 0, 1 and 2 *)
  | Er_binary_missing of string
  | Er_decode of int * Wire_js.wjerror (* 1-based line number *)
  | Er_count of int * int (* rust line count, decoded js line count *)

(* One line per error, naming the constructor and its payload, so the
   CLI and the gate print the same words.  Rust_leg.error_text
   (shell/rust_leg.ml:108-115) has the same shape. *)
let error_text (e : error) : string =
  match e with
  | Er_mkdir (path, m) -> "mkdir failed at " ^ path ^ ": " ^ m
  | Er_read (path, m) -> "read failed at " ^ path ^ ": " ^ m
  | Er_write (path, m) -> "write failed at " ^ path ^ ": " ^ m
  | Er_spawn (prog, m) -> "spawn failed for " ^ prog ^ ": " ^ m
  | Er_wait m -> "waitpid failed: " ^ m
  | Er_signalled n -> "the driver was killed by signal " ^ nat_to_string n
  | Er_stopped n -> "the driver was stopped by signal " ^ nat_to_string n
  | Er_io -> "the driver exited 1, which is io: a read or a write failed"
  | Er_usage -> "the driver exited 2, which is usage: a bad flag"
  | Er_exit n -> "the driver exited " ^ nat_to_string n
  | Er_binary_missing path -> "the node binary is missing at " ^ path
  | Er_decode (n, e1) ->
      "js line " ^ nat_to_string n ^ " does not decode: "
      ^ Wire_js.wjerror_name e1
  | Er_count (rust_n, js_n) ->
      "the rust capture has " ^ nat_to_string rust_n
      ^ " lines and the js run decoded " ^ nat_to_string js_n

type report = {
  j_lines : Wire_js.jline list;
  j_exit : int;
  j_counts : (string * int) list; (* outcome kind, count, fixed order *)
}

(* ---------- the argv (spec 5.2) ---------- *)

(* Fifteen elements.  The first eleven are byte for byte the m25 gate
   command, in its order.  The last four are the two optional flags at
   their default values, spelled out rather than defaulted, so the gate
   log records the budget that actually ran.  The list is handed to
   Unix.create_process as both the program and the argument array:  no
   shell, no Sys.command, and no command line is ever concatenated. *)
let argv (cfg : config) ~(rust : string) ~(out : string) : string list =
  [
    cfg.node;
    "--experimental-transform-types";
    "--import";
    cfg.driver_dir ^ "/loader.mjs";
    cfg.driver_dir ^ "/driver.mjs";
    "--in";
    rust;
    "--out";
    out;
    "--clone";
    cfg.clone;
    "--timeout-ms";
    nat_to_string cfg.timeout_ms;
    "--startup-timeout-ms";
    nat_to_string cfg.startup_timeout_ms;
  ]

(* ---------- the adapters over shell/rust_leg.ml ---------- *)

(* The two error types differ only in their constructors, so one total
   translator carries a Rust leg error into this one.  The Unix calls
   themselves are never copied.  Er_budget has no js counterpart:  the
   node driver never exits 3 and never resumes (README:110-114), so the
   arm cannot arise through the adapters below, and it carries its
   number into Er_exit rather than invent a text. *)
let of_rust (e : Rust_leg.error) : error =
  match e with
  | Rust_leg.Er_mkdir (path, m) -> Er_mkdir (path, m)
  | Rust_leg.Er_read (path, m) -> Er_read (path, m)
  | Rust_leg.Er_write (path, m) -> Er_write (path, m)
  | Rust_leg.Er_spawn (prog, m) -> Er_spawn (prog, m)
  | Rust_leg.Er_wait m -> Er_wait m
  | Rust_leg.Er_signalled n -> Er_signalled n
  | Rust_leg.Er_stopped n -> Er_stopped n
  | Rust_leg.Er_usage -> Er_usage
  | Rust_leg.Er_exit n -> Er_exit n
  | Rust_leg.Er_binary_missing path -> Er_binary_missing path
  | Rust_leg.Er_budget n -> Er_exit n
  | Rust_leg.Er_decode (n, w) -> Er_decode (n, Wire_js.Wj_wire w)
  | Rust_leg.Er_count (a, b) -> Er_count (a, b)

let mkdir_one (path : string) : (unit, error) result =
  Result.map_error of_rust (Rust_leg.mkdir_one path)

let open_write (path : string) : (Unix.file_descr, error) result =
  Result.map_error of_rust (Rust_leg.open_write path false)

let close_write (path : string) (fd : Unix.file_descr) : (unit, error) result =
  Result.map_error of_rust (Rust_leg.close_write path fd)

let create_res (prog : string) (args : string array) (out_fd : Unix.file_descr)
    (err_fd : Unix.file_descr) : (int, error) result =
  Result.map_error of_rust (Rust_leg.create_res prog args out_fd err_fd)

let wait_res (pid : int) : (Unix.process_status, error) result =
  Result.map_error of_rust (Rust_leg.wait_res pid)

let status_code (status : Unix.process_status) : (int, error) result =
  Result.map_error of_rust (Rust_leg.status_code status)

let read_file (path : string) : (string, error) result =
  Result.map_error of_rust (Rust_leg.read_file path)

(* prefer, in this module's error type.  The contract is
   Rust_leg.prefer's, shell/rust_leg.ml:207-216:  the inner result wins,
   both arguments are evaluated so the descriptor is closed on every
   path, and the close error is reported only when the inner result is
   Ok.  EVERY caller binds the inner result with a let on the line
   above, because OCaml does not fix the order of the two arguments. *)
let prefer (inner : ('a, error) result) (closed : (unit, error) result) :
    ('a, error) result =
  Result.fold
    ~ok:(fun v -> Result.map (fun () -> v) closed)
    ~error:(fun e -> Error e)
    inner

(* ---------- the spawn (spec 5.4) ---------- *)

(* ONE file for both streams, so the driver's stdout (empty) and its
   stderr (the node warnings plus the one summary line) both land in
   seed.js.err, which is what the verdict reads.  The spawn and the wait
   are bound in ONE continuation, so a child that starts is always
   reaped. *)
let spawn_node (_cfg : config) ~(argv : string list) ~(err : string) :
    (int, error) result =
  match argv with
  | [] -> Error (Er_spawn ("", "the argv is empty"))
  | prog :: _ ->
      Result.bind (open_write err) (fun fd ->
          let waited =
            Result.bind
              (create_res prog (Array.of_list argv) fd fd)
              (fun pid -> Result.bind (wait_res pid) status_code)
          in
          prefer waited (close_write err fd))

(* A spawn failure whose Unix text names a missing file names the node
   binary instead, so the gate says which program is absent. *)
let name_missing (cfg : config) (e : error) : error =
  match e with
  | Er_spawn (_prog, m) -> (
      match () with
      | () when String.equal m (Unix.error_message Unix.ENOENT) ->
          Er_binary_missing cfg.node
      | () -> e)
  | Er_mkdir (_, _) | Er_read (_, _) | Er_write (_, _) | Er_wait _
  | Er_signalled _ | Er_stopped _ | Er_io | Er_usage | Er_exit _
  | Er_binary_missing _ | Er_decode (_, _) | Er_count (_, _) ->
      e

(* 0 continues, 1 is io, 2 is usage, anything else is the code itself.
   A signalled or stopped child never reaches here:  Rust_leg.status_code
   (shell/rust_leg.ml:325-329) reports those two first. *)
let code_error (code : int) : (unit, error) result =
  match () with
  | () when code = 0 -> Ok ()
  | () when code = 1 -> Error Er_io
  | () when code = 2 -> Error Er_usage
  | () -> Error (Er_exit code)

(* ---------- the decode loop and the counts ---------- *)

let rec decode_lines (n : int) (lines : string list) :
    (Wire_js.jline list, error) result =
  match lines with
  | [] -> Ok []
  | line :: rest ->
      Result.bind
        (Result.map_error (fun e -> Er_decode (n, e)) (Wire_js.decode_line line))
        (fun l ->
          Result.map (fun more -> l :: more) (decode_lines (n + 1) rest))

(* The kind name of one line.  The three Jl_obs kinds come from the
   Obs.outcome inside it;  the other four are the other four
   constructors, so the tabulation is total over the sum type and the
   compiler catches a new constructor. *)
let kind_of (l : Wire_js.jline) : string =
  match l.Wire_js.jl_body with
  | Wire_js.Jl_obs (o, _x) -> (
      match o.Obs.outcome with
      | Obs.O_value _ -> "value"
      | Obs.O_panic (_, _) -> "panic"
      | Obs.O_no_terminate -> "no_terminate")
  | Wire_js.Jl_js_error (_, _) -> "js_error"
  | Wire_js.Jl_skipped _ -> "skipped"
  | Wire_js.Jl_driver_error (_, _) -> "driver_error"
  | Wire_js.Jl_lossy _ -> "lossy"

(* Seven names, always present, zeros included, in this fixed order.  A
   fixed order and a fixed length mean the summary line never changes
   shape between runs, so the verdict asserts it whole.  A function, not
   a constant, for the same reason the wire tables are. *)
let count_kinds () =
  [ "value"; "panic"; "no_terminate"; "js_error"; "skipped"; "driver_error";
    "lossy" ]

let count_one (lines : Wire_js.jline list) (kind : string) : int =
  fold
    (fun n l ->
      match () with
      | () when String.equal (kind_of l) kind -> n + 1
      | () -> n)
    0 lines

let counts (lines : Wire_js.jline list) : (string * int) list =
  map (fun k -> (k, count_one lines k)) (count_kinds ())

let count_of (rep : report) (kind : string) : int =
  Option.fold ~none:0 ~some:(fun n -> n) (assoc_opt String.equal kind rep.j_counts)

let js_obs (rep : report) : int =
  count_of rep "value" + count_of rep "panic" + count_of rep "no_terminate"

(* ---------- the runner (spec 5.3) ---------- *)

let run (cfg : config) ~(rust : string) ~(dir : string) :
    (report, error) result =
  Result.bind (mkdir_one dir) (fun () ->
      let out = dir ^ "/seed.js.jsonl" in
      let err = dir ^ "/seed.js.err" in
      Result.bind
        (Result.map_error (name_missing cfg)
           (spawn_node cfg ~argv:(argv cfg ~rust ~out) ~err))
        (fun code ->
          Result.bind (code_error code) (fun () ->
              Result.bind (read_file out) (fun text ->
                  Result.map
                    (fun lines ->
                      { j_lines = lines; j_exit = code; j_counts = counts lines })
                    (decode_lines 1 (Rust_leg.split_lines text))))))

(* ---------- the row cells (spec 5.5) ---------- *)

(* This module owns the text of the J cell, so the unit tests and the
   gate share ONE oracle, exactly as Rust_leg.row (shell/rust_leg.ml:568)
   owns the M24 row.  The js_error cell length-prefixes both texts,
   because either can carry a colon and the cell must stay
   self-delimiting the way Obs.encode_outcome is.  The driver_error cell
   carries the error word only:  the detail bytes are arbitrary and go
   on the report, not in a table that is compared byte for byte. *)
let cell (l : Wire_js.jline) : string =
  match l.Wire_js.jl_body with
  | Wire_js.Jl_obs (o, _x) -> Obs.encode o
  | Wire_js.Jl_skipped r -> "skipped:" ^ r
  | Wire_js.Jl_js_error (n, m) ->
      "js_error:" ^ nat_to_string (String.length n) ^ ":" ^ n ^ ":"
      ^ nat_to_string (String.length m) ^ ":" ^ m
  | Wire_js.Jl_driver_error (e, _d) -> "driver_error:" ^ e
  | Wire_js.Jl_lossy k -> "lossy:" ^ k

(* The one stderr line the verdict asserts whole (spec 6.2).  The format
   lives here, beside the cell printer, so the unit tests and the gate
   share it.  The caller adds the line feed. *)
let summary (rep : report) ~(cases : int) ~(rust : int) ~(reference : int)
    ~(hint_mismatch : int) : string =
  "m26: cases " ^ nat_to_string cases ^ " rust " ^ nat_to_string rust ^ " js "
  ^ nat_to_string (len rep.j_lines)
  ^ " ref " ^ nat_to_string reference ^ " js_obs "
  ^ nat_to_string (js_obs rep)
  ^ " skipped "
  ^ nat_to_string (count_of rep "skipped")
  ^ " js_error "
  ^ nat_to_string (count_of rep "js_error")
  ^ " driver_error "
  ^ nat_to_string (count_of rep "driver_error")
  ^ " lossy "
  ^ nat_to_string (count_of rep "lossy")
  ^ " hint_mismatch " ^ nat_to_string hint_mismatch
