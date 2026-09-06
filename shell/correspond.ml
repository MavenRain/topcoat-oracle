(** Correspond is the M32 correspondence gate AS DATA.  It holds the trace
    codec, the one writer of a step list, and the pure checker that reads a
    journal and a trace together.  Nothing here opens a channel, reads a clock
    or spawns a process.  The step vocabulary is [Frame.tname] and nothing
    else, so a change to model/frame.ml breaks this build and not a test
    (ruling R3).  model/ is READ here and is never changed (ruling R2). *)

open Prelude

(** A journal cell either carries an observation or names the leg's own
    reason.  This is the [Differ.cell] distinction of core/differ.ml:158,
    carried across the file boundary as the two names the checker needs. *)
type presence = Cell_present | Cell_absent

(** The five row kinds the pipeline can produce (ruling R5).
    [Kd_dropped] is a position the rust crate writer refused.
    [Kd_build_lost] is a batch that lost its leg BEFORE the crate ran.
    [Kd_leg_lost] is a batch that lost a leg AFTER the crate ran.
    [Kd_no_line] is a kept position with no pair left.  [Kd_paired] is a kept
    and paired position.  The row sites are section 4.4 of the M32 spec, the
    full replacement of [rows_ok], for [Kd_dropped], [Kd_no_line] and
    [Kd_paired], and section 4.5, the full replacement of [rows_fail], for
    [Kd_build_lost] and [Kd_leg_lost].  No M31 line of shell/pipeline.ml is
    cited, because sections 4.4 and 4.5 replace shell/pipeline.ml:181-237
    outright. *)
type kind = Kd_dropped | Kd_build_lost | Kd_leg_lost | Kd_no_line | Kd_paired

(** What the pipeline already knows at row time.  [ev_head] is
    [Journal.head] of the verdict text the row carries. *)
type evidence = {
  ev_kind : kind;
  ev_rust : presence;
  ev_js : presence;
  ev_ref : presence;
  ev_head : string;
}

(** [step_name t] is the constructor of [Frame.tname] in snake case.  This
    match is exhaustive over the 19 constructors of model/frame.ml:14-19 and
    carries no wildcard arm, so a new step is a build failure here. *)
let step_name (t : Frame.tname) : string =
  match t with
  | Frame.Shape_ok -> "shape_ok"
  | Frame.Shape_fail -> "shape_fail"
  | Frame.Print_ok -> "print_ok"
  | Frame.Compile_ok -> "compile_ok"
  | Frame.Compile_fail -> "compile_fail"
  | Frame.Exec_rust_ok -> "exec_rust_ok"
  | Frame.Exec_rust_crash -> "exec_rust_crash"
  | Frame.Exec_js_ok -> "exec_js_ok"
  | Frame.Exec_js_crash -> "exec_js_crash"
  | Frame.Exec_ref_ok -> "exec_ref_ok"
  | Frame.Exec_ref_crash -> "exec_ref_crash"
  | Frame.Judge_agree -> "judge_agree"
  | Frame.Judge_diverge -> "judge_diverge"
  | Frame.Judge_known -> "judge_known"
  | Frame.Judge_infra -> "judge_infra"
  | Frame.File_unjudged -> "file_unjudged"
  | Frame.Shrink -> "shrink"
  | Frame.Shrink_done -> "shrink_done"
  | Frame.Stay -> "stay"

(** [all_steps ()] is every constructor of [Frame.tname], in the order
    model/frame.ml:14-19 declares them.  [step_of_name] is the inverse of
    [step_name] over this list, so the two can never disagree. *)
let all_steps () : Frame.tname list =
  [ Frame.Shape_ok; Frame.Shape_fail; Frame.Print_ok; Frame.Compile_ok;
    Frame.Compile_fail; Frame.Exec_rust_ok; Frame.Exec_rust_crash;
    Frame.Exec_js_ok; Frame.Exec_js_crash; Frame.Exec_ref_ok;
    Frame.Exec_ref_crash; Frame.Judge_agree; Frame.Judge_diverge;
    Frame.Judge_known; Frame.Judge_infra; Frame.File_unjudged; Frame.Shrink;
    Frame.Shrink_done; Frame.Stay ]

(** [step_of_name s] is the step [s] names, and None when no step does.
    Equality on [Frame.tname] goes through [String.equal] on [step_name]
    everywhere in this file (ruling R3). *)
let step_of_name (s : string) : Frame.tname option =
  fold
    (fun acc t ->
      Option.fold
        ~none:
          (match () with
          | () when String.equal (step_name t) s -> Some t
          | () -> None)
        ~some:(fun found -> Some found)
        acc)
    None (all_steps ())

(** [verdict_str v] names a model verdict.  model/frame.ml exports
    [leg_str] and [stage_str] but no verdict speller, so this is the one
    spelling M32 adds and model/ still does not change. *)
let verdict_str (v : State.verdict) : string =
  match v with
  | State.V_none -> "none"
  | State.V_agree -> "agree"
  | State.V_diverge -> "diverge"
  | State.V_known -> "known"

(** [world_text w] names a model world in one line, for the failure text of a
    step that is not an edge.  The leg letters are [Frame.leg_str]:
    "p" pending, "o" ok, "c" crashed. *)
let world_text (w : State.state) : string =
  "stage=" ^ Frame.stage_str w.State.stage ^ " rust="
  ^ Frame.leg_str w.State.rust ^ " js=" ^ Frame.leg_str w.State.js ^ " ref="
  ^ Frame.leg_str w.State.reference ^ " verdict=" ^ verdict_str w.State.verdict

(** [exec_of_rust p], [exec_of_js p] and [exec_of_ref p] read a leg's exec
    step off its cell presence.  A leg's exec step is _ok exactly when the
    differ cell for that leg is Present, and _crash when it is Absent,
    whatever the reason (ruling R5). *)
let exec_of_rust (p : presence) : Frame.tname =
  match p with
  | Cell_present -> Frame.Exec_rust_ok
  | Cell_absent -> Frame.Exec_rust_crash

let exec_of_js (p : presence) : Frame.tname =
  match p with
  | Cell_present -> Frame.Exec_js_ok
  | Cell_absent -> Frame.Exec_js_crash

let exec_of_ref (p : presence) : Frame.tname =
  match p with
  | Cell_present -> Frame.Exec_ref_ok
  | Cell_absent -> Frame.Exec_ref_crash

(** [judge_of_head h] is the judge step a verdict head asks for, and None for
    a head that asks for no judge step.  A K4 row heads "no_line" and always
    walks Judge_infra, so that head asks for a judge step too.  The head
    "batch_fail" is the one head that answers None here and still ACCEPTS a
    judge step, because Kd_build_lost and Kd_leg_lost share it and only the
    first walks compile_fail into Gen_bug;  [judge_free] below carries that
    case. *)
let judge_of_head (h : string) : Frame.tname option =
  match () with
  | () when String.equal h "agree" -> Some Frame.Judge_agree
  | () when String.equal h "known" -> Some Frame.Judge_known
  | () when String.equal h "diverge" -> Some Frame.Judge_diverge
  | () when String.equal h "leg_fail" -> Some Frame.Judge_infra
  | () when String.equal h "no_line" -> Some Frame.Judge_infra
  | () -> None

(** [steps_of e] is the ONE writer of a step list (ruling R5).  The pipeline
    calls it at row time and the checker never calls it, so the two directions
    of the gate stay independent.

    K1 and K2 never reached a crate that ran: shape, print, compile_fail, and
    the world ends in Gen_bug.  K3 and K4 reached a crate that ran but lost a
    product leg: both product legs crash, the reference decides by its own
    cell, and Judge_infra ends the world in Leg_failed, or in Oracle_bug when
    the reference cell is Absent.  K5 reads all three legs off their cells and
    takes the judge step the verdict head asks for. *)
let steps_of (e : evidence) : Frame.tname list =
  match e.ev_kind with
  | Kd_dropped | Kd_build_lost ->
      [ Frame.Shape_ok; Frame.Print_ok; Frame.Compile_fail ]
  | Kd_leg_lost | Kd_no_line ->
      [ Frame.Shape_ok; Frame.Print_ok; Frame.Compile_ok;
        Frame.Exec_rust_crash; Frame.Exec_js_crash; exec_of_ref e.ev_ref;
        Frame.Judge_infra ]
  | Kd_paired ->
      append
        [ Frame.Shape_ok; Frame.Print_ok; Frame.Compile_ok;
          exec_of_rust e.ev_rust; exec_of_js e.ev_js; exec_of_ref e.ev_ref ]
        [ Option.fold ~none:Frame.Judge_infra
            ~some:(fun t -> t)
            (judge_of_head e.ev_head) ]

(** The trace codec (ruling R4).  The header is the journal header's four
    fields, in the journal's own order, under the version key "m32".  The
    encoders are [Journal.jobject], [Journal.field], [Journal.jstring],
    [Journal.jint] and [Journal.jarray], so the trace and the journal escape
    the same bytes the same way. *)
type trace_header = {
  th_seed : int;
  th_batch : int;
  th_plant : string;
  th_topcoat : string;
}

type trace_line = { tl_i : int; tl_steps : string list }

let trace_version : int = 1

let encode_trace_header (h : trace_header) : string =
  Journal.jobject
    [ Journal.field "m32" (Journal.jint trace_version);
      Journal.field "seed" (Journal.jint h.th_seed);
      Journal.field "batch" (Journal.jint h.th_batch);
      Journal.field "plant" (Journal.jstring h.th_plant);
      Journal.field "topcoat" (Journal.jstring h.th_topcoat) ]

let encode_trace_line (l : trace_line) : string =
  Journal.jobject
    [ Journal.field "i" (Journal.jint l.tl_i);
      Journal.field "steps"
        (Journal.jarray (map Journal.jstring l.tl_steps)) ]

(** Every way the gate says no.  One constructor per check (ruling R8).
    [F_trace] carries the 1 based line the trace codec was reading AND a
    [Journal.error] unedited, so a trace that is not JSON is named by the
    journal codec and not by a second parser, and the line the CLI prints is
    the codec's own line and never a constant.  [F_front] is the front of walk
    rule of C5 and carries the head, the journal f cell, the name of the step
    it refused and the 1 based position of that step. *)
type failure =
  | F_trace of int * Journal.error
  | F_version of int
  | F_field of string * string * string
  | F_count of int * int
  | F_index of int * int * int
  | F_front of int * string * string * string * int
  | F_step of int * string
  | F_edge of int * string * string
  | F_open of int * string
  | F_end of int * string * string
  | F_cell of int * string * string
  | F_judge of int * string * string
  | F_leg of int * string

(** [failure_line f] is the 1 based line of trace.jsonl the failure names.
    Line 1 is the header, and sample i sits on line i + 2.  A decode failure
    names the line the codec was reading, which is the same number the codec
    writes inside its own text.  A whole file check names line 1, the line
    that opens the file. *)
let failure_line (f : failure) : int =
  match f with
  | F_trace (n, _) -> n
  | F_version _ -> 1
  | F_field (_, _, _) -> 1
  | F_count (_, _) -> 1
  | F_index (n, _, _) -> n
  | F_front (n, _, _, _, _) -> n
  | F_step (n, _) -> n
  | F_edge (n, _, _) -> n
  | F_open (n, _) -> n
  | F_end (n, _, _) -> n
  | F_cell (n, _, _) -> n
  | F_judge (n, _, _) -> n
  | F_leg (n, _) -> n

(** [article h] is the indefinite article a verdict head takes in a failure
    text: "an" for a head that starts with a vowel and "a" for every other
    head.  Of the seven heads M31 can write, "agree" is the only one that
    starts with a vowel;  "known", "diverge", "leg_fail", "dropped", "no_line"
    and "batch_fail" take "a".  The test is a total [List.exists] with
    [String.starts_with] over the five vowels, so it reads no byte by index
    and answers "a" for the empty string. *)
let article (h : string) : string =
  match () with
  | () when
      List.exists
        (fun v -> String.starts_with ~prefix:v h)
        [ "a"; "e"; "i"; "o"; "u" ] ->
      "an"
  | () -> "a"

(** [f_cell_text f] names the state of a journal f cell in a failure text.
    C5 keys on that cell, so a failure C5 raises says which state it read. *)
let f_cell_text (f : string) : string =
  match () with
  | () when String.equal f "" -> "an empty f cell"
  | () -> "a non empty f cell"

(** [failure_text f] is what bin/m32.ml prints after "m32 failure: line N: ".
    The empty trace has its own arm, because the journal codec's [E_empty]
    text names the journal and this failure is about the trace.  Every other
    [Journal.error] carries its own line number and its own noun, which name
    the text that failed to parse and not the file it sat in, so those texts
    are quoted unedited.  The head of a C5 failure takes its article from
    [article]. *)
let failure_text (f : failure) : string =
  match f with
  | F_trace (_, Journal.E_empty) -> "the trace holds no line"
  | F_trace (_, e) -> "the trace does not decode: " ^ Journal.error_text e
  | F_version v ->
      "the trace version is " ^ nat_to_string v ^ " and this checker reads "
      ^ nat_to_string trace_version
  | F_field (k, t, j) ->
      "the trace header says " ^ k ^ " " ^ t ^ " and the journal header says "
      ^ k ^ " " ^ j
  | F_count (j, t) ->
      "the journal holds " ^ nat_to_string j ^ " sample lines and the trace holds "
      ^ nat_to_string t
  | F_index (_, j, t) ->
      "the journal names sample " ^ nat_to_string j ^ " and the trace names "
      ^ nat_to_string t
  | F_front (_, h, f, s, p) ->
      article h ^ " " ^ h ^ " verdict with " ^ f_cell_text f ^ " holds " ^ s
      ^ " at step " ^ nat_to_string p
  | F_step (_, s) -> "the step " ^ s ^ " is not a step of model/frame.ml"
  | F_edge (_, s, w) -> "the step " ^ s ^ " is not an edge from " ^ w
  | F_open (_, g) -> "the line ends in " ^ g ^ ", which is not a model terminal"
  | F_end (_, h, g) ->
      article h ^ " " ^ h ^ " verdict must not end in " ^ g
  | F_cell (_, leg, m) -> "the " ^ leg ^ " leg " ^ m
  | F_judge (_, s, h) ->
      "the judge step " ^ s ^ " does not match the verdict head " ^ h
  | F_leg (_, leg) ->
      "the verdict names the leg " ^ leg ^ " and the trace holds no exec_"
      ^ leg ^ "_crash"

(** Total byte helpers.  [String.sub] raises on a bad range and the house
    rules forbid an exception, so the prefix test walks [Prelude.byte_at],
    which core/journal.ml:341 already uses for the same reason. *)
let rec take_bytes (t : string) (k : int) (i : int) (acc : string) : string =
  match () with
  | () when i >= k -> acc
  | () ->
      Option.fold ~none:acc
        ~some:(fun b -> take_bytes t k (i + 1) (acc ^ b))
        (Prelude.byte_at t i)

let has_prefix (p : string) (t : string) : bool =
  String.equal (take_bytes t (String.length p) 0 "") p

(** [cell_presence verdict leg cell] is the presence predicate the pipeline
    used, read back off the journal alone (ruling R8, check C3).  A cell is
    Absent when it is "" (the dropped row of shell/pipeline.ml:195, the three
    no_line rows of :211, :215 and :218, and the pre-crate batch_fail row of
    :233-235;  those are the M31 lines, which sections 4.4 and 4.5 replace
    outright) and when the verdict is a leg_fail naming this leg
    (core/differ.ml:449, :471-476).  Every other cell is
    Present, because [Legs.cells_of] wraps a decoded observation as
    [Differ.Present] and wraps nothing else. *)
let cell_presence (verdict : string) (leg : string) (cell : string) : presence =
  match () with
  | () when String.equal cell "" -> Cell_absent
  | () when has_prefix ("leg_fail:" ^ leg ^ ":") verdict -> Cell_absent
  | () -> Cell_present

(** [leg_of_verdict v] is the leg a leg_fail verdict names.  The three
    spellings are [Differ.leg_name], core/differ.ml:449. *)
let leg_of_verdict (v : string) : string option =
  fold
    (fun acc l ->
      Option.fold
        ~none:
          (match () with
          | () when has_prefix ("leg_fail:" ^ l ^ ":") v -> Some l
          | () -> None)
        ~some:(fun found -> Some found)
        acc)
    None [ "rust"; "js"; "ref" ]

(** [holds names s] answers whether the step list carries the step [s]. *)
let holds (names : string list) (s : string) : presence =
  fold
    (fun acc t ->
      match () with
      | () when String.equal t s -> Cell_present
      | () -> acc)
    Cell_absent names

(** [judge_in names] is the judge step of a step list, and None when the walk
    took none.  The fold keeps the LAST one, so a list that somehow carried
    two is judged on the one that decided the disposition. *)
let judge_in (names : string list) : string option =
  fold
    (fun acc s ->
      match () with
      | () when String.equal s "judge_agree" -> Some s
      | () when String.equal s "judge_known" -> Some s
      | () when String.equal s "judge_diverge" -> Some s
      | () when String.equal s "judge_infra" -> Some s
      | () -> acc)
    None names

(** ---------- the decoder ---------- *)

let ti (n : int) (ps : (string * Json.jvalue) list) (k : string) :
    (int, failure) result =
  Result.map_error (fun e -> F_trace (n, e)) (Journal.get_int n ps k)

let ts (n : int) (ps : (string * Json.jvalue) list) (k : string) :
    (string, failure) result =
  Result.map_error (fun e -> F_trace (n, e)) (Journal.get_str n ps k)

let tss (n : int) (ps : (string * Json.jvalue) list) (k : string) :
    (string list, failure) result =
  Result.map_error (fun e -> F_trace (n, e)) (Journal.get_strs n ps k)

let tobj (n : int) (text : string) :
    ((string * Json.jvalue) list, failure) result =
  Result.map_error (fun e -> F_trace (n, e)) (Journal.parse_object n text)

(** The header version is a Correspond failure and NOT a [Journal.E_version],
    because core/journal.ml owns the journal version and no other (R4). *)
let decode_trace_header (n : int) (text : string) :
    (trace_header, failure) result =
  Result.bind (tobj n text) (fun ps ->
      Result.bind (ti n ps "m32") (fun v ->
          match () with
          | () when not (Int.equal v trace_version) -> Error (F_version v)
          | () ->
              Result.bind (ti n ps "seed") (fun seed ->
                  Result.bind (ti n ps "batch") (fun batch ->
                      Result.bind (ts n ps "plant") (fun plant ->
                          Result.map
                            (fun sha ->
                              { th_seed = seed; th_batch = batch;
                                th_plant = plant; th_topcoat = sha })
                            (ts n ps "topcoat"))))))

let decode_trace_line (n : int) (text : string) : (trace_line, failure) result =
  Result.bind (tobj n text) (fun ps ->
      Result.bind (ti n ps "i") (fun i ->
          Result.map (fun ss -> { tl_i = i; tl_steps = ss }) (tss n ps "steps")))

let rec decode_body (n : int) (texts : string list) :
    (trace_line list, failure) result =
  match texts with
  | [] -> Ok []
  | t :: rest ->
      Result.bind (decode_trace_line n t) (fun l ->
          Result.map (fun ls -> l :: ls) (decode_body (n + 1) rest))

(** [decode_trace texts] decodes a whole trace file.  The line numbers it
    hands to the codec are the file's own, and every codec helper puts that
    number into the [F_trace] it builds, so a red gate names the line in the
    "line N:" prefix as well as inside the codec's own text.  An empty file
    has no line of its own and names line 1, and [failure_text] gives that one
    case the trace's own noun, "the trace holds no line", so no failure of the
    trace names the journal. *)
let decode_trace (texts : string list) :
    (trace_header * trace_line list, failure) result =
  match texts with
  | [] -> Error (F_trace (1, Journal.E_empty))
  | h :: rest ->
      Result.bind (decode_trace_header 1 h) (fun th ->
          Result.map (fun ls -> (th, ls)) (decode_body 2 rest))

(** ---------- direction 1: the log against the model ---------- *)

(** [edge w s] is the world the step named [s] leads to from [w], and None
    when [s] is not an edge of [w].  The edge table is [Frame.steps] itself
    (model/frame.ml:86-102) and never a copy of it. *)
let edge (w : State.state) (s : string) : State.state option =
  fold
    (fun acc pr ->
      Option.fold
        ~none:
          (match () with
          | () when String.equal (step_name (fst pr)) s -> Some (snd pr)
          | () -> None)
        ~some:(fun found -> Some found)
        acc)
    None
    (Frame.steps Frame.Coupled w)

(** [walk n w names] folds a step list from [w] through the model.  A name
    that is no step at all is [F_step];  a step that is not an edge of the
    world reached so far is [F_edge]. *)
let rec walk (n : int) (w : State.state) (names : string list) :
    (State.state, failure) result =
  match names with
  | [] -> Ok w
  | s :: rest ->
      Result.bind
        (Option.fold ~none:(Error (F_step (n, s)))
           ~some:(fun _t -> Ok ())
           (step_of_name s))
        (fun () ->
          Option.fold
            ~none:(Error (F_edge (n, s, world_text w)))
            ~some:(fun w1 -> walk n w1 rest)
            (edge w s))

(** [is_terminal w] is derived from the model and not from model/props.ml: a
    terminal world is a world whose only edge is Stay to itself
    (model/frame.ml:101-102). *)
let is_terminal (w : State.state) : bool =
  match Frame.steps Frame.Coupled w with
  | [] -> false
  | pr :: rest -> (
      match rest with
      | [] -> String.equal (step_name (fst pr)) "stay"
      | _ :: _ -> false)

(** ---------- direction 2: the journal against the log ---------- *)

(** [want_stage h f] is every end stage a verdict head allows (ruling R8,
    check C5), keyed on the head AND on the journal f cell.  An empty list
    rejects the head itself.  The "leg_fail" head does NOT allow "gen_bug":
    a leg_fail row is always a [Kd_paired] row, and that arm of [steps_of]
    always emits [Frame.Compile_ok], so the world has left the stage that
    reaches Gen_bug before the judge step.  The "no_line" head drops
    "gen_bug" for the same reason: the [Kd_no_line] arm of [steps_of] also
    emits [Frame.Compile_ok].  That head drops "oracle_bug" too, because
    section 4.4's [no_line] helper hardcodes [Cell_present] for the reference
    and always writes an f cell, so the arm emits [Frame.Exec_ref_ok] and
    [Frame.judge_steps] answers Judge_infra into Leg_failed;  a K4 row that
    ends in Oracle_bug needs an Absent reference cell, which that helper
    cannot produce, and a K4 trace line rewritten to "exec_ref_crash" is
    refused by C3 against the row's non empty f cell.  The "batch_fail" head
    carries TWO row kinds,
    so the f cell decides between them: [Kd_build_lost] loses the batch
    before the crate ran, writes an empty f cell and walks Compile_fail into
    Gen_bug;  [Kd_leg_lost] reaches a crate that ran, keeps the reference
    cell the reference leg wrote and walks Judge_infra into Leg_failed.  The
    head alone cannot tell the two kinds apart, so C5 reads the cell the
    journal already holds and a K2 row rewritten with the [Kd_leg_lost] step
    tail is refused.  Facts F-E states that the reference cell is never
    produced Absent today, and section 4.5's [rows_fail] hardcodes
    [Cell_present] for the After_crate reference, so a [Kd_leg_lost] row with
    an empty f cell cannot arise. *)
let want_stage (h : string) (f : string) : string list =
  match () with
  | () when String.equal h "agree" -> [ "dropped_agree" ]
  | () when String.equal h "known" -> [ "dropped_known" ]
  | () when String.equal h "diverge" -> [ "minimizing_hi" ]
  | () when String.equal h "dropped" -> [ "gen_bug" ]
  | () when String.equal h "leg_fail" -> [ "leg_failed"; "oracle_bug" ]
  | () when String.equal h "no_line" -> [ "leg_failed" ]
  | () when String.equal h "batch_fail" && String.equal f "" -> [ "gen_bug" ]
  | () when String.equal h "batch_fail" -> [ "leg_failed" ]
  | () -> []

let allows (gs : string list) (g : string) : bool =
  fold (fun acc x -> acc || String.equal x g) false gs

(** [unwritten s] holds for the five step names M31 never writes.  They are
    the snake case spellings of [Frame.Shape_fail], [Frame.File_unjudged],
    [Frame.Shrink], [Frame.Shrink_done] and [Frame.Stay], declared at
    model/frame.ml:14-19 and carried, name by name in that order, by the
    transitions at model/frame.ml:90, :84, :98, :99 and :102, the same five
    section 12 lists as never emitted: no arm of [steps_of] holds one of
    them, and no line of shell/pipeline.ml or shell/legs.ml writes one.  The
    test is a
    total [List.exists] with [String.equal] over a literal list, so it reads
    no index. *)
let unwritten (s : string) : bool =
  List.exists (fun u -> String.equal u s)
    [ "shape_fail"; "file_unjudged"; "shrink"; "shrink_done"; "stay" ]

(** [unwritten_at names] is the name and the 1 based position of the FIRST
    step of a step list that M31 never writes, and ("", 0) when the list holds
    none.  The fold walks the whole list and keeps the first hit, so it reads
    no index and calls no partial list function. *)
let unwritten_at (names : string list) : string * int =
  snd
    (fold
       (fun (seen, hit) s ->
         match () with
         | () when not (Int.equal (snd hit) 0) -> (seen + 1, hit)
         | () when unwritten s -> (seen + 1, (s, seen + 1))
         | () -> (seen + 1, hit))
       (0, ("", 0)) names)

(** [check_front n names head fc] is the front of walk rule of check C5
    (ruling R8).  It holds for EVERY head M31 can write, all five row kinds
    and both "batch_fail" arms: no arm of [steps_of] emits [Frame.Shape_fail],
    [Frame.File_unjudged], [Frame.Shrink], [Frame.Shrink_done] or
    [Frame.Stay], every arm opens with [Frame.Shape_ok], and no line of
    shell/pipeline.ml or shell/legs.ml writes any of the five.  So a step list
    that holds one of them is a rewritten list whatever the head and whatever
    the f cell.  Without this rule the walk answers Ok for the list
    ["shape_fail"], because [Frame.Shape_fail] is an edge from [Generated]
    into [Gen_bug] (model/frame.ml:89-90) and [Gen_bug] is terminal
    (model/frame.ml:101-102), and C5 then accepts the "dropped" head and the
    empty f cell "batch_fail" head, both of which list "gen_bug".  It answers
    Ok for an accepted list with "stay" appended too, because [Frame.Stay] is
    the self loop of every terminal (model/frame.ml:102), so the walk ends on
    the same world and no later check reads the step.  The test is a total
    [List.exists] with [String.equal] over the whole list, so it reads no head
    and no index, and the failure names the offending step, the first one by
    position.  [Frame.Compile_fail] is the only OTHER step that walks into
    [Gen_bug], and [steps_of] emits it LAST for both kinds that reach it, so
    no second rule is needed.  The rule runs LAST in the per line chain, so
    the C3 to C6 texts win when both apply, and it is the only refusal of a
    list that no earlier arm rejects, such as the K1 dropped row rewritten to
    ["shape_fail"] and an accepted list with "stay" appended. *)
let check_front (n : int) (names : string list) (head : string) (fc : string) :
    (unit, failure) result =
  let s, p = unwritten_at names in
  match () with
  | () when List.exists unwritten names -> Error (F_front (n, head, fc, s, p))
  | () -> Ok ()

(** [check_cell n leg names verdict cell] is check C3 for one leg.  The trace
    holds Exec_<leg>_ok exactly when the journal cell for that leg is a
    Present cell. *)
let check_cell (n : int) (leg : string) (names : string list)
    (verdict : string) (cell : string) : (unit, failure) result =
  let in_trace = holds names ("exec_" ^ leg ^ "_ok") in
  let in_journal = cell_presence verdict leg cell in
  match (in_trace, in_journal) with
  | Cell_present, Cell_present -> Ok ()
  | Cell_absent, Cell_absent -> Ok ()
  | Cell_present, Cell_absent ->
      Error (F_cell (n, leg, "ran in the trace and has no cell in the journal"))
  | Cell_absent, Cell_present ->
      Error (F_cell (n, leg, "has a cell in the journal and did not run in the trace"))

(** [judge_free h] is the one head that accepts BOTH no judge step and
    judge_infra: a "batch_fail" row is Kd_build_lost, which loses the batch
    before the crate ran and walks compile_fail into Gen_bug with no judge
    step, or Kd_leg_lost, which reaches a crate that ran and walks Judge_infra
    into Leg_failed.  The two kinds share the head, so C4 cannot decide
    between them from the head alone and accepts either shape.  Check C5 then
    pins the end stage from the journal f cell, which DOES tell the two kinds
    apart: an empty f cell admits only "gen_bug" and a non empty f cell admits
    only "leg_failed".  Check C3 pins the cells. *)
let judge_free (h : string) : bool = String.equal h "batch_fail"

(** [check_judge n names head] is check C4.  A head that asks for a judge step
    must have exactly that one;  a head that asks for none must have none,
    except for the [judge_free] head.  The two options are read with
    [Option.fold] and never with a match on an option. *)
let check_judge (n : int) (names : string list) (head : string) :
    (unit, failure) result =
  let want = judge_of_head head in
  Option.fold
    ~none:
      (Option.fold ~none:(Ok ())
         ~some:(fun _t -> Error (F_judge (n, "none", head)))
         want)
    ~some:(fun s ->
      Option.fold
        ~none:
          (match () with
          | () when judge_free head && String.equal s "judge_infra" -> Ok ()
          | () -> Error (F_judge (n, s, head)))
        ~some:(fun t ->
          match () with
          | () when String.equal s (step_name t) -> Ok ()
          | () -> Error (F_judge (n, s, head)))
        want)
    (judge_in names)

(** [check_leg n names verdict] is check C6: a leg_fail verdict names a leg,
    and that leg must have crashed in the trace. *)
let check_leg (n : int) (names : string list) (verdict : string) :
    (unit, failure) result =
  Option.fold ~none:(Ok ())
    ~some:(fun leg ->
      match holds names ("exec_" ^ leg ^ "_crash") with
      | Cell_present -> Ok ()
      | Cell_absent -> Error (F_leg (n, leg)))
    (leg_of_verdict verdict)

(** ---------- the report ---------- *)

type report = {
  rp_lines : int;
  rp_dropped_agree : int;
  rp_dropped_known : int;
  rp_minimizing_hi : int;
  rp_gen_bug : int;
  rp_leg_failed : int;
  rp_oracle_bug : int;
}

let empty_report () : report =
  { rp_lines = 0; rp_dropped_agree = 0; rp_dropped_known = 0;
    rp_minimizing_hi = 0; rp_gen_bug = 0; rp_leg_failed = 0;
    rp_oracle_bug = 0 }

(** [bump r g] counts one line under the end stage [g], in the
    [Frame.stage_str] spelling.  A stage this milestone does not count cannot
    arrive: [want_stage] rejects every head that could reach one. *)
let bump (r : report) (g : string) : report =
  let r = { r with rp_lines = r.rp_lines + 1 } in
  match () with
  | () when String.equal g "dropped_agree" ->
      { r with rp_dropped_agree = r.rp_dropped_agree + 1 }
  | () when String.equal g "dropped_known" ->
      { r with rp_dropped_known = r.rp_dropped_known + 1 }
  | () when String.equal g "minimizing_hi" ->
      { r with rp_minimizing_hi = r.rp_minimizing_hi + 1 }
  | () when String.equal g "gen_bug" -> { r with rp_gen_bug = r.rp_gen_bug + 1 }
  | () when String.equal g "leg_failed" ->
      { r with rp_leg_failed = r.rp_leg_failed + 1 }
  | () when String.equal g "oracle_bug" ->
      { r with rp_oracle_bug = r.rp_oracle_bug + 1 }
  | () -> r

(** [report_text ~dir r] is the ONE stdout line of [m32 check], newline
    terminated, in the [Journal.summary_text] voice. *)
let report_text ~(dir : string) (r : report) : string =
  "m32 check " ^ dir ^ ": " ^ nat_to_string r.rp_lines ^ " lines, dropped_agree "
  ^ nat_to_string r.rp_dropped_agree ^ ", dropped_known "
  ^ nat_to_string r.rp_dropped_known ^ ", minimizing_hi "
  ^ nat_to_string r.rp_minimizing_hi ^ ", gen_bug "
  ^ nat_to_string r.rp_gen_bug ^ ", leg_failed "
  ^ nat_to_string r.rp_leg_failed ^ ", oracle_bug "
  ^ nat_to_string r.rp_oracle_bug ^ "\n"

(** ---------- the whole check ---------- *)

(** [check_headers jh th] is check C1: the two headers agree on all four
    fields.  The version is already checked by the decoder. *)
let check_headers (jh : Journal.header) (th : trace_header) :
    (unit, failure) result =
  match () with
  | () when not (Int.equal th.th_seed jh.Journal.jh_seed) ->
      Error
        (F_field
           ( "seed", nat_to_string th.th_seed,
             nat_to_string jh.Journal.jh_seed ))
  | () when not (Int.equal th.th_batch jh.Journal.jh_batch) ->
      Error
        (F_field
           ( "batch", nat_to_string th.th_batch,
             nat_to_string jh.Journal.jh_batch ))
  | () when not (String.equal th.th_plant jh.Journal.jh_plant) ->
      Error (F_field ("plant", th.th_plant, jh.Journal.jh_plant))
  | () when not (String.equal th.th_topcoat jh.Journal.jh_topcoat) ->
      Error (F_field ("topcoat", th.th_topcoat, jh.Journal.jh_topcoat))
  | () -> Ok ()

(** [check_line n jl tl] runs both directions over ONE sample and answers the
    end stage it reached.  The checks run in the order C2 index, direction 1
    walk, C3 cells, C4 judge, C6 leg, C5 on the end stage and terminality, and
    the front of walk rule of C5 LAST, so the first failure a line has is the
    one the CLI prints and the C3 to C6 texts win when both apply.  The chain
    refuses when ANY predicate fails, so acceptance does not depend on the
    order.  C5 reads the verdict head AND the row's f cell, which is bound as
    [fc] here, in both of its parts. *)
let check_line (n : int) (jl : Journal.line) (tl : trace_line) :
    (string, failure) result =
  match () with
  | () when not (Int.equal jl.Journal.jl_i tl.tl_i) ->
      Error (F_index (n, jl.Journal.jl_i, tl.tl_i))
  | () ->
      let v = jl.Journal.jl_verdict in
      let h = Journal.head v in
      let fc = jl.Journal.jl_f in
      Result.bind (walk n State.init tl.tl_steps) (fun w ->
          Result.bind (check_cell n "rust" tl.tl_steps v jl.Journal.jl_r)
            (fun () ->
              Result.bind (check_cell n "js" tl.tl_steps v jl.Journal.jl_j)
                (fun () ->
                  Result.bind (check_cell n "ref" tl.tl_steps v jl.Journal.jl_f)
                    (fun () ->
                      Result.bind (check_judge n tl.tl_steps h) (fun () ->
                          Result.bind (check_leg n tl.tl_steps v) (fun () ->
                              let g = Frame.stage_str w.State.stage in
                              Result.bind
                                (match () with
                                | () when not (allows (want_stage h fc) g) ->
                                    Error (F_end (n, h, g))
                                | () when String.equal h "diverge" -> Ok ()
                                | () when not (is_terminal w) ->
                                    Error (F_open (n, g))
                                | () -> Ok ())
                                (fun () ->
                                  Result.bind (check_front n tl.tl_steps h fc)
                                    (fun () -> Ok g))))))))

let rec check_lines (n : int) (r : report) (jls : Journal.line list)
    (tls : trace_line list) : (report, failure) result =
  match (jls, tls) with
  | [], [] -> Ok r
  | [], _ :: _ -> Ok r
  | _ :: _, [] -> Ok r
  | jl :: jrest, tl :: trest ->
      Result.bind (check_line n jl tl) (fun g ->
          check_lines (n + 1) (bump r g) jrest trest)

(** [check jh jls th tls] is the whole gate as one pure function.  C1 runs
    first, then C2, then every line in file order.  The ragged arms of
    [check_lines] are totality clauses: C2 already refused a count
    mismatch. *)
let check (jh : Journal.header) (jls : Journal.line list)
    (th : trace_header) (tls : trace_line list) : (report, failure) result =
  Result.bind (check_headers jh th) (fun () ->
      match () with
      | () when not (Int.equal (len jls) (len tls)) ->
          Error (F_count (len jls, len tls))
      | () -> check_lines 2 (empty_report ()) jls tls)
