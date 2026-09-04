(* M24 rust leg (DESIGN.md M24, spec section 4).  The effectful half of
   the milestone.  It writes the driver crate, runs it with the pinned
   toolchain, resumes it past a case that spins, reads the JSONL back,
   and pairs every decoded line with the sample that produced it.

   core/ owns the pure half.  Json.parse reads the bytes and
   Wire.decode_line turns one line into an Obs.observation plus the
   wire extras.  Nothing here re-decides either of them.  Everything
   here is IO: mkdir, the file writes, the harness copy, the process
   spawn, waitpid, the resume loop, the file read and the line split.

   Every raising call is wrapped ONCE, at its Unix boundary, and names
   the constructor it catches.  A function whose body needs two raising
   calls is split into two functions.  There is no other try in the
   file and no "with _" anywhere.  File IO goes through Unix.openfile,
   Unix.read and Unix.write_substring rather than the stdlib channels,
   so one error type (Unix_error) covers every boundary and no
   Sys_error path is left implicit.

   The harness is COPIED at run time, never embedded, so the file rustc
   compiles is the file in the repo, byte for byte.  This module
   creates and overwrites;  it never deletes.  The gate clears its own
   directories.

   Cap, bound and drop inventory (spec section 10).  Every site of this
   milestone, with its kind and its reason:
   - JSON nesting depth, 64.  CAP, real, owned by core/json.ml.  A wire
     line reaches depth 4, so the cap is sixteen times the need and
     still bounds a hostile input.  Passing it is E_depth with the byte
     offset, never a stack overflow.
   - integer digit run, 18.  CAP, real, owned by core/json.ml.  18
     digits is at most 999999999999999999, below 2^62, so acc * 10 + d
     cannot overflow the 63-bit int.  A 19th digit is
     E_too_many_digits, never a silent wrap.
   - hi and lo, 0 to 4294967295.  BOUND, owned by core/wire.ml.  One
     32-bit half each, as harness::Value::F64 writes them.  4294967296
     is W_range.
   - hex payload, an even length and the bytes 0-9 a-f.  BOUND, owned
     by core/wire.ml.  An odd length is W_odd_hex and an uppercase
     digit is W_bad_hex.  Neither is repaired.
   - resume budget, 20.  CAP, real, owned here.  The same number
     m23_gate.sh uses.  Spending it is Er_budget, a named error, never
     a silent stop.
   - per-case timeout, 2000 ms.  CAP, real, passed straight through to
     the harness, which owns it (DESIGN M23).
   - cargo jobs, 2.  BOUND.  The OOM-safe build discipline for this
     machine.  Not a correctness cap.
   - seed table size, 12.  BOUND.  The expected table is hand-derived
     in spec section 7;  growing it means recomputing that section by
     hand.
   - dropped samples, an unbounded count.  DROP.  Driver.add_case owns
     the three reasons.  This module counts them per reason on the
     report and never re-decides one.
   - the js byte count column, masked in the verdict.  STRUCTURAL.
     js_hex carries a fresh Signal uuid per run, so neither its bytes
     nor its length is stable.  Verdict check 5 pins non-zero instead.
   - exit 4, surfaced and never swallowed.  INVARIANT.  The range
     finished.  Every case index with js_consistent false is listed on
     the report and counted in the summary line.
   - the "; return " slicing of the direct JS body.  NOT FIXED, a known
     limitation carried from research/m23-driver-probe.md.  A
     quote-aware scan is out of M24 scope, and the failure mode stays a
     loud exit 4 with js_consistent false. *)

open Prelude

type config = {
  toolchain : string;
  jobs : int;
  target_dir : string;
  timeout_ms : int;
  resume_budget : int;
  harness_src : string;
  dep_prefix : string;
}

(* The out-dir sits two levels below the root, as _emit/m24seed does,
   which is why the dep prefix is the same "../../../" that
   bin/emit_m23.ml passes for _emit/m23seed. *)
let default_config ~(root : string) : config =
  {
    toolchain = "nightly-2026-06-22";
    jobs = 2;
    target_dir = root ^ "/research/probes-rs/exprmac/target";
    timeout_ms = 2000;
    resume_budget = 20;
    harness_src = root ^ "/driver-rs/harness.rs";
    dep_prefix = "../../../";
  }

type error =
  | Er_mkdir of string * string (* path, the Unix error text *)
  | Er_write of string * string
  | Er_read of string * string
  | Er_spawn of string * string
  | Er_wait of string
  | Er_signalled of int
  | Er_stopped of int
  | Er_usage (* the child exited 2 *)
  | Er_exit of int (* any code outside 0, 2, 3 and 4 *)
  | Er_binary_missing of string
  | Er_budget of int (* the resumes are spent, budget n *)
  | Er_decode of int * Wire.werror (* 1-based line number *)
  | Er_count of int * int (* kept, decoded line count *)

(* One line per error, naming the constructor and its payload, so the
   CLI and the gate print the same words. *)
let error_text (e : error) : string =
  match e with
  | Er_mkdir (path, m) -> "mkdir failed at " ^ path ^ ": " ^ m
  | Er_write (path, m) -> "write failed at " ^ path ^ ": " ^ m
  | Er_read (path, m) -> "read failed at " ^ path ^ ": " ^ m
  | Er_spawn (prog, m) -> "spawn failed for " ^ prog ^ ": " ^ m
  | Er_wait m -> "waitpid failed: " ^ m
  | Er_signalled n -> "the child was killed by signal " ^ nat_to_string n
  | Er_stopped n -> "the child was stopped by signal " ^ nat_to_string n
  | Er_usage -> "the child exited 2, which is usage: a missing index"
  | Er_exit n -> "the child exited " ^ nat_to_string n
  | Er_binary_missing path -> "the built binary is missing at " ^ path
  | Er_budget n ->
      "the resume budget of " ^ nat_to_string n
      ^ " is spent and the child still exits 3"
  | Er_decode (n, w) ->
      "line " ^ nat_to_string n ^ " does not decode: " ^ Wire.werror_name w
  | Er_count (kept, lines) ->
      "the run kept " ^ nat_to_string kept ^ " samples and wrote "
      ^ nat_to_string lines ^ " lines"

type report = {
  p_lines : Wire.decoded list;
  p_kept : int;
  p_dropped : (string * int) list; (* drop reason name, count *)
  p_resumes : int;
  p_exits : int list; (* every waitpid code, in order *)
  p_exit : int; (* the last one *)
  p_inconsistent : int list; (* case indices with js_consistent false *)
}

(* ---------- total list helpers, so no loop keyword appears ---------- *)

let keep (p : 'a -> bool) (xs : 'a list) : 'a list =
  rev
    (fold (fun acc x -> match () with () when p x -> x :: acc | () -> acc) [] xs)

let rec zip (xs : 'a list) (ys : 'b list) : ('a * 'b) list =
  match xs with
  | [] -> []
  | x :: xs' -> ( match ys with [] -> [] | y :: ys' -> (x, y) :: zip xs' ys')

(* ---------- the Unix boundary, one raising call per try ---------- *)

(* One level, an existing directory is not an error, the parent must
   exist.  The name says "one" because nothing here walks a path. *)
let mkdir_one (path : string) : (unit, error) result =
  try Ok (Unix.mkdir path 0o755) with
  | Unix.Unix_error (e, _, _) -> (
      match () with
      | () when e = Unix.EEXIST -> Ok ()
      | () -> Error (Er_mkdir (path, Unix.error_message e)))

let open_read (path : string) : (Unix.file_descr, error) result =
  try Ok (Unix.openfile path [ Unix.O_RDONLY ] 0o644) with
  | Unix.Unix_error (e, _, _) -> Error (Er_read (path, Unix.error_message e))

(* O_TRUNC on the first run and O_APPEND on a resume, mode 0o644. *)
let open_write (path : string) (append : bool) :
    (Unix.file_descr, error) result =
  let flags =
    match () with
    | () when append -> [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND ]
    | () -> [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ]
  in
  try Ok (Unix.openfile path flags 0o644) with
  | Unix.Unix_error (e, _, _) -> Error (Er_write (path, Unix.error_message e))

let close_read (path : string) (fd : Unix.file_descr) : (unit, error) result =
  try Ok (Unix.close fd) with
  | Unix.Unix_error (e, _, _) -> Error (Er_read (path, Unix.error_message e))

let close_write (path : string) (fd : Unix.file_descr) : (unit, error) result =
  try Ok (Unix.close fd) with
  | Unix.Unix_error (e, _, _) -> Error (Er_write (path, Unix.error_message e))

let size_res (path : string) (fd : Unix.file_descr) : (int, error) result =
  try Ok (Unix.fstat fd).Unix.st_size with
  | Unix.Unix_error (e, _, _) -> Error (Er_read (path, Unix.error_message e))

let read_res (path : string) (fd : Unix.file_descr) (buf : bytes) (off : int)
    (n : int) : (int, error) result =
  try Ok (Unix.read fd buf off n) with
  | Unix.Unix_error (e, _, _) -> Error (Er_read (path, Unix.error_message e))

let write_res (path : string) (fd : Unix.file_descr) (s : string) (off : int)
    (n : int) : (int, error) result =
  try Ok (Unix.write_substring fd s off n) with
  | Unix.Unix_error (e, _, _) -> Error (Er_write (path, Unix.error_message e))

let create_res (prog : string) (args : string array) (out_fd : Unix.file_descr)
    (err_fd : Unix.file_descr) : (int, error) result =
  try Ok (Unix.create_process prog args Unix.stdin out_fd err_fd) with
  | Unix.Unix_error (e, _, _) -> Error (Er_spawn (prog, Unix.error_message e))

let wait_res (pid : int) : (Unix.process_status, error) result =
  try Ok (snd (Unix.waitpid [] pid)) with
  | Unix.Unix_error (e, _, _) -> Error (Er_wait (Unix.error_message e))

(* The inner result wins.  Both arguments are evaluated, so the
   descriptor is closed on every path, but the close error is reported
   only when the inner result is Ok.  Without this the close would mask
   the read or the write error that names what actually went wrong.

   EVERY caller binds the inner result with a `let` on the line above.
   OCaml does not fix the order of the two arguments, so an inline
   inner expression can run AFTER the close and read a closed
   descriptor.  The `let` is what orders the work before the close. *)
let prefer (inner : ('a, error) result) (closed : (unit, error) result) :
    ('a, error) result =
  Result.fold
    ~ok:(fun v -> Result.map (fun () -> v) closed)
    ~error:(fun e -> Error e)
    inner

(* ---------- whole-file read and write, bounded by the size ---------- *)

let rec read_go (path : string) (fd : Unix.file_descr) (buf : bytes)
    (off : int) (n : int) : (int, error) result =
  match () with
  | () when off >= n -> Ok off
  | () ->
      Result.bind (read_res path fd buf off (n - off)) (fun k ->
          match () with
          | () when k <= 0 -> Ok off
          | () -> read_go path fd buf (off + k) n)

(* A short read is an error, never a truncated string handed on as if
   it were the file.  The read error wins when the close also fails, so
   "the file ended early" is never masked by the close. *)
let read_file (path : string) : (string, error) result =
  Result.bind (open_read path) (fun fd ->
      let text =
        Result.bind (size_res path fd) (fun n ->
            match () with
            | () when n < 0 || n > Sys.max_string_length ->
                Error (Er_read (path, "the file is too large to read"))
            | () ->
                let buf = Bytes.create n in
                Result.bind (read_go path fd buf 0 n) (fun got ->
                    match () with
                    | () when got = n -> Ok (Bytes.to_string buf)
                    | () -> Error (Er_read (path, "the file ended early"))))
      in
      prefer text (close_read path fd))

let rec write_go (path : string) (fd : Unix.file_descr) (s : string)
    (off : int) (n : int) : (unit, error) result =
  match () with
  | () when off >= n -> Ok ()
  | () ->
      Result.bind (write_res path fd s off (n - off)) (fun k ->
          match () with
          | () when k <= 0 ->
              Error (Er_write (path, "the write made no progress"))
          | () -> write_go path fd s (off + k) n)

(* The descriptor is closed on the write error too, and the write error
   is the one reported when both fire. *)
let write_file (path : string) (text : string) : (unit, error) result =
  Result.bind (open_write path false) (fun fd ->
      let wrote = write_go path fd text 0 (String.length text) in
      prefer wrote (close_write path fd))

(* ---------- the crate writer (spec 4.2) ---------- *)

let rec write_pairs (dir : string) (pairs : (string * string) list) :
    (unit, error) result =
  match pairs with
  | [] -> Ok ()
  | p :: rest ->
      Result.bind
        (write_file (dir ^ "/" ^ fst p) (snd p))
        (fun () -> write_pairs dir rest)

let write_crate (cfg : config) ~(name : string) ~(dir : string)
    (samples : Sample.t list) : (unit, error) result =
  Result.bind (mkdir_one dir) (fun () ->
      Result.bind
        (mkdir_one (dir ^ "/src"))
        (fun () ->
          Result.bind (read_file cfg.harness_src) (fun harness ->
              Result.bind
                (write_pairs dir
                   (Driver.crate_files ~name ~dep_prefix:cfg.dep_prefix samples))
                (fun () -> write_file (dir ^ "/src/harness.rs") harness))))

(* ---------- the cargo argv (spec 4.3), pure and unit-tested ---------- *)

(* Byte identical to the drawn-batch argv of m23_gate.sh with the
   manifest and the target dir substituted.  The list is handed to
   Unix.create_process as both the program and the argument array:  no
   shell, no Sys.command, and no command line is ever concatenated. *)
let cargo_argv (cfg : config) ~(manifest : string) ~(from : int option) :
    string list =
  append
    [
      "cargo";
      "+" ^ cfg.toolchain;
      "run";
      "--quiet";
      "--manifest-path";
      manifest;
      "--target-dir";
      cfg.target_dir;
      "-j";
      nat_to_string cfg.jobs;
      "--";
      "--timeout-ms";
      nat_to_string cfg.timeout_ms;
    ]
    (Option.fold ~none:[] ~some:(fun k -> [ "--from"; nat_to_string k ]) from)

(* ---------- the runner (spec 4.4) ---------- *)

(* The three process outcomes, in one place, so the spawn reads as one
   chain and the exit code is the only Ok. *)
let status_code (status : Unix.process_status) : (int, error) result =
  match status with
  | Unix.WEXITED code -> Ok code
  | Unix.WSIGNALED n -> Error (Er_signalled n)
  | Unix.WSTOPPED n -> Error (Er_stopped n)

(* The spawn and the wait are bound in ONE continuation, so a child that
   starts is always reaped, and each open is closed through `prefer`, so
   both descriptors are closed on every path.  A close error surfaces
   only when the run itself succeeded. *)
let spawn_once (_cfg : config) ~(argv : string list) ~(jsonl : string)
    ~(err : string) ~(append : bool) : (int, error) result =
  match argv with
  | [] -> Error (Er_spawn ("", "the argv is empty"))
  | prog :: _ ->
      Result.bind (open_write jsonl append) (fun out_fd ->
          let ran =
            Result.bind (open_write err append) (fun err_fd ->
                let waited =
                  Result.bind
                    (create_res prog (Array.of_list argv) out_fd err_fd)
                    (fun pid -> Result.bind (wait_res pid) status_code)
                in
                prefer waited (close_write err err_fd))
          in
          prefer ran (close_write jsonl out_fd))

(* ---------- the JSONL text, split without a loop keyword ---------- *)

let byte_or_empty (s : string) (i : int) : string =
  Option.fold ~none:"" ~some:(fun b -> b) (byte_at s i)

let rec split_go (s : string) (i : int) (n : int) (cur : string)
    (acc : string list) : string list =
  match () with
  | () when i >= n ->
      rev (match () with () when String.equal cur "" -> acc | () -> cur :: acc)
  | () when String.equal (byte_or_empty s i) "\n" ->
      split_go s (i + 1) n "" (cur :: acc)
  | () -> split_go s (i + 1) n (cur ^ byte_or_empty s i) acc

(* Split on line feed and drop a trailing empty piece.  A pure fold over
   Prelude.byte_at, so it is testable without a file. *)
let split_lines (text : string) : string list =
  split_go text 0 (String.length text) "" []

(* The 1-based line number rides with the line, so a malformed tail
   names the line it sits on and not the line count.  Trailing blank
   lines do not move the number. *)
let last_non_empty (lines : string list) : (int * string) option =
  snd
    (fold
       (fun acc l ->
         let n = fst acc + 1 in
         match () with
         | () when String.equal l "" -> (n, snd acc)
         | () -> (n, Some (n, l)))
       (0, None) lines)

(* The ONLY route to a resume index.  m23_gate.sh read the last case
   with a regex;  here the decoder reads it, so a malformed tail is a
   named error and never a silent zero. *)
let resume_index (text : string) : (int, error) result =
  let lines = split_lines text in
  let last =
    Option.fold ~none:(0, "") ~some:(fun p -> p) (last_non_empty lines)
  in
  Result.map_error
    (fun w -> Er_decode (fst last, w))
    (Wire.next_from (snd last))

(* ---------- the resume loop (spec 4.5) ---------- *)

(* Bounded recursion with an explicit counter.  No busy wait, no sleep
   and no while.  The resume runs the BUILT BINARY, not cargo, for the
   reason m23_gate.sh gives: one cargo invocation per spinning case is
   the waste this avoids. *)
let rec resume_loop (cfg : config) ~(name : string) ~(jsonl : string)
    ~(err : string) ~(code : int) ~(resumes : int) ~(acc : int list) :
    (int list * int, error) result =
  match () with
  | () when code <> 3 -> Ok (rev acc, resumes)
  | () when resumes >= cfg.resume_budget -> Error (Er_budget cfg.resume_budget)
  | () -> (
      let bin = cfg.target_dir ^ "/debug/" ^ name in
      match () with
      | () when not (Sys.file_exists bin) -> Error (Er_binary_missing bin)
      | () ->
          Result.bind (read_file jsonl) (fun text ->
              Result.bind (resume_index text) (fun next ->
                  Result.bind
                    (spawn_once cfg
                       ~argv:
                         [
                           bin;
                           "--timeout-ms";
                           nat_to_string cfg.timeout_ms;
                           "--from";
                           nat_to_string next;
                         ]
                       ~jsonl ~err ~append:true)
                    (fun c ->
                      resume_loop cfg ~name ~jsonl ~err ~code:c
                        ~resumes:(resumes + 1) ~acc:(c :: acc)))))

(* The exit-code map of spec 4.4, applied at the caller.  Code 3 never
   reaches here: the loop above either resumes past it or spends the
   budget.  Code 4 means the range FINISHED with at least one line that
   lost its direct JS body, so it is kept and reported, never
   swallowed. *)
let check_code (code : int) : (int, error) result =
  match () with
  | () when code = 0 -> Ok code
  | () when code = 4 -> Ok code
  | () when code = 2 -> Error Er_usage
  | () -> Error (Er_exit code)

(* ---------- the kept-sample recovery (spec 4.6) ---------- *)

(* Driver.add_case owns the drop decision.  This fold only OBSERVES it:
   a sample is kept when built.kept went up.  No logic is copied out of
   shell/driver.ml. *)
let kept_samples (samples : Sample.t list) : Sample.t list =
  rev
    (snd
       (fold
          (fun acc s ->
            let before = fst acc in
            let after = Driver.add_case before s in
            match () with
            | () when after.Driver.kept > before.Driver.kept ->
                (after, s :: snd acc)
            | () -> (after, snd acc))
          (Driver.empty_built, []) samples))

let drop_counts (b : Driver.built) : (string * int) list =
  keep
    (fun p -> snd p > 0)
    (map
       (fun r ->
         ( Driver.drop_reason_name r,
           fold
             (fun n d ->
               match () with
               | () when Driver.drop_reason_eq d r -> n + 1
               | () -> n)
             0 b.Driver.drops ))
       Driver.all_drop_reasons)

(* ---------- the decode pass ---------- *)

let rec decode_all (lines : string list) (n : int) (acc : Wire.decoded list) :
    (Wire.decoded list, error) result =
  match lines with
  | [] -> Ok (rev acc)
  | l :: rest ->
      Result.bind
        (Result.map_error (fun w -> Er_decode (n, w)) (Wire.decode_line l))
        (fun d -> decode_all rest (n + 1) (d :: acc))

let inconsistent (lines : Wire.decoded list) : int list =
  rev
    (fold
       (fun acc d ->
         match () with
         | () when d.Wire.d_js_consistent -> acc
         | () -> d.Wire.d_case :: acc)
       [] lines)

let last_code (codes : int list) : int = fold (fun _ c -> c) 0 codes

(* ---------- end to end (spec 4.6) ---------- *)

let run (cfg : config) ~(name : string) ~(dir : string)
    (samples : Sample.t list) : (report, error) result =
  let jsonl = dir ^ "/run.jsonl" in
  let err = dir ^ "/run.err" in
  Result.bind (write_crate cfg ~name ~dir samples) (fun () ->
      Result.bind
        (spawn_once cfg
           ~argv:(cargo_argv cfg ~manifest:(dir ^ "/Cargo.toml") ~from:None)
           ~jsonl ~err ~append:false)
        (fun first ->
          Result.bind
            (resume_loop cfg ~name ~jsonl ~err ~code:first ~resumes:0
               ~acc:[ first ])
            (fun loop ->
              let codes = fst loop in
              Result.bind
                (check_code (last_code codes))
                (fun final ->
                  Result.bind (read_file jsonl) (fun text ->
                      Result.map
                        (fun lines ->
                          let built = Driver.build samples in
                          {
                            p_lines = lines;
                            p_kept = built.Driver.kept;
                            p_dropped = drop_counts built;
                            p_resumes = snd loop;
                            p_exits = codes;
                            p_exit = final;
                            p_inconsistent = inconsistent lines;
                          })
                        (decode_all (split_lines text) 1 []))))))

(* A drop shifts the DRAW index and never the kept index, which is why
   the zip is by position. *)
let pair (samples : Sample.t list) (rep : report) :
    ((Sample.t * Wire.decoded) list, error) result =
  let ks = kept_samples samples in
  match () with
  | () when len ks <> len rep.p_lines ->
      Error (Er_count (len ks, len rep.p_lines))
  | () -> Ok (zip ks rep.p_lines)

(* ---------- renderability (spec 4.7) ---------- *)

type rendered_state = Rs_absent | Rs_empty | Rs_text of string

(* An empty rendered_hex is ambiguous on the wire between "the target
   type has no NodeViewParts impl" and "None renders as the empty
   string".  research/m23-driver-probe.md resolves it statically from
   Sample.target, and that is what happens here: in the shell, where
   the sample is in hand, never in core/ and never by changing
   Obs.observation. *)
let rendered_of (s : Sample.t) (d : Wire.decoded) : rendered_state =
  match d.Wire.d_obs.Obs.outcome with
  | Obs.O_panic (_, _) -> Rs_absent
  | Obs.O_no_terminate -> Rs_absent
  | Obs.O_value _ -> (
      match () with
      | () when not (Driver.renderable s.Sample.target) -> Rs_absent
      | () when String.equal d.Wire.d_obs.Obs.rendered "" -> Rs_empty
      | () -> Rs_text d.Wire.d_obs.Obs.rendered)

(* ---------- the printed row (spec 4.8) ---------- *)

(* Six fields with single spaces between them.  The cell can carry
   spaces, because a panic message can, so the verdict reads only $1,
   $2 and $NF and compares the rest byte for byte.  $2 is T on the
   no-terminate row and on no other row, because every other cell
   starts with V or P. *)
let row (d : Wire.decoded) : string =
  let cell =
    match d.Wire.d_obs.Obs.outcome with
    | Obs.O_no_terminate -> "T"
    | Obs.O_value _ | Obs.O_panic (_, _) -> Obs.encode d.Wire.d_obs
  in
  nat_to_string d.Wire.d_case
  ^ " " ^ cell ^ " "
  ^ Wire.js_form_wire d.Wire.d_js_form
  ^ " "
  ^ Wire.hint_wire d.Wire.d_hint
  ^ " "
  ^ (match d.Wire.d_js_consistent with true -> "1" | false -> "0")
  ^ " "
  ^ nat_to_string (String.length d.Wire.d_js)

let summary (rep : report) : string =
  "m24 seeds: kept "
  ^ nat_to_string rep.p_kept
  ^ " lines "
  ^ nat_to_string (len rep.p_lines)
  ^ " resumes "
  ^ nat_to_string rep.p_resumes
  ^ " exits "
  ^ joined "," (map nat_to_string rep.p_exits)
  ^ " inconsistent "
  ^ nat_to_string (len rep.p_inconsistent)

(* The second stderr line of the CLI, printed when at least one case
   lost its direct JS body, so exit 4 is named and never swallowed. *)
let inconsistent_text (rep : report) : string =
  "m24 seeds: js_consistent false on cases "
  ^ joined "," (map nat_to_string rep.p_inconsistent)
