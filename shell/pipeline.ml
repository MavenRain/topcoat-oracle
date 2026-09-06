(* M31 pipeline: draw, run in batches, append the journal, answer the summary.
   This file PRINTS NOTHING.  A stdlib channel call inside shell/ is
   forbidden (shell/walk.ml:9-11), so the per batch progress line goes to a
   [progress] callback the CLI supplies and the summary is ANSWERED as text
   for the CLI to print.  Hazard H4 is closed here and in bin/m31.ml. *)

open Prelude

(** Everything one run needs.  [p_dir] is the run directory, four segments
    below [p_root];  section 16 states that contract. *)
type config = {
  p_dir : string;
  p_samples : int;
  p_seed : int;
  p_batch : int;
  p_plant : Plant.t;
  p_clone : string;
  p_root : string;
}

(** Every way a run fails, each with its own constructor.  No failure is a
    bare string and none is a raised exception. *)
type failure =
  | Pf_mkdir of string
  | Pf_sha of string
  | Pf_read of string
  | Pf_write of string
  | Pf_decode of string
  | Pf_header of string
  | Pf_absent of string
  | Pf_short of string
  | Pf_trace of string
  | Pf_torn of string

(** [failure_text f] is the text bin/m31.ml prints after "m31 failure: ". *)
let failure_text (f : failure) : string =
  match f with
  | Pf_mkdir m -> "the run directory could not be created: " ^ m
  | Pf_sha m -> "the clone sha could not be read: " ^ m
  | Pf_read m -> "the journal could not be read: " ^ m
  | Pf_write m -> "the journal could not be written: " ^ m
  | Pf_decode m -> m
  | Pf_header m -> m
  | Pf_absent p -> "there is no journal at " ^ p
  | Pf_short m -> m
  | Pf_trace m -> "the trace could not be written: " ^ m
  | Pf_torn m -> m

(** [journal_path dir] is the one journal of a run directory. *)
let journal_path (dir : string) : string = dir ^ "/journal.jsonl"

(** [trace_path dir] is the one transition log of a run directory.  It sits
    beside the journal and is a SECOND file: the journal is data, not a log
    (DESIGN.md:369-371), so the log does not enter it. *)
let trace_path (dir : string) : string = dir ^ "/trace.jsonl"

(** [trace_header_of h] is the trace header of a run whose journal header is
    [h].  The four fields are the journal's own, in the journal's own order
    (ruling R4). *)
let trace_header_of (h : Journal.header) : Correspond.trace_header =
  {
    Correspond.th_seed = h.Journal.jh_seed;
    Correspond.th_batch = h.Journal.jh_batch;
    Correspond.th_plant = h.Journal.jh_plant;
    Correspond.th_topcoat = h.Journal.jh_topcoat;
  }

(** One sample of a batch: its journal row and its model walk.  The two are
    built together at row time from the SAME evidence, so a row can never
    reach the journal without its own walk reaching the trace. *)
type entry = { e_row : Journal.line; e_steps : Frame.tname list }

(** [entry_text e] is the one trace line of an entry, newline free. *)
let entry_text (e : entry) : string =
  Correspond.encode_trace_line
    {
      Correspond.tl_i = e.e_row.Journal.jl_i;
      Correspond.tl_steps = map Correspond.step_name e.e_steps;
    }

(** [presence_of c] carries a differ cell's presence to the checker.  This is
    the pipeline's OWN predicate, so [Correspond.cell_presence] reads back
    exactly what was written (ruling R8, check C3). *)
let presence_of (c : Differ.cell) : Correspond.presence =
  match c with
  | Differ.Present _ -> Correspond.Cell_present
  | Differ.Absent _ -> Correspond.Cell_absent

(** [legs_config c] is the shipped M29 configuration with the M31 crate name.
    [l_out] is the RUN directory, so [Legs.batch_dir] puts every batch crate
    ONE level below it, five segments below the root, which is the depth
    shell/legs.ml:60-71 fixes [dep_prefix] for (hazard H2).  The contract is
    documented and never checked: a run directory at another depth makes every
    generated crate fail to resolve its dependencies, which is a batch_fail on
    every sample and a red gate, so the failure is loud and named. *)
let legs_config (c : config) : Legs.config =
  {
    (Legs.default_config ~root:c.p_root ~clone:c.p_clone ~out:c.p_dir c.p_plant) with
    Legs.l_name = "m31batch";
  }

(** [draw n seed] is the n sample draw of the seed, in DRAW ORDER: element 0
    is the FIRST value the generator produced.

    The [rev] is load bearing.  [QCheck.Gen.generate] conses each draw in
    front of the last, so it answers [draw_n; ...; draw_1] and its element 0
    is the LAST draw (QCheck.ml:35-36, :316-319, :533-534).  Without the
    [rev], element i of an N draw would be draw N-i, which MOVES when N moves,
    so the pair (seed, i) would not name a sample, a resume with a larger N
    would rerun different samples, and the gate check "the resumed journal
    equals the straight journal" could not hold.  With the [rev], element i is
    draw i+1 for every N, so the first k elements of an N draw are exactly the
    k draw, which is the property ruling R3 states and section 16 argues. *)
let draw (n : int) (seed : int) : Sample.t list =
  rev
    (QCheck.Gen.generate ~n
       ~rand:(Random.State.make [| seed |])
       (Sample_gen.gen_sample true Weights.m20))

(** [take k xs] is the first [k] elements of [xs], or all of them when there
    are fewer.  It is a fold and not a loop;  the shape is bin/m30.ml's own
    [after]. *)
let take (k : int) (xs : 'a list) : 'a list =
  snd
    (fold
       (fun acc x ->
         match () with
         | () when fst acc < k -> (fst acc + 1, append (snd acc) (x :: []))
         | () -> (fst acc + 1, snd acc))
       (0, []) xs)

(** [drop k xs] is [xs] without its first [k] elements. *)
let drop (k : int) (xs : 'a list) : 'a list =
  snd
    (fold
       (fun acc x ->
         match () with
         | () when fst acc < k -> (fst acc + 1, snd acc)
         | () -> (fst acc + 1, append (snd acc) (x :: [])))
       (0, []) xs)

(** [count p xs] is how many elements satisfy [p]. *)
let count (p : 'a -> bool) (xs : 'a list) : int =
  fold
    (fun n x ->
      match () with
      | () when p x -> n + 1
      | () -> n)
    0 xs

(** [append_text path text] opens [path] for APPEND, writes [text] and closes
    it, once.  [Rust_leg.write_file] cannot be used: it always calls
    [open_write path false], which TRUNCATES (shell/rust_leg.ml:286-289).
    This is that function with the boolean flipped, over the same three
    shipped primitives, so the whole batch is ONE open, ONE write and ONE
    close and no new Unix call site enters the tree (ruling R5). *)
let append_text (path : string) (text : string) : (unit, Rust_leg.error) result
    =
  Result.bind (Rust_leg.open_write path true) (fun fd ->
      let wrote = Rust_leg.write_go path fd text 0 (String.length text) in
      Rust_leg.prefer wrote (Rust_leg.close_write path fd))

(** [journal_lines text] is the lines of a journal file.  One empty tail piece
    is dropped, so a file that ends with a newline and a file that does not
    both read as the same list of records. *)
let journal_lines (text : string) : string list =
  let all = Rust_leg.split_lines text in
  match rev all with
  | [] -> []
  | last :: rest -> (
      match () with
      | () when String.equal last "" -> rev rest
      | () -> all)

(** [read_journal path] reads and decodes the whole journal. *)
let read_journal (path : string) :
    (Journal.header * Journal.line list, failure) result =
  Result.bind
    (Result.map_error
       (fun e -> Pf_read (Rust_leg.error_text e))
       (Rust_leg.read_file path))
    (fun text ->
      Result.map_error
        (fun e ->
          Pf_decode
            ("the journal at " ^ path ^ " is broken: " ^ Journal.error_text e))
        (Journal.decode_journal (journal_lines text)))

(** A position of a batch was kept by the rust crate writer or dropped by it.
    A bool would carry the same information, but a match on a bool is denied
    by the house rules and the two names read better in the walk below. *)
type keep_mark = K_kept | K_dropped

(** [marks samples] is one mark per position, from the SHIPPED
    [Legs.keep_flags] (shell/legs.ml:135-147) and no second opinion. *)
let marks (samples : Sample.t list) : keep_mark list =
  map
    (fun f ->
      match () with
      | () when f -> K_kept
      | () -> K_dropped)
    (Legs.keep_flags samples)

(** [row ~i ~verdict ~r ~j ~f s] is the journal line of ONE sample.  The mode,
    the size, the environment and the body come from the SAMPLE, so they are
    written even for a dropped sample and even for a failed batch: a journal
    line always names its program (ruling R5). *)
let row ~(i : int) ~(verdict : string) ~(r : string) ~(j : string)
    ~(f : string) (s : Sample.t) : Journal.line =
  {
    Journal.jl_i = i;
    Journal.jl_mode = Taxonomy.mode_name s.Sample.mode;
    Journal.jl_size = Minimize.size_of s;
    Journal.jl_verdict = verdict;
    Journal.jl_r = r;
    Journal.jl_j = j;
    Journal.jl_f = f;
    Journal.jl_env = Walk.let_lines s;
    Journal.jl_body = Walk.body_text s;
  }

(** [no_line rcfg i s] is the K4 entry: the crate ran, the position was kept,
    and the rust leg wrote no line for it.  The reference leg still answers,
    so the row carries an f cell (ruling R6) and the walk crashes the two
    product legs and reads the reference off its own cell. *)
let no_line (rcfg : Ref_leg.config) (i : int) (s : Sample.t) : entry =
  let rc = Legs.ref_cell_of rcfg s in
  {
    e_row =
      row ~i ~verdict:"no_line" ~r:"" ~j:"" ~f:(Obs.encode rc.Legs.r_obs) s;
    e_steps =
      Correspond.steps_of
        {
          Correspond.ev_kind = Correspond.Kd_no_line;
          Correspond.ev_rust = Correspond.Cell_absent;
          Correspond.ev_js = Correspond.Cell_absent;
          Correspond.ev_ref = Correspond.Cell_present;
          Correspond.ev_head = "no_line";
        };
  }

(** [rows_ok rcfg i ms samples ps ls] spreads the kept answers back over the
    whole batch, with the shape of Legs.spread (shell/legs.ml:164-175), and
    keeps the three CELLS that walk throws away.  Each position answers its
    journal row AND its model walk, built from the same evidence (ruling R5).
    A dropped position takes "dropped" and consumes NO pair;  a kept position
    with no pair left takes "no_line" and STILL runs the reference leg, whose
    cell it journals in f (ruling R6).  [legs_lines] already refuses a batch
    whose pair count and line count disagree, so the two ragged arms below are
    totality clauses. *)
let rec rows_ok (rcfg : Ref_leg.config) (i : int) (ms : keep_mark list)
    (samples : Sample.t list) (ps : (Sample.t * Wire.decoded) list)
    (ls : Wire_js.jline list) : entry list =
  match (ms, samples) with
  | [], [] -> []
  | [], _ :: _ -> []
  | _ :: _, [] -> []
  | K_dropped :: mrest, s :: srest ->
      {
        e_row = row ~i ~verdict:"dropped" ~r:"" ~j:"" ~f:"" s;
        e_steps =
          Correspond.steps_of
            {
              Correspond.ev_kind = Correspond.Kd_dropped;
              Correspond.ev_rust = Correspond.Cell_absent;
              Correspond.ev_js = Correspond.Cell_absent;
              Correspond.ev_ref = Correspond.Cell_absent;
              Correspond.ev_head = "dropped";
            };
      }
      :: rows_ok rcfg (i + 1) mrest srest ps ls
  | K_kept :: mrest, s :: srest -> (
      match (ps, ls) with
      | p :: prest, l :: lrest ->
          let rc = Legs.ref_cell_of rcfg (fst p) in
          let cs = Legs.cells_of (snd p) l rc.Legs.r_obs in
          let v = Differ.verdict rc.Legs.r_mode (Differ.known_seed ()) cs in
          let vt = Differ.verdict_text v in
          {
            e_row =
              row ~i ~verdict:vt
                ~r:(Obs.encode (snd p).Wire.d_obs)
                ~j:(Js_leg.cell l)
                ~f:(Obs.encode rc.Legs.r_obs)
                s;
            e_steps =
              Correspond.steps_of
                {
                  Correspond.ev_kind = Correspond.Kd_paired;
                  Correspond.ev_rust = presence_of cs.Differ.rust;
                  Correspond.ev_js = presence_of cs.Differ.js;
                  Correspond.ev_ref = presence_of cs.Differ.reference;
                  Correspond.ev_head = Journal.head vt;
                };
          }
          :: rows_ok rcfg (i + 1) mrest srest prest lrest
      | [], [] -> no_line rcfg i s :: rows_ok rcfg (i + 1) mrest srest [] []
      | [], l :: lrest ->
          let _ = l in
          no_line rcfg i s :: rows_ok rcfg (i + 1) mrest srest [] lrest
      | _ :: prest, [] ->
          no_line rcfg i s :: rows_ok rcfg (i + 1) mrest srest prest [])

(** [rows_fail rcfg i be samples] is the batch that lost a leg: every sample
    takes the SAME named reason, the run CONTINUES (ruling R4 of M31), and the
    reason text is [Legs.batch_error_text] unedited, so its own prefix
    ("rust leg: ", "rust pairing: ", "js leg: ") survives into the journal and
    into the summary.  A batch that died BEFORE the crate ran has no reference
    observation and writes three "" cells;  a batch that died AFTER the crate
    ran still runs the reference leg and writes its f cell (ruling R6). *)
let rows_fail (rcfg : Ref_leg.config) (i : int) (be : Legs.batch_error)
    (samples : Sample.t list) : entry list =
  let why = Legs.batch_error_text be in
  let k =
    match Legs.batch_origin be with
    | Legs.Before_crate -> Correspond.Kd_build_lost
    | Legs.After_crate -> Correspond.Kd_leg_lost
  in
  let f_of (s : Sample.t) : string =
    match Legs.batch_origin be with
    | Legs.Before_crate -> ""
    | Legs.After_crate -> Obs.encode (Legs.ref_cell_of rcfg s).Legs.r_obs
  in
  let p_ref =
    match Legs.batch_origin be with
    | Legs.Before_crate -> Correspond.Cell_absent
    | Legs.After_crate -> Correspond.Cell_present
  in
  snd
    (fold
       (fun acc s ->
         ( fst acc + 1,
           append (snd acc)
             ({
                e_row =
                  row ~i:(fst acc)
                    ~verdict:("batch_fail:" ^ why)
                    ~r:"" ~j:"" ~f:(f_of s) s;
                e_steps =
                  Correspond.steps_of
                    {
                      Correspond.ev_kind = k;
                      Correspond.ev_rust = Correspond.Cell_absent;
                      Correspond.ev_js = Correspond.Cell_absent;
                      Correspond.ev_ref = p_ref;
                      Correspond.ev_head = "batch_fail";
                    };
              }
             :: []) ))
       (i, []) samples)

(** [batch_rows lcfg first samples] runs ONE batch of the corpus and answers
    its entries, whether the batch worked or lost a leg. *)
let batch_rows (lcfg : Legs.config) (first : int) (samples : Sample.t list) :
    entry list =
  Result.fold
    ~ok:(fun pl ->
      rows_ok lcfg.Legs.l_ref first (marks samples) samples (fst pl) (snd pl))
    ~error:(fun be -> rows_fail lcfg.Legs.l_ref first be samples)
    (Legs.legs_lines lcfg ~dir:(Legs.batch_dir lcfg first) samples)

(** [progress_text first samples rows] is the ONE line per batch the CLI
    prints on stderr.  "kept" is the number of rows that are NOT dropped;  on
    a failed batch that is the batch size, because a batch_fail row is not a
    dropped row (ruling RES-5).  The count stays as coded and the line is
    never compared by the gate (ruling R7).  "verdicts" is the number of
    samples an adjudication was made for, which is exactly the number of rows
    carrying a rust cell: a dropped, a no_line and a batch_fail row all carry
    "". *)
let progress_text_of (first : int) (samples : Sample.t list)
    (rows : Journal.line list) : string =
  "m31 batch b" ^ nat_to_string first ^ " cases " ^ nat_to_string (len samples)
  ^ " kept "
  ^ nat_to_string
      (count (fun l -> not (String.equal l.Journal.jl_verdict "dropped")) rows)
  ^ " verdicts "
  ^ nat_to_string (count (fun l -> not (String.equal l.Journal.jl_r "")) rows)

(** [progress_text first samples rows] is the M31 line over the entries of a
    batch.  The entry carries the row, so the M31 body reads the rows and its
    text does not change by one byte. *)
let progress_text (first : int) (samples : Sample.t list) (rows : entry list) :
    string =
  progress_text_of first samples (map (fun e -> e.e_row) rows)

(** [run_batches lcfg ~progress ~path ~tpath ~batch first samples] runs the
    samples in batches, in index order, appending each batch to the journal
    and then to the trace before the next batch starts.  The two appends are
    the only writes and they happen once per batch, so a run killed between
    batches leaves both files on a batch boundary.  A run killed BETWEEN the
    two appends leaves a trace one batch short of the journal;  the resume of
    section 4.8 REFUSES that directory and repairs nothing (ruling R12). *)
let rec run_batches (lcfg : Legs.config) ~(progress : string -> unit)
    ~(path : string) ~(tpath : string) ~(batch : int) (first : int)
    (samples : Sample.t list) : (unit, failure) result =
  match samples with
  | [] -> Ok ()
  | _ :: _ ->
      let chunk = take batch samples in
      let rest = drop batch samples in
      let rows = batch_rows lcfg first chunk in
      Result.bind
        (Result.map_error
           (fun e -> Pf_write (Rust_leg.error_text e))
           (append_text path
              (concat
                 (map (fun e -> Journal.encode_line e.e_row ^ "\n") rows))))
        (fun () ->
          Result.bind
            (Result.map_error
               (fun e -> Pf_trace (Rust_leg.error_text e))
               (append_text tpath
                  (concat (map (fun e -> entry_text e ^ "\n") rows))))
            (fun () ->
              progress (progress_text first chunk rows);
              run_batches lcfg ~progress ~path ~tpath ~batch
                (first + len chunk) rest))

(** [want_of c sha] is the header this run asks for. *)
let want_of (c : config) (sha : string) : Journal.header =
  {
    Journal.jh_seed = c.p_seed;
    Journal.jh_batch = c.p_batch;
    Journal.jh_plant = Plant.name c.p_plant;
    Journal.jh_topcoat = sha;
  }

(** [header_text h] names a header in the words the mismatch failure uses. *)
let header_text (h : Journal.header) : string =
  "seed " ^ Cover.hex_str h.Journal.jh_seed ^ " batch "
  ^ nat_to_string h.Journal.jh_batch
  ^ " plant " ^ h.Journal.jh_plant ^ " topcoat " ^ h.Journal.jh_topcoat

(** [mismatch path found want] is the refusal of a resume whose journal was
    written by another run.  The text names BOTH headers in full, so the
    operator sees which field disagreed without opening the file. *)
let mismatch (path : string) (found : Journal.header) (want : Journal.header) :
    failure =
  Pf_header
    ("the journal at " ^ path ^ " was written with " ^ header_text found
   ^ ", this run asked for " ^ header_text want)

(** [clone_sha lcfg c] captures the clone sha with the shipped
    [Provenance.read_sha].  [~out] is the RUN directory, never a batch
    directory, so the capture happens once per run and no batch rewrites it
    (hazard H5). *)
let clone_sha (lcfg : Legs.config) (c : config) : (string, failure) result =
  Result.map_error
    (fun e -> Pf_sha (Provenance.error_text e))
    (Provenance.read_sha lcfg.Legs.l_rust ~out:c.p_dir ~name:"topcoat"
       ~repo:c.p_clone)

(** [read_trace tpath] reads and decodes the whole trace. *)
let read_trace (tpath : string) :
    (Correspond.trace_header * Correspond.trace_line list, failure) result =
  Result.bind
    (Result.map_error
       (fun e -> Pf_read (Rust_leg.error_text e))
       (Rust_leg.read_file tpath))
    (fun text ->
      Result.map_error
        (fun f ->
          Pf_decode
            ("the trace at " ^ tpath ^ " is broken: " ^ Correspond.failure_text f))
        (Correspond.decode_trace (journal_lines text)))

(** [resume_open c lcfg path tpath] decodes an EXISTING journal fully, checks
    its header against the flags, checks that the trace beside it holds the
    same number of sample lines, and answers how many are already there.  The
    three flag fields are compared FIRST, the trace next and the clone sha
    LAST, so a run with the wrong seed refuses before git is spawned and
    before one byte under the run directory is rewritten.  A trace that is
    missing or short is a REFUSAL and never a repair (ruling R12). *)
let resume_open (c : config) (lcfg : Legs.config) (path : string)
    (tpath : string) : (int, failure) result =
  Result.bind (read_journal path) (fun hl ->
      let found = fst hl in
      match () with
      | () when not (Int.equal found.Journal.jh_seed c.p_seed) ->
          Error (mismatch path found (want_of c found.Journal.jh_topcoat))
      | () when not (Int.equal found.Journal.jh_batch c.p_batch) ->
          Error (mismatch path found (want_of c found.Journal.jh_topcoat))
      | () when not (String.equal found.Journal.jh_plant (Plant.name c.p_plant))
        ->
          Error (mismatch path found (want_of c found.Journal.jh_topcoat))
      | () when not (Sys.file_exists tpath) ->
          Error
            (Pf_torn
               ("the journal at " ^ path ^ " holds "
              ^ nat_to_string (len (snd hl))
              ^ " lines and there is no trace at " ^ tpath))
      | () ->
          Result.bind (read_trace tpath) (fun thl ->
              let jk = len (snd hl) in
              let tk = len (snd thl) in
              match () with
              | () when not (Int.equal jk tk) ->
                  Error
                    (Pf_torn
                       ("the journal at " ^ path ^ " holds "
                      ^ nat_to_string jk ^ " lines and the trace at " ^ tpath
                      ^ " holds " ^ nat_to_string tk ^ " lines"))
              | () ->
                  Result.bind (clone_sha lcfg c) (fun sha ->
                      match () with
                      | () when String.equal sha found.Journal.jh_topcoat ->
                          Ok jk
                      | () -> Error (mismatch path found (want_of c sha)))))

(** [fresh_open c lcfg path tpath] captures the sha and writes BOTH headers.
    [Rust_leg.write_file] is right here and only here: neither file exists, so
    its truncation is a creation.  The journal header is written first, so a
    directory that holds a trace and no journal cannot arise. *)
let fresh_open (c : config) (lcfg : Legs.config) (path : string)
    (tpath : string) : (int, failure) result =
  Result.bind (clone_sha lcfg c) (fun sha ->
      let h = want_of c sha in
      Result.bind
        (Result.map_error
           (fun e -> Pf_write (Rust_leg.error_text e))
           (Rust_leg.write_file path (Journal.encode_header h ^ "\n")))
        (fun () ->
          Result.map
            (fun () -> 0)
            (Result.map_error
               (fun e -> Pf_trace (Rust_leg.error_text e))
               (Rust_leg.write_file tpath
                  (Correspond.encode_trace_header (trace_header_of h) ^ "\n")))))

(** [summary path] re-reads the journal FROM DISK and answers its summary.
    The summary is a function of the decoded journal and of nothing else, not
    of the verdicts still in memory, which is why a run and a replay of the
    same directory print the same bytes by construction (ruling R7). *)
let summary (path : string) : (string, failure) result =
  Result.map
    (fun hl ->
      Journal.summary_text
        ~seed_hex:(Cover.hex_str (fst hl).Journal.jh_seed)
        ~path (fst hl) (snd hl))
    (read_journal path)

(** [finish path n] answers the summary when the journal holds at least [n]
    sample lines and a named failure when it holds fewer, so exit 0 means the
    journal is COMPLETE (ruling R2).  A journal longer than the request is
    accepted and printed whole: a smaller --samples on a directory that
    already holds more is a shorter question about a longer answer, not a
    reason to delete anything (ruling R8). *)
let finish (path : string) (n : int) : (string, failure) result =
  Result.bind (read_journal path) (fun hl ->
      let k = len (snd hl) in
      match () with
      | () when k >= n ->
          Ok
            (Journal.summary_text
               ~seed_hex:(Cover.hex_str (fst hl).Journal.jh_seed)
               ~path (fst hl) (snd hl))
      | () ->
          Error
            (Pf_short
               ("the journal at " ^ path ^ " holds " ^ nat_to_string k
              ^ " lines and the run asked for " ^ nat_to_string n)))

(** [run ~progress c] is a whole run: make the directory, open or create the
    journal and the trace, run the batches that are still missing, and answer
    the summary.  The summary is a function of the JOURNAL alone, so its bytes
    do not change in M32. *)
let run ~(progress : string -> unit) (c : config) : (string, failure) result =
  let path = journal_path c.p_dir in
  let tpath = trace_path c.p_dir in
  let lcfg = legs_config c in
  Result.bind
    (Result.map_error
       (fun e -> Pf_mkdir (Rust_leg.error_text e))
       (Rust_leg.mkdir_parents c.p_dir))
    (fun () ->
      Result.bind
        (match () with
        | () when Sys.file_exists path -> resume_open c lcfg path tpath
        | () -> fresh_open c lcfg path tpath)
        (fun k ->
          Result.bind
            (match () with
            | () when k >= c.p_samples -> Ok ()
            | () ->
                run_batches lcfg ~progress ~path ~tpath ~batch:c.p_batch k
                  (drop k (draw c.p_samples c.p_seed)))
            (fun () -> finish path c.p_samples)))

(** [replay ~dir] answers the summary of an existing journal.  It spawns
    nothing, reads no repository, opens no clone and writes nothing, so a
    journal copied to another machine replays there (decision sheet Q4). *)
let replay ~(dir : string) : (string, failure) result =
  let path = journal_path dir in
  match () with
  | () when Sys.file_exists path -> summary path
  | () -> Error (Pf_absent path)
