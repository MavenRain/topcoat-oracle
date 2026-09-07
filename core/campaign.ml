(** Pure M34 campaign analysis.  The shell supplies one regenerated construct
    signature per journal row.  Grouping changes presentation only: every
    unexcused divergence index remains in exactly one group. *)

type group = {
  g_mode : string;
  g_verdict : string;
  g_signature : string;
  g_indices : int list;
  g_first : int;
  g_count : int;
  g_min_size : int;
}

type report = {
  r_total : int;
  r_read_only : int;
  r_signal_writing : int;
  r_tally : Journal.tally;
  r_groups : group list;
}

type error =
  | E_signatures of int * int
  | E_index of int * int
  | E_mode of int * string
  | E_size of int
  | E_signature of int
  | E_head of int * string
  | E_verdict of int * string

(** Counts and positions are nonnegative; rejected negative row values are
    described without passing them to the natural-number renderer. *)
let error_text (e : error) : string =
  match e with
  | E_signatures (want, got) ->
      "expected " ^ Prelude.nat_to_string want ^ " construct signatures, got "
      ^ Prelude.nat_to_string got
  | E_index (want, _) ->
      "row at position " ^ Prelude.nat_to_string want
      ^ " does not carry its expected contiguous sample index"
  | E_mode (i, mode) ->
      "sample " ^ Prelude.nat_to_string i ^ " has an unknown mode "
      ^ Journal.jstring mode
  | E_size i -> "sample " ^ Prelude.nat_to_string i ^ " has a negative size"
  | E_signature i ->
      "sample " ^ Prelude.nat_to_string i ^ " has an empty construct signature"
  | E_head (i, head) ->
      "sample " ^ Prelude.nat_to_string i ^ " has an unknown verdict head "
      ^ Journal.jstring head
  | E_verdict (i, verdict) ->
      "sample " ^ Prelude.nat_to_string i ^ " has an invalid verdict "
      ^ Journal.jstring verdict

let member (text : string) (texts : string list) : bool =
  Prelude.fold (fun found s -> found || String.equal text s) false texts

(** Read prefix bytes through the total accessor.  A payload must be nonempty;
    its contents, including colons in driver failure reasons, stay opaque. *)
let has_payload (prefix : string) (text : string) : bool =
  let rec go (k : int) : bool =
    Option.fold
      ~none:(String.length text > k)
      ~some:(fun p ->
        Option.fold ~none:false
          ~some:(fun t -> String.equal p t && go (k + 1))
          (Prelude.byte_at text k))
      (Prelude.byte_at prefix k)
  in
  go 0

(** The channel and split encoders are the authority for divergence grammar.
    Mode compatibility also follows Differ: three parties permit an odd leg
    or three distinct values, and two parties permit only Two_way. *)
let valid_diverge (mode : string) (text : string) : bool =
  let splits =
    if String.equal mode "read_only" then
      [ Differ.Odd Differ.L_rust; Differ.Odd Differ.L_js;
        Differ.Odd Differ.L_ref; Differ.All_three ]
    else [ Differ.Two_way ]
  in
  Prelude.fold
    (fun found channel ->
      found
      || Prelude.fold
           (fun got split ->
             got
             || String.equal text
                  (Differ.verdict_text (Differ.Diverge (channel, split))))
           false splits)
    false (Differ.channels ())

let valid_verdict (mode : string) (text : string) : bool =
  member text [ "agree"; "dropped"; "no_line" ]
  || valid_diverge mode text
  || has_payload "known:" text
  || has_payload "batch_fail:" text
  || Prelude.fold
       (fun found leg ->
         found || has_payload ("leg_fail:" ^ Differ.leg_name leg ^ ":") text)
       false [ Differ.L_rust; Differ.L_js; Differ.L_ref ]

(** The analyzer accepts no unknown tally bucket.  A newly added verdict must
    receive an explicit grammar here before a campaign can report it. *)
let validate (want : int) (row : Journal.line) (signature : string) :
    (unit, error) result =
  let head = Journal.head row.Journal.jl_verdict in
  match () with
  | () when not (Int.equal row.Journal.jl_i want) ->
      Error (E_index (want, row.Journal.jl_i))
  | () when not (member row.Journal.jl_mode [ "read_only"; "signal_writing" ]) ->
      Error (E_mode (want, row.Journal.jl_mode))
  | () when row.Journal.jl_size < 0 -> Error (E_size want)
  | () when String.equal signature "" -> Error (E_signature want)
  | () when
      not
        (member head
           [ "agree"; "known"; "diverge"; "leg_fail"; "dropped";
             "no_line"; "batch_fail" ]) ->
      Error (E_head (want, head))
  | () when not (valid_verdict row.Journal.jl_mode row.Journal.jl_verdict) ->
      Error (E_verdict (want, row.Journal.jl_verdict))
  | () -> Ok ()

let same_group (row : Journal.line) (signature : string) (g : group) : bool =
  String.equal row.Journal.jl_mode g.g_mode
  && String.equal row.Journal.jl_verdict g.g_verdict
  && String.equal signature g.g_signature

(** During collection member indices are reversed, avoiding repeated appends
    for large groups.  [analyze] reverses each group once before returning. *)
let rec add_group (row : Journal.line) (signature : string)
    (groups : group list) : group list =
  match groups with
  | [] ->
      [ { g_mode = row.Journal.jl_mode; g_verdict = row.Journal.jl_verdict;
          g_signature = signature; g_indices = [ row.Journal.jl_i ];
          g_first = row.Journal.jl_i; g_count = 1;
          g_min_size = row.Journal.jl_size } ]
  | g :: rest ->
      (match () with
      | () when same_group row signature g ->
          { g with g_indices = row.Journal.jl_i :: g.g_indices;
                   g_count = g.g_count + 1;
                   g_min_size =
                     (if row.Journal.jl_size < g.g_min_size then
                        row.Journal.jl_size
                      else g.g_min_size) }
          :: rest
      | () -> g :: add_group row signature rest)

(** Signature alignment is checked before traversal, and row indices are
    checked even when the caller obtained its rows outside the journal codec.
    Group order is first appearance, and representatives never change when a
    later member is smaller.  Empty input is valid analysis; campaign size
    policy belongs to the shell command. *)
let analyze (rows : Journal.line list) (signatures : string list) :
    (report, error) result =
  let total = Prelude.len rows in
  let supplied = Prelude.len signatures in
  let rec go (i : int) (ro : int) (sw : int) (groups : group list)
      (rest : Journal.line list) (sigs : string list) : (report, error) result =
    match rest with
    | [] ->
        (match sigs with
        | [] ->
            Ok { r_total = total; r_read_only = ro; r_signal_writing = sw;
                 r_tally = Journal.tally rows;
                 r_groups =
                   Prelude.map
                     (fun g -> { g with g_indices = Prelude.rev g.g_indices })
                     groups }
        | _ :: _ -> Error (E_signatures (total, supplied)))
    | row :: more ->
        (match sigs with
        | [] -> Error (E_signatures (total, supplied))
        | signature :: next ->
            Result.bind (validate i row signature) (fun () ->
                let is_ro = String.equal row.Journal.jl_mode "read_only" in
                let next_groups =
                  if String.equal (Journal.head row.Journal.jl_verdict) "diverge"
                  then add_group row signature groups
                  else groups
                in
                go (i + 1) (ro + if is_ro then 1 else 0)
                  (sw + if is_ro then 0 else 1) next_groups more next))
  in
  if not (Int.equal total supplied) then Error (E_signatures (total, supplied))
  else go 0 0 0 [] rows signatures

let adjudicated (r : report) : int =
  r.r_tally.Journal.t_agree + r.r_tally.Journal.t_known
  + r.r_tally.Journal.t_diverge

let losses (r : report) : int =
  r.r_tally.Journal.t_leg_fail + r.r_tally.Journal.t_dropped
  + r.r_tally.Journal.t_no_line + r.r_tally.Journal.t_batch_fail

(** Inline HTML does not suppress GFM parsing.  Quote Markdown punctuation,
    automatic-link separators, table delimiters and line breaks as well as
    HTML syntax, so a reason or signature remains literal report text. *)
let code (text : string) : string =
  let rec go (i : int) (acc : string) : string =
    Option.fold ~none:("<code>" ^ acc ^ "</code>")
      ~some:(fun byte ->
        let quoted =
          Option.fold ~none:byte ~some:(fun escaped -> escaped)
            (Prelude.assoc_opt String.equal byte
               [ ("&", "&amp;"); ("<", "&lt;"); (">", "&gt;");
                 ("|", "&#124;"); ("`", "&#96;"); ("\n", "&#10;");
                 ("\r", "&#13;"); ("\\", "&#92;"); ("[", "&#91;");
                 ("]", "&#93;"); ("*", "&#42;"); ("_", "&#95;");
                 ("~", "&#126;"); ("!", "&#33;"); ("@", "&#64;");
                 (":", "&#58;"); (".", "&#46;") ])
        in
        go (i + 1) (acc ^ quoted))
      (Prelude.byte_at text i)
  in
  go 0 ""

let count_text (r : report) : string =
  let t = r.r_tally in
  "m34 agree " ^ Prelude.nat_to_string t.Journal.t_agree ^ " known "
  ^ Prelude.nat_to_string t.Journal.t_known ^ " diverge "
  ^ Prelude.nat_to_string t.Journal.t_diverge ^ " leg_fail "
  ^ Prelude.nat_to_string t.Journal.t_leg_fail ^ " dropped "
  ^ Prelude.nat_to_string t.Journal.t_dropped ^ " no_line "
  ^ Prelude.nat_to_string t.Journal.t_no_line ^ " batch_fail "
  ^ Prelude.nat_to_string t.Journal.t_batch_fail ^ " other "
  ^ Prelude.nat_to_string t.Journal.t_other ^ "\n"

let group_row (seed : int) (g : group) : string =
  "| " ^ code g.g_mode ^ " | " ^ code g.g_verdict ^ " | "
  ^ Prelude.nat_to_string g.g_count ^ " | "
  ^ code (Prelude.nat_to_string seed ^ ":" ^ Prelude.nat_to_string g.g_first)
  ^ " | " ^ Prelude.nat_to_string g.g_min_size ^ " | "
  ^ code (Prelude.joined "," (Prelude.map Prelude.nat_to_string g.g_indices))
  ^ " | " ^ code g.g_signature ^ " |\n"

(** A function of the journal header and analysis alone, with no path, clock
    or process metadata.  Histograms retain complete verdict texts, so all
    driver loss reasons and Known tags remain visible. *)
let markdown (header : Journal.header) (r : report) : string =
  Prelude.concat
    [ "# Campaign 1\n\n";
      "Seed " ^ code (Prelude.nat_to_string header.Journal.jh_seed)
      ^ ", batch " ^ code (Prelude.nat_to_string header.Journal.jh_batch)
      ^ ", plant " ^ code header.Journal.jh_plant ^ ", topcoat "
      ^ code header.Journal.jh_topcoat ^ ".\n\n";
      "Counts include every attempted sample. Adjudicated samples have an "
      ^ "agree, known or diverge verdict. Losses received no complete "
      ^ "comparison.\n\n```text\n";
      "m34 samples " ^ Prelude.nat_to_string r.r_total ^ " read_only "
      ^ Prelude.nat_to_string r.r_read_only ^ " signal_writing "
      ^ Prelude.nat_to_string r.r_signal_writing ^ "\n";
      "m34 adjudicated " ^ Prelude.nat_to_string (adjudicated r) ^ " losses "
      ^ Prelude.nat_to_string (losses r) ^ "\n";
      count_text r;
      "m34 groups " ^ Prelude.nat_to_string (Prelude.len r.r_groups)
      ^ " members " ^ Prelude.nat_to_string r.r_tally.Journal.t_diverge
      ^ "\n```\n\n";
      "## Verdict census\n\n";
      "Every non-agree verdict is listed by its complete text.\n\n";
      "| Verdict | Samples |\n| --- | ---: |\n";
      "| <code>agree</code> | " ^ Prelude.nat_to_string r.r_tally.Journal.t_agree
      ^ " |\n";
      Prelude.concat
        (Prelude.map
           (fun entry ->
             "| " ^ code (fst entry) ^ " | "
             ^ Prelude.nat_to_string (snd entry) ^ " |\n")
           (Journal.sort_texts r.r_tally.Journal.t_texts));
      "\n## Unexcused divergence groups\n\n";
      "The key is mode, complete verdict and construct signature. Groups "
      ^ "and representatives follow first appearance. All member indices "
      ^ "are retained for replay; a smaller later member does not replace "
      ^ "the first representative. Known verdicts form no candidate group.\n\n";
      "| Mode | Verdict | Samples | Representative seed:index | Minimum size "
      ^ "| Member indices | Construct signature |\n";
      "| --- | --- | ---: | --- | ---: | --- | --- |\n";
      Prelude.concat (Prelude.map (group_row header.Journal.jh_seed) r.r_groups);
      (if Int.equal (Prelude.len r.r_groups) 0 then
         "\nNo unexcused divergence groups.\n"
       else "");
    ]
