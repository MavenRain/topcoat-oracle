(* M33: the known-divergence allowlist.  The ENTRIES live here with their
   citations.  core/differ.ml keeps [type known] (core/differ.ml:169),
   [is_class] (:365) and the whole walk (:308-373 after M33), and this
   module only builds the closures the walk consumes.

   THE RUBRIC (M33 spec section 1, ruling R2).  A difference is Known under
   one of two heads and under no other.
   - K_upstream: an upstream document, source comment or issue number names
     the difference.
   - K_harness: the difference is a property of our legs or of our differ,
     and not of the target.
   A difference that is neither is a FINDING.  It keeps its Diverge verdict
   and feeds the M35 repro stream.

   THE NO-MASKING INVARIANT.  An entry excuses ONE channel of one row.  The
   walk reports the FIRST UNEXCUSED divergence (core/differ.ml:335-340), so
   an entry can never hide a later channel.  Both entries below excuse the
   class channel of rows whose MESSAGE channel still diverges, so the text
   difference is still reported.  BOTH entries REQUIRE that message
   difference in their own predicate, so the invariant is code and not
   prose.  The one exception is the frozen [seed ()] list, which keeps the
   M26 I1 predicate byte for byte.  Outside the tests it is used by
   bin/m27.ml alone, and it is pinned by test/test_differ.ml and
   test/test_known.ml.

   THE DECLARED FIELDS ARE LOAD-BEARING.  [allow ()] wraps every closure in
   [declared], which refuses any channel other than [e_channel] and any
   split outside [e_splits].  A closure that is broadened past the fields
   KNOWN.md renders therefore stops firing instead of quietly excusing more
   than the review document says.

   ZXLINT TRAP 2 (DESIGN.md:71-95, gates.sh:8).  A helper that reads a
   top-level constant is rejected and the trap fires cross module, so every
   list here is a function of (), as Differ.channels () is at
   core/differ.ml:310-313.

   NO FILE IS READ HERE.  bin/m33.ml does every read (ruling R5).  The
   render is a function of this source alone: no clock, no environment and
   no absolute path. *)

open Prelude

(* ---------- the rubric, the citation and the entry ---------- *)

(** Keep the two admissible reasons explicit so an entry cannot invent a third. *)
type head = K_upstream | K_harness

(* Which root a cited path is relative to.  R_repo is this repository,
   R_clone is the pinned topcoat clone.  A cite never carries an absolute
   path, so the render is the same on every machine. *)
type root = R_repo | R_clone

(* [c_quote] must occur inside the join of the lines [c_lo] to [c_hi] of
   the cited file.  m33 cite checks exactly that.  A range wider than
   twelve lines makes the check vacuous, so every range below is short. *)
type cite = {
  c_root : root;
  c_path : string;
  c_lo : int;
  c_hi : int;
  c_quote : string;
}

(** Keep review evidence beside its closure so both describe the same excuse. *)
type entry = {
  e_tag : Differ.tag;
  e_head : head;
  e_channel : Differ.channel;
  e_splits : Differ.split list;
  e_cite : cite;
  e_note : string list;
  e_known : Differ.known;
}

(* A documented difference that no corpus row reaches today.  It carries a
   citation and NO closure, so it excuses nothing.  A watch becomes an
   entry the day a row reaches it, and not before.  [w_head] names WHICH
   of the two heads documents it: three watches cite an upstream source
   comment, and two cite our own m23 driver probe, so the section cannot
   claim upstream for all five. *)
type watch = { w_name : string; w_head : head; w_cite : cite; w_note : string list }

(* A limit of the shipped EVIDENCE.  It is not a difference between the
   legs, so it has no channel, no split and no citation: it says what the
   archived campaign can and cannot answer.  [l_owner] names the milestone
   that recorded the limit. *)
type limit = { l_name : string; l_owner : string; l_note : string list }

(* A leg failure class.  It is not a divergence and never gets an entry.
   [x_owner] names the milestone that owns the loss. *)
type refused = {
  x_name : string;
  x_owner : string;
  x_cite : cite;
  x_note : string list;
}

(* ---------- the class predicates the entries share ---------- *)

(* The three classes driver-js/lib/classify.mjs:41-46 can produce from the
   static hint alone, after every prefix arm missed. *)
let js_fell_back (cs : Differ.cells) : bool =
  Differ.is_class cs.Differ.js Obs.P_expect
  || Differ.is_class cs.Differ.js Obs.P_expect_err
  || Differ.is_class cs.Differ.js Obs.P_other

(* Rust and the reference agree on one unwrap-family class.  This is the
   corroboration I2 needs on the THREE-party split, where rust is a
   compared party: without it the entry would excuse a class divergence in
   which the true class is itself in doubt. *)
let unwrap_family_agrees (cs : Differ.cells) : bool =
  (Differ.is_class cs.Differ.reference Obs.P_unwrap
  && Differ.is_class cs.Differ.rust Obs.P_unwrap)
  || Differ.is_class cs.Differ.reference Obs.P_unwrap_err
     && Differ.is_class cs.Differ.rust Obs.P_unwrap_err

(* The reference alone names one unwrap-family class.  This is the
   corroboration I2 uses on the TWO-party split.  A Signal_writing sample
   compares js against the reference and does not read the rust cell at
   all (core/differ.ml:36-38 and the BOUND at :82-84), so a two-party
   excuse must not be a function of that third cell: today shell/legs.ml
   fills it Present for every sample, and an Absent rust cell would
   otherwise delete the excuse without any source change. *)
let reference_unwrap_family (cs : Differ.cells) : bool =
  Differ.is_class cs.Differ.reference Obs.P_unwrap
  || Differ.is_class cs.Differ.reference Obs.P_unwrap_err

(* The js message differs from the reference message, byte for byte.  The
   surrogate throws the dotted text and the reference carries the Rust
   spelling with two colons, so the two texts cannot be equal on a row
   this entry may excuse.  When they ARE equal the classes disagree on
   identical bytes, which is a drift between driver-rs/harness.rs:224-237
   and its js port, and the row must keep its class divergence. *)
let js_message_differs (cs : Differ.cells) : bool =
  Differ.msg_differs cs.Differ.js cs.Differ.reference

(* The reference message differs from the rust message, byte for byte.
   This is the no-masking conjunct on the I1 side: the reference named a
   different panic class because it evaluated the other operand first, so
   its text is the other panic's text.  When the two texts are EQUAL the
   classes disagree on identical bytes, which is a drift in the
   leg-neutral mapping and not a known difference, and the row must keep
   its class divergence. *)
let ref_message_differs (cs : Differ.cells) : bool =
  Differ.msg_differs cs.Differ.reference cs.Differ.rust

(* ---------- I1, relocated from core/differ.ml in M33; the range it
   left now holds Differ.msg_differs ---------- *)

(* I1 (M26 spec 8.6): on case 10 the reference names the panic class
   expect_err because it evaluated the left operand first
   (core/interp.ml:244-251), while both legs classify by message prefix and
   fall back to the static hint (shell/driver.ml:598-602, the leg-neutral
   mapping; the js half of it is driver-js/lib/classify.mjs:41-46 and the
   rust half is driver-rs/harness.rs:224-237), which gives other.  Neither
   leg can do better with a static hint, so the class channel of that
   shape is excused, and only that channel. *)
let i1_known () : Differ.known =
  {
    Differ.tag = Differ.Tag "I1";
    Differ.applies =
      (fun ch s cs ->
        match ch with
        | Differ.Ch_class -> (
            match s with
            | Differ.Odd Differ.L_ref ->
                Differ.is_class cs.Differ.reference Obs.P_expect_err
                && Differ.is_class cs.Differ.rust Obs.P_other
                && Differ.is_class cs.Differ.js Obs.P_other
            | Differ.Odd Differ.L_rust | Differ.Odd Differ.L_js
            | Differ.All_three | Differ.Two_way ->
                false)
        | Differ.Ch_outcome | Differ.Ch_message | Differ.Ch_value
        | Differ.Ch_rendered | Differ.Ch_signals ->
            false);
  }

(* The I1 closure the ALLOWLIST ships.  It is [i1_known ()] with the
   no-masking conjunct added, so a row whose three panic messages are
   byte identical keeps its class divergence instead of being excused on
   the only channel that diverges.  [seed ()] keeps the frozen M26
   predicate without the conjunct, because the hand-derived 48-row M27
   table and the three m28 plant summaries are pinned against those exact
   bytes (M33 spec section 5.3).  The conjunct moves no corpus row: the
   straight, resume and planted censuses hold no known: verdict and no
   diverge on the value or the rendered channel, so I1 excuses no row of
   the corpus today. *)
let i1_allow_known () : Differ.known =
  {
    Differ.tag = Differ.Tag "I1";
    Differ.applies =
      (fun ch s cs ->
        (i1_known ()).Differ.applies ch s cs && ref_message_differs cs);
  }

(* ---------- I2, the js prefix miss ---------- *)

(* I2 (M33): driver-js/lib/classify.mjs is a PORT of driver-rs/harness.rs
   arm for arm, so its prefix arms carry the Rust spellings
   "called `Option::unwrap()`" with two colons
   (driver-js/lib/classify.mjs:25-39).  The surrogate throws the dotted
   text, "called `Option.unwrap()` on a `None` value", which matches no arm,
   so the js leg falls back to the static hint and reports expect,
   expect_err or other.  The classifier says so itself at
   driver-js/lib/classify.mjs:16-19.  This is a property of OUR js leg and
   not of the target, so the head is K_harness.

   The entry fires only when the parties that ARE compared corroborate the
   unwrap-family class: rust and the reference on the three-party split,
   the reference alone on the two-party split, where the rust cell is not
   read.  It excuses the class channel alone, and only when the js message
   differs from the reference message, so every row it excuses still
   diverges on the message channel and is reported there instead (M33 spec
   section 10.4).  A row whose message bytes are EQUAL keeps its class
   divergence: identical text under two class names is a port drift and
   not a known difference. *)
let i2_known () : Differ.known =
  {
    Differ.tag = Differ.Tag "I2";
    Differ.applies =
      (fun ch s cs ->
        match ch with
        | Differ.Ch_class -> (
            match s with
            | Differ.Odd Differ.L_js ->
                js_fell_back cs && unwrap_family_agrees cs
                && js_message_differs cs
            | Differ.Two_way ->
                js_fell_back cs && reference_unwrap_family cs
                && js_message_differs cs
            | Differ.Odd Differ.L_rust | Differ.Odd Differ.L_ref
            | Differ.All_three ->
                false)
        | Differ.Ch_outcome | Differ.Ch_message | Differ.Ch_value
        | Differ.Ch_rendered | Differ.Ch_signals ->
            false);
  }

(* ---------- the three lists ---------- *)

(** Pair the frozen I1 predicate with the evidence for the reference order. *)
let i1 () : entry =
  {
    e_tag = Differ.Tag "I1";
    e_head = K_harness;
    e_channel = Differ.Ch_class;
    e_splits = [ Differ.Odd Differ.L_ref ];
    e_cite =
      {
        c_root = R_repo;
        c_path = "core/interp.ml";
        c_lo = 244;
        c_hi = 251;
        c_quote = "Both operands always evaluate, left first";
      };
    e_note =
      [
        "The reference evaluates the left operand of a binop first, so it \
         names the class of the left panic.";
        "Both legs classify by message prefix and fall back to the static \
         hint, which gives other.";
        "Only the class channel is excused, and the entry fires only when \
         the reference message differs from the rust message, so the row \
         still reports its message divergence.";
      ];
    e_known = i1_allow_known ();
  }

(** Pair the I2 predicate with the classifier evidence for the prefix miss. *)
let i2 () : entry =
  {
    e_tag = Differ.Tag "I2";
    e_head = K_harness;
    e_channel = Differ.Ch_class;
    e_splits = [ Differ.Odd Differ.L_js; Differ.Two_way ];
    e_cite =
      {
        c_root = R_repo;
        c_path = "driver-js/lib/classify.mjs";
        c_lo = 16;
        c_hi = 19;
        c_quote = "matches no prefix arm and classifies as other";
      };
    e_note =
      [
        "The surrogate throws a dotted text, for example Option.unwrap(), \
         which matches no prefix arm of our js classifier.";
        "The js leg then falls back to the static hint and reports expect, \
         expect_err or other.";
        "The entry fires only when the compared parties corroborate the \
         unwrap-family class: rust and the reference on odd:js, the \
         reference alone on two_way, where the rust cell is not read.";
        "It also requires the js message to differ from the reference \
         message, so the message channel of every excused row still \
         diverges and is reported instead.";
      ];
    e_known = i2_known ();
  }

(* In tag order.  The order is the render order and the m33 cite order. *)
let entries () : entry list = [ i1 (); i2 () ]

(* [declared ch0 ss k] is [k] fenced by the fields KNOWN.md renders: it
   answers false on any channel other than [ch0] and on any split outside
   [ss], whatever the wrapped closure says.  The declarative e_channel and
   e_splits fields are therefore load-bearing, and a closure broadened
   past them stops firing rather than excusing rows the review document
   does not describe.  The equalities are Differ.channel_eq and
   Differ.split_eq, never a polymorphic compare. *)
let declared (ch0 : Differ.channel) (ss : Differ.split list)
    (k : Differ.known) : Differ.known =
  {
    Differ.tag = k.Differ.tag;
    Differ.applies =
      (fun ch s cs ->
        Differ.channel_eq ch ch0
        && fold (fun acc s0 -> acc || Differ.split_eq s s0) false ss
        && k.Differ.applies ch s cs);
  }

(* [fence e] is the one wrapper [allow ()] applies to every entry.  It is
   named so test/test_known.ml can pin the wrapper over the REAL entries:
   a test can substitute a broadened closure into an entry record and
   require the entry's own declared fields to hold it back. *)
let fence (e : entry) : Differ.known = declared e.e_channel e.e_splits e.e_known

(* The projection the walk consumes.  This is what shell/pipeline.ml,
   shell/legs.ml and every new vector pass to Differ.verdict. *)
let allow () : Differ.known list = map fence (entries ())

(* The FROZEN M26 seed list, [ i1 ].  bin/m27.ml and test/test_differ.ml
   keep it, because the hand-derived 48-row M27 table and the three m28
   plant summaries are pinned against this list and against no other
   (M33 spec section 5.3).  Growing [allow ()] never moves those pins.
   It keeps the M26 predicate [i1_known ()] and NOT the allowlist copy,
   so the M27 and m28 pins never move.  It is wrapped in [declared] with
   the same channel and split I1 renders: the wrapper is
   behaviour-identical today, because i1_known already answers false
   outside Ch_class and outside Odd L_ref, and it keeps the frozen list
   frozen if that closure is ever broadened. *)
let seed () : Differ.known list =
  [ declared Differ.Ch_class [ Differ.Odd Differ.L_ref ] (i1_known ()) ]

(* ---------- the watches: documented upstream, excusing nothing ---------- *)

(** Keep documented upstream differences visible until corpus evidence justifies an entry. *)
let watches () : watch list =
  [
    {
      w_name = "W-f64-display";
      w_head = K_upstream;
      w_cite =
        {
          c_root = R_clone;
          c_path = "crates/topcoat-runtime/browser/src/surrogate/f64.ts";
          c_lo = 40;
          c_hi = 51;
          c_quote = "five kinds of value (#237)";
        };
      w_note =
        [
          "Upstream issue #237 says Number.prototype.toString differs from \
           the Rust Display on five kinds of value, and the cited comment \
           lists four of them.";
          "The surrogate avoids toString and renders an f64 with its own \
           display() function, written to match Rust.";
          "No corpus row diverges on the value or the rendered channel today.";
        ];
    };
    {
      w_name = "W-string-order";
      w_head = K_upstream;
      w_cite =
        {
          c_root = R_clone;
          c_path = "crates/topcoat-runtime/browser/src/surrogate/string.ts";
          c_lo = 16;
          c_hi = 20;
          c_quote = "expression can disagree (#236)";
        };
      w_note =
        [
          "The surrogate orders two strings by code point, the way Rust does.";
          "JavaScript orders by UTF-16 code unit, so issue #236 patches the \
           comparison.";
          "No corpus row compares two strings above U+FFFF today.";
        ];
    };
    {
      w_name = "W-string-trim";
      w_head = K_upstream;
      w_cite =
        {
          c_root = R_clone;
          c_path = "crates/topcoat-runtime/browser/src/surrogate/string.ts";
          c_lo = 7;
          c_hi = 14;
          c_quote = "opposite of Rust (#238)";
        };
      w_note =
        [
          "Rust trims the Unicode White_Space set.";
          "JavaScript trims the ECMAScript set, so issue #238 patches trim.";
          "No corpus row trims a string today.";
        ];
    };
    {
      w_name = "W-nan-null";
      w_head = K_harness;
      w_cite =
        {
          c_root = R_repo;
          c_path = "research/m23-driver-probe.md";
          c_lo = 253;
          c_hi = 255;
          c_quote = "NaN serialises into the JS as `null`";
        };
      w_note =
        [
          "A NaN loses its payload bits on the way into the js leg.";
          "The m23 driver probe is our own record of the loss and refuses \
           to hide it, so the head is harness.";
          "No corpus row produces a NaN today.";
        ];
    };
    {
      w_name = "W-integral-f64";
      w_head = K_harness;
      w_cite =
        {
          c_root = R_repo;
          c_path = "research/m23-driver-probe.md";
          c_lo = 256;
          c_hi = 259;
          c_quote = "renders as `3` in the value channel";
        };
      w_note =
        [
          "An integral f64 renders one way in the value channel and another \
           way in the js.";
          "The two channels disagree on the text of one number by design, \
           which our own m23 driver probe records, so the head is harness.";
          "No corpus row diverges on the rendered channel today.";
        ];
    };
  ]

(* ---------- the leg failure classes, which get no entry ---------- *)

(** Keep leg losses visible with their owner without treating them as excuses. *)
let refusals () : refused list =
  [
    {
      x_name = "X-signal-arity";
      x_owner = "M34";
      x_cite =
        {
          c_root = R_repo;
          c_path = "driver-js/lib/signals.mjs";
          c_lo = 96;
          c_hi = 99;
          c_quote =
            "Pair every declared signal, preserving wire order and unused entries.";
        };
      x_note =
        [
          "The archived campaign-1 report records 3946 signal_arity leg \
           failures from the former positional pairing.";
          "M39 pairs each wire id with its own Debug UUID, including unused \
           bindings, so the current driver no longer reports signal_arity.";
          "The archived rows remain leg failures, not divergences; the \
           historical evidence is research/campaign-1/report.md.";
        ];
    };
    {
      x_name = "X-no-js";
      x_owner = "M34";
      x_cite =
        {
          c_root = R_repo;
          c_path = "driver-js/lib/line.mjs";
          c_lo = 331;
          c_hi = 338;
          c_quote = "\"reason\":\"no_js\"";
        };
      x_note =
        [
          "A line that carries no js hex is skipped by the js driver.";
          "The M39 500-row straight run still records 4 such skipped rows.";
        ];
    };
    {
      x_name = "X-js-syntax";
      x_owner = "M34";
      x_cite =
        {
          c_root = R_repo;
          c_path = "driver-js/worker.mjs";
          c_lo = 337;
          c_hi = 340;
          c_quote = "new Function(\"cx\", `return ${js};`)";
        };
      x_note =
        [
          "The js driver compiles one EXPRESSION: it wraps the decoded text \
           in return and hands it to new Function.";
          "A statement-shaped body therefore does not parse, and node \
           names the first offending token, while.";
          "A leg crash walks into Leg_failed and reaches no channel.";
          "The M39 500-row straight run records 47 such failures, \
           including 33 previously hidden by signal_arity.";
        ];
    };
    {
      x_name = "X-js-type";
      x_owner = "M34";
      x_cite =
        {
          c_root = R_clone;
          c_path = "crates/topcoat-runtime/browser/src/surrogate/signal.ts";
          c_lo = 35;
          c_hi = 37;
          c_quote = "(prev as F64).add(new F64(1))";
        };
      x_note =
        [
          "The surrogate increment() calls add on the previous signal \
           value after a cast to F64.";
          "A signal that holds another type has no add, so node throws the \
           TypeError prev.add is not a function.";
          "The historical 500-row straight run had one such failure at \
           case 105. M39 corrects its signal identities and it now agrees \
           with the reference.";
        ];
    };
  ]

(* ---------- the evidence limits, which excuse nothing ---------- *)

(** State what the archived campaign answers after M39, and what it does not. *)
let limits () : limit list =
  [
    {
      l_name = "L-campaign-1-historical";
      l_owner = "M39";
      l_note =
        [
          "After M39 the research/campaign-1 evidence is HISTORICAL: its \
           provenance.json predates two producers of this slice, \
           archive_sources.py and driver-js/lib/signals.mjs.";
          "m35_verdict.py run and m35_verdict.py publish therefore refuse \
           with incomplete source inventory, which names the missing and \
           the extra paths, until a new campaign records the M39 producers.";
          "m35_verdict.py check reads the historical branch, which verifies \
           the archived producer bytes against research/archive-v1, and \
           stays green on this evidence.";
        ];
    };
  ]

(* ---------- the render (ruling R4) ---------- *)

(** Give both admissible reasons stable spellings in the review document. *)
let head_text (h : head) : string =
  match h with K_upstream -> "upstream" | K_harness -> "harness"

(** Name the source root without leaking a machine-specific absolute path. *)
let root_text (r : root) : string =
  match r with R_repo -> "repo" | R_clone -> "clone"

(** Include the range so reviewers can locate exactly the evidence the CLI checks. *)
let cite_text (c : cite) : string =
  root_text c.c_root ^ " " ^ c.c_path ^ ":" ^ nat_to_string c.c_lo ^ "-"
  ^ nat_to_string c.c_hi

(** Share field formatting so all three review lists use the same layout. *)
let field (k : string) (v : string) : string = "- " ^ k ^ ": " ^ v ^ "\n"

(* One block per row.  The leading newline is the blank line before the
   heading, so the document never ends in a blank line. *)
let block (name : string) (fields : string list) : string =
  "\n### " ^ name ^ "\n\n" ^ concat fields

(* The note sentences are joined with two spaces, the house rule, and are
   NOT wrapped: a wrap would be a second layout rule to derive by hand. *)
let entry_block (e : entry) : string =
  block (Differ.tag_text e.e_tag)
    [
      field "head" (head_text e.e_head);
      field "channel" (Differ.channel_name e.e_channel);
      field "splits" (joined ", " (map Differ.split_text e.e_splits));
      field "cite" (cite_text e.e_cite);
      field "quote" e.e_cite.c_quote;
      field "note" (joined "  " e.e_note);
    ]

(** Show the evidence for a watch without presenting it as an active excuse. *)
let watch_block (w : watch) : string =
  block w.w_name
    [
      field "head" (head_text w.w_head);
      field "cite" (cite_text w.w_cite);
      field "quote" w.w_cite.c_quote;
      field "note" (joined "  " w.w_note);
    ]

(** Show an evidence limit with its owner and no citation to open. *)
let limit_block (l : limit) : string =
  block l.l_name
    [ field "owner" l.l_owner; field "note" (joined "  " l.l_note) ]

(** Show who owns each leg loss beside the evidence for its refusal. *)
let refused_block (x : refused) : string =
  block x.x_name
    [
      field "owner" x.x_owner;
      field "cite" (cite_text x.x_cite);
      field "quote" x.x_cite.c_quote;
      field "note" (joined "  " x.x_note);
    ]

(** State the review rules before the entries so readers can assess each excuse. *)
let intro () : string =
  concat
    [
      "# Known divergences\n";
      "\n";
      "Rendered by `m33 render` from `core/known.ml`.  Do not edit this file by\n";
      "hand.  The m33 gate compares this file with the render, byte for byte.\n";
      "\n";
      "An entry excuses ONE channel of one row.  The walk reports the first\n";
      "UNEXCUSED divergence, so an entry never masks a later channel.\n";
      "\n";
      "Two heads.  upstream: an upstream document, comment or issue names the\n";
      "difference.  harness: the difference is a property of our legs or of our\n";
      "differ, and not of the target.\n";
      "\n";
      "## Entries\n";
    ]

(** Derive the whole review document from the lists so it cannot drift independently. *)
let render () : string =
  concat
    [
      intro ();
      concat (map entry_block (entries ()));
      "\n## Documented, not excused today\n";
      "\n";
      "Each row below names the head that documents it: upstream for a source\n";
      "comment or issue in the target, harness for our own driver probe.  No\n";
      "corpus row reaches any of them today, so each carries no entry and\n";
      "excuses nothing.\n";
      concat (map watch_block (watches ()));
      "\n## Not on the allowlist\n";
      "\n";
      "A leg failure is not a divergence.  These ";
      nat_to_string (len (refusals ()));
      " classes stay leg_fail\n";
      "verdicts.  Each row names the milestone that owns the loss.  Its note\n";
      "identifies the historical archive or current run behind each count.\n";
      concat (map refused_block (refusals ()));
      "\n## Evidence limits\n";
      "\n";
      "A limit is a property of the shipped EVIDENCE and not of a\n";
      "divergence.  It excuses no row, so it names no channel and opens no\n";
      "citation.  Each row names the milestone that recorded it.\n";
      concat (map limit_block (limits ()));
    ]

(* ---------- what m33 cite needs, without reading a file ---------- *)

(* The rows m33 cite checks, in render order: the entries, then the
   watches, then the refusals.  The shell reads the file;  core/ only says
   which name, which root, which range and which quote. *)
let cite_rows () : (string * cite) list =
  append
    (map (fun e -> (Differ.tag_text e.e_tag, e.e_cite)) (entries ()))
    (append
       (map (fun w -> (w.w_name, w.w_cite)) (watches ()))
       (map (fun x -> (x.x_name, x.x_cite)) (refusals ())))

(* The one line m33 cite prints per row that checks out. *)
let ok_line (name : string) (c : cite) : string =
  "ok " ^ name ^ " " ^ c.c_path ^ ":" ^ nat_to_string c.c_lo ^ "-"
  ^ nat_to_string c.c_hi ^ "\n"
