(* M35: one unplanted minimized witness per campaign divergence. *)
open Prelude

type failure = F_usage | F_data of string | F_io of Rust_leg.error
let ( let* ) = Result.bind
let io r = Result.map_error (fun e -> F_io e) r
let data text = Error (F_data text)
let need yes text = if yes then Ok () else data text
let read p = io (Rust_leg.read_file p)
let write p text = io (Rust_leg.write_file p text)
let field = Journal.field
let str = Journal.jstring
let num = Journal.jint

let divergence text =
  List.find_opt (fun v -> String.equal text (Differ.verdict_text v))
    (List.concat_map (fun ch -> List.map (fun sp -> Differ.Diverge (ch, sp))
         [ Differ.Odd Differ.L_rust; Differ.Odd Differ.L_js;
           Differ.Odd Differ.L_ref; Differ.Two_way; Differ.All_three ])
       (Differ.channels ()))

(* A recorded answer is rebuilt as the class that wrote it, never as a
   default.  String.sub raises, so a payload comes off the text through
   Prelude.byte_at, the shell/correspond.ml:305 precedent.  A payload is
   never empty, which matches core/campaign.ml:60 has_payload. *)
let rec bytes_from text i acc =
  Option.fold ~none:acc
    ~some:(fun b -> bytes_from text (i + 1) (acc ^ b)) (byte_at text i)

let payload prefix text =
  let rest = bytes_from text (String.length prefix) "" in
  match () with
  | () when not (Correspond.has_prefix prefix text) -> None
  | () when String.equal rest "" -> None
  | () -> Some rest

let agreement text =
  match () with
  | () when String.equal text (Differ.verdict_text Differ.Agree) -> Some Differ.Agree
  | () -> None

let known text =
  Option.map (fun tag -> Differ.Known (Differ.Tag tag)) (payload "known:" text)

let leg_fail text =
  List.find_map (fun l -> Option.map (fun why -> Differ.Leg_fail (l, why))
      (payload ("leg_fail:" ^ Differ.leg_name l ^ ":") text))
    [ Differ.L_rust; Differ.L_js; Differ.L_ref ]

(* [Differ.verdict_text] is injective over these four reconstructors, so
   a text that none of them accepts was never written by a walk. *)
let verdict_of text =
  List.find_map (fun f -> f text) [ agreement; divergence; known; leg_fail ]

let answer text =
  List.find_map (fun f -> f text)
    [ (fun t -> Option.map (fun v -> Minimize.A_verdict v) (verdict_of t));
      (fun t -> Option.map (fun why -> Minimize.A_no_verdict why)
          (payload "no_verdict: " t)) ]

let load campaign index =
  let* h, members = Result.map_error
      (fun e -> F_data (Campaign_report.error_text e))
      (Campaign_report.read_samples campaign) in
  let* row, sample = Option.fold ~none:(data "sample index absent")
      ~some:Result.ok (nth_opt members index) in
  let* target = Option.fold ~none:(data "sample is not an unexcused divergence")
      ~some:Result.ok (divergence row.Journal.jl_verdict) in
  Ok (h, row, sample, target)

let json r = Result.map_error (fun e -> F_data (Journal.error_text e)) r
let snapshot text = json (Journal.parse_object 1 text)
let get_int ps k = json (Journal.get_int 1 ps k)
let get_str ps k = json (Journal.get_str 1 ps k)
let get_strs ps k = json (Journal.get_strs 1 ps k)

let witness_files out sample =
  let* rt = read (out ^ "/rust.jsonl") in
  let* jt = read (out ^ "/js.jsonl") in
  let one text = match Rust_leg.split_lines text with
    | [ line ] -> Ok line
    | [] | _ :: _ -> data "witness must contain exactly one line" in
  let* rl = one rt in
  let* jl = one jt in
  let* r = Result.map_error (fun _ -> F_data "invalid Rust witness") (Wire.decode_line rl) in
  let* j = Result.map_error (fun _ -> F_data "invalid JS witness") (Wire_js.decode_line jl) in
  let* () = need (r.Wire.d_case = 0 && j.Wire_js.jl_case = 0) "witness index is not zero" in
  Ok (Legs.witness_of (Legs.ref_cell_of Ref_leg.default_config sample) r j)

let result_ok target r wi =
  let* () = need (match r.Minimize.m_stop with
      | Minimize.Fixpoint -> true | Minimize.Fuel | Minimize.Stuck _ -> false)
      ("walk stopped at " ^ Walk.stop_word r.Minimize.m_stop) in
  need (Minimize.preserves target (Minimize.A_verdict wi.Legs.wi_verdict))
    "fresh witness does not preserve the original divergence"

let rendered campaign index h row sample r wi oracle_sha =
  let final = r.Minimize.m_final in
  let lines = Repro.block in
  lines [ "# Campaign repro " ^ string_of_int h.Journal.jh_seed ^ ":" ^ string_of_int index; "";
    "- topcoat: " ^ h.Journal.jh_topcoat; "- topcoat-oracle: " ^ oracle_sha;
    "- plant: none"; "- verdict: " ^ row.Journal.jl_verdict;
    "- original mode: " ^ row.Journal.jl_mode;
    "- final mode: " ^ Taxonomy.mode_name final.Sample.mode;
    "- size: " ^ string_of_int (Minimize.size_of sample) ^ " -> " ^ string_of_int (Minimize.size_of final);
    "- stop: " ^ Walk.stop_word r.Minimize.m_stop; "";
    "This is an observed difference between the legs, pending triage. It is not an upstream bug adjudication.";
    "Minimization preserves the channel and split using the current shrink candidates. Signal arity and compile failures can exclude candidates; this is not a global minimum.";
    ""; "## Program"; ""; "```rust" ]
  ^ lines (Walk.let_lines final)
  ^ lines [ Walk.body_text final; "```"; ""; "## Emitted JS"; "";
      "- form: " ^ Wire.js_form_wire wi.Legs.wi_rust.Wire.d_js_form;
      ""; "```js"; wi.Legs.wi_rust.Wire.d_js; "```"; ""; "## Witness"; "";
      "- rust: " ^ Obs.encode wi.Legs.wi_rust.Wire.d_obs;
      "- js: " ^ Js_leg.cell wi.Legs.wi_js;
      "- ref: " ^ Obs.encode wi.Legs.wi_ref.Legs.r_obs;
      "- verdict: " ^ Differ.verdict_text wi.Legs.wi_verdict;
      ""; "## Walk"; ""; "```text" ]
  ^ concat (map Walk.round_line r.Minimize.m_trace)
  ^ lines [ "```"; ""; "## Reproduce"; "";
      "From the oracle repository root, with the campaign archive unpacked at " ^ Repro.shell_arg campaign ^ ":";
      ""; "```sh"; "dune exec bin/m35.exe -- emit " ^ Repro.shell_arg campaign ^ " "
      ^ string_of_int index ^ " . ../topcoat"; "```"; "" ]

let emit campaign index root clone =
  let out = root ^ "/_emit/m35/out/" ^ string_of_int index in
  let* h, row, sample, target = load campaign index in
  let* () = io (Rust_leg.mkdir_one out) in
  let cfg = { (Legs.default_config ~root ~clone ~out Plant.No_plant) with
      Legs.l_name = "m35case" ^ string_of_int index } in
  let sha name repo = Result.map_error (fun e -> F_data (Provenance.error_text e))
      (Provenance.read_sha cfg.Legs.l_rust ~out ~name ~repo) in
  let* clone_sha = sha "topcoat" clone in
  let* sibling = sha "sibling" (root ^ "/../topcoat") in
  let* () = need (String.equal clone_sha h.Journal.jh_topcoat && String.equal clone_sha sibling)
      "Rust/JS clone pin mismatch" in
  let* oracle_sha = sha "oracle" root in
  let* () = need (Minimize.preserves target (Legs.start cfg sample)) "original sample no longer reproduces" in
  let rounds = ref [] in
  let oracle = { Minimize.o_run = (fun ~round samples ->
      let answers = (Legs.oracle cfg).Minimize.o_run ~round samples in
      rounds := Journal.jobject [ field "round" (num round);
          field "answers" (Journal.jarray (map (fun a -> str (Walk.answer_text a)) answers)) ] :: !rounds;
      prerr_endline ("m35 " ^ string_of_int index ^ " round " ^ string_of_int round
          ^ " candidates " ^ string_of_int (len samples));
      answers) } in
  let fuel = Minimize.size_of sample + 1 in
  let r = Minimize.run oracle { Minimize.fuel } ~target sample in
  let* wi = Result.map_error (fun e -> F_data e) (Legs.witness cfg r.Minimize.m_final) in
  let* () = result_ok target r wi in
  let* rust = read (out ^ "/rp/run.jsonl") in
  let* js = read (out ^ "/rp/seed.js.jsonl") in
  let* () = write (out ^ "/rust.jsonl") rust in
  let* () = write (out ^ "/js.jsonl") js in
  let metadata = Journal.jobject [ field "index" (num index);
      field "oracle_sha" (str oracle_sha); field "fuel" (num fuel) ] in
  let* () = write (out ^ "/walk.jsonl") (Repro.block (metadata :: rev !rounds)) in
  let* () = write (out ^ "/repro.md") (rendered campaign index h row sample r wi oracle_sha) in
  Ok ("m35 emitted " ^ string_of_int index ^ " size " ^ string_of_int (Minimize.size_of sample)
      ^ " -> " ^ string_of_int (Minimize.size_of r.Minimize.m_final) ^ "\n")

let replay campaign index out expected_sha =
  let* h, row, sample, target = load campaign index in
  let* text = read (out ^ "/walk.jsonl") in
  let* meta, rest = match Rust_leg.split_lines text with
    | m :: rs -> Ok (m, rs) | [] -> data "empty walk" in
  let* ps = snapshot meta in
  let* recorded_index = get_int ps "index" in
  let* sha = get_str ps "oracle_sha" in
  let* fuel = get_int ps "fuel" in
  let* () = need (recorded_index = index && fuel = Minimize.size_of sample + 1
      && Repro.is_sha40 sha && String.equal sha expected_sha)
      "walk metadata mismatch" in
  let rec answers acc = function
    | [] -> Ok (rev acc)
    | t :: ts ->
        let* a = Option.fold ~none:(data "unknown answer text") ~some:Result.ok (answer t) in
        answers (a :: acc) ts in
  let rec decode acc = function
    | [] -> Ok (rev acc)
    | l :: ls -> let* ps = snapshot l in
        let* k = get_int ps "round" in
        let* texts = get_strs ps "answers" in
        let* these = answers [] texts in
        decode ((k, these) :: acc) ls in
  let* recorded = decode [] rest in
  let pending = ref recorded in
  let valid = ref true in
  let oracle = { Minimize.o_run = (fun ~round samples -> match !pending with
      | [] -> valid := false; []
      | (k, these) :: more -> pending := more;
          if k <> round || len samples <> len these then valid := false;
          these) } in
  let r = Minimize.run oracle { Minimize.fuel } ~target sample in
  let* () = need (!valid && !pending = []) "walk shape mismatch" in
  let* wi = witness_files out r.Minimize.m_final in
  let* () = result_ok target r wi in
  let* actual = read (out ^ "/repro.md") in
  let* () = need (String.equal actual (rendered campaign index h row sample r wi sha))
      "repro does not match reconstructed walk and witness" in
  Ok ("m35 replay " ^ string_of_int index ^ " green\n")

(* Pool requests from independent greedy walks without changing their order. *)
type task = {
  index : int; row : Journal.line; sample : Sample.t; target : Differ.verdict;
  history : (int * Minimize.answer list) list;
}

let round_json (k, answers) = Journal.jobject [ field "round" (num k);
    field "answers" (Journal.jarray (map (fun a -> str (Walk.answer_text a)) answers)) ]

let advance task =
  let pending = ref task.history in
  let request = ref [] in
  let oracle = { Minimize.o_run = (fun ~round samples -> match !pending with
      | (_, answers) :: rest -> pending := rest; answers
      | [] -> request := [ (round, samples) ];
          map (fun _ -> Minimize.A_no_verdict "pending") samples) } in
  let r = Minimize.run oracle { Minimize.fuel = Minimize.size_of task.sample + 1 }
      ~target:task.target task.sample in
  (r, !request)

let rec starts_preserve tasks answers = match tasks, answers with
  | [], [] -> true
  | [], _ :: _ | _ :: _, [] -> false
  | t :: ts, a :: rest -> Minimize.preserves t.target a && starts_preserve ts rest

let stream campaign root clone =
  let* h, members = Result.map_error (fun e -> F_data (Campaign_report.error_text e))
      (Campaign_report.read_samples campaign) in
  let tasks = List.filter_map (fun (row, sample) ->
      Option.map (fun target -> { index = row.Journal.jl_i; row; sample; target; history = [] })
        (divergence row.Journal.jl_verdict)) members in
  let out = root ^ "/_emit/m35/out/batch" in
  let* () = io (Rust_leg.mkdir_one out) in
  let cfg = { (Legs.default_config ~root ~clone ~out Plant.No_plant) with Legs.l_name = "m35stream" } in
  let sha name repo = Result.map_error (fun e -> F_data (Provenance.error_text e))
      (Provenance.read_sha cfg.Legs.l_rust ~out ~name ~repo) in
  let* clone_sha = sha "topcoat" clone in
  let* sibling = sha "sibling" (root ^ "/../topcoat") in
  let* () = need (String.equal clone_sha h.Journal.jh_topcoat && String.equal clone_sha sibling)
      "Rust/JS clone pin mismatch" in
  let* oracle_sha = sha "oracle" root in
  let batch_id = ref 0 in
  let rec batches samples = match samples with
    | [] -> []
    | _ :: _ ->
        let chunk = Pipeline.take 100 samples in
        let dir = out ^ "/b" ^ string_of_int !batch_id in
        incr batch_id;
        let answers = Legs.run_batch cfg ~dir chunk in
        prerr_endline ("m35 batch " ^ string_of_int !batch_id ^ " samples " ^ string_of_int (len chunk));
        append answers (batches (Pipeline.drop 100 samples)) in
  let starts = batches (map (fun t -> t.sample) tasks) in
  let* () = need (starts_preserve tasks starts) "campaign start verdict drift" in
  let rec rounds tasks =
    let pending = List.filter_map (fun t -> match snd (advance t) with
        | [] -> None | (k, cs) :: _ -> Some (t, k, cs)) tasks in
    match pending with
    | [] -> Ok tasks
    | _ :: _ ->
        let answers = batches (List.concat_map (fun (_, _, cs) -> cs) pending) in
        let rec spread acc left = function
          | [] -> Ok (rev acc)
          | (t, k, cs) :: rest ->
              let n = len cs in
              let these = Pipeline.take n left in
              let* () = need (len these = n) "short pooled batch" in
              let updated = { t with history = append t.history [ (k, these) ] } in
              spread (updated :: acc) (Pipeline.drop n left) rest in
        let* updated = spread [] answers pending in
        let next = map (fun t -> Option.value ~default:t
            (List.find_opt (fun u -> u.index = t.index) updated)) tasks in
        rounds next in
  let* tasks = rounds tasks in
  let rec finish = function
    | [] -> Ok ("m35 stream complete " ^ string_of_int (len tasks) ^ " repros\n")
    | t :: rest ->
        let r = fst (advance t) in
        let dir = root ^ "/_emit/m35/out/" ^ string_of_int t.index in
        let* () = io (Rust_leg.mkdir_one dir) in
        let cfg = { cfg with Legs.l_out = dir; l_name = "m35case" ^ string_of_int t.index } in
        let* wi = Result.map_error (fun e -> F_data e) (Legs.witness cfg r.Minimize.m_final) in
        let* () = result_ok t.target r wi in
        let* rust = read (dir ^ "/rp/run.jsonl") in
        let* js = read (dir ^ "/rp/seed.js.jsonl") in
        let* () = write (dir ^ "/rust.jsonl") rust in
        let* () = write (dir ^ "/js.jsonl") js in
        let meta = Journal.jobject [ field "index" (num t.index); field "oracle_sha" (str oracle_sha);
            field "fuel" (num (Minimize.size_of t.sample + 1)) ] in
        let* () = write (dir ^ "/walk.jsonl") (Repro.block (meta :: map round_json t.history)) in
        let* () = write (dir ^ "/repro.md") (rendered campaign t.index h t.row t.sample r wi oracle_sha) in
        prerr_endline ("m35 finished " ^ string_of_int t.index ^ " size "
            ^ string_of_int (Minimize.size_of t.sample) ^ " -> " ^ string_of_int (Minimize.size_of r.Minimize.m_final));
        finish rest in
  finish tasks

let job = function
  | [ _; "stream"; campaign; root; clone ] -> stream campaign root clone
  | [ _; "emit"; campaign; index; root; clone ] ->
      Option.fold ~none:(Error F_usage) ~some:(fun i ->
          if i < 0 then Error F_usage else emit campaign i root clone) (int_of_string_opt index)
  | [ _; "replay"; campaign; index; out; oracle_sha ] ->
      Option.fold ~none:(Error F_usage) ~some:(fun i ->
          if i < 0 then Error F_usage else replay campaign i out oracle_sha)
        (int_of_string_opt index)
  | [] | _ :: _ -> Error F_usage

let () = Result.fold ~ok:print_string ~error:(fun e ->
    prerr_endline (match e with
      | F_usage -> "usage: m35 emit <campaign> <index> <root> <clone> | replay <campaign> <index> <evidence-dir> <oracle-sha>"
      | F_data s -> "m35: " ^ s | F_io e -> "m35: " ^ Rust_leg.error_text e);
    exit 1) (job (Array.to_list Sys.argv))
