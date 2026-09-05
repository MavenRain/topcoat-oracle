(* M27 verdict over the three leg observations (DESIGN.md M27).  One
   pure module: the verdict ADT, the six channel projections, the split
   rule, the two-way rule, the Leg_fail precedence, the Known walk, one
   known entry and the encoders.  It depends on Prelude, Obs and
   Taxonomy and on nothing else.  No float, no exception, no IO and no
   mutation.

   There is no .mli in this tree, so the two entry points are recorded
   here:

     val verdict : Taxonomy.mode -> known list -> cells -> verdict
     val excused : Taxonomy.mode -> known list -> cells -> tag list

   [excused] is exported with a stated reason.  The CLI summary counts
   the cases whose walk excused a channel, and the verdict alone cannot
   say: case 10 is a Diverge that excused a channel first.  Recomputing
   the walk in the shell would duplicate the rule.

   CHANNEL ORDER: outcome, class, message, value, rendered, signals.
   Ch_outcome comes FIRST so a kind mismatch is reported once and never
   again.  When two legs disagree on the kind of an outcome, the class,
   the message and the value channels are consequences of that one
   fact, and reporting them again would file three repros for one
   difference.

   THE VACUITY RULE: a channel is compared ONLY when every party
   projects Some on it.  Otherwise the channel is vacuously agreeing,
   because the kind mismatch that made a party project None was already
   reported on Ch_outcome.  A panic against a value gives exactly one
   verdict, on the outcome channel.

   THE TWO-WAY RULE: a Read_only sample has three parties, rust, js and
   reference.  A Signal_writing sample has TWO, js and reference.
   DESIGN.md:67-69 fixes the arity: "read-only (three-way diff) and
   signal-writing event handlers (two-way: js leg vs reference; the
   server panics on those by design)".  The rust cell of a
   Signal_writing sample is not read at all, and its absence is not a
   Leg_fail, because that cell is not a party.

   THE Leg_fail PRECEDENCE: before any channel is projected, an Absent
   PARTY cell gives Leg_fail (leg, reason) for the FIRST absent party
   in the order rust, js, reference.  The reason text is the shell's
   own bytes and travels through unparsed.

   THE KNOWN WALK: the walk collects the divergent channels in channel
   order, then classifies.  The verdict is the FIRST UNEXCUSED Diverge.
   If every divergent channel was excused, the verdict is the first
   excused channel's Known tag.  If no channel diverges, the verdict is
   Agree.  So a Known entry NEVER masks a later unexcused channel: case
   10 excuses its class channel under Tag "I1" and still reports its
   message divergence.

   THE REFINEMENT MAP to model/ (M27 spec section 4).  core/ cannot
   depend on model/, so this map is DOCUMENTED here and NO function
   implements it in M27.  M32, the correspondence gate, owns that
   direction, and model/ stays untouched.
   - Agree maps to model/state.ml V_agree, frame edge Judge_agree into
     the terminal Dropped_agree.
   - Diverge (_, _) maps to V_diverge, the diverge arm into
     Minimizing_hi.
   - Known _ maps to V_known, frame edge Judge_known into the terminal
     Dropped_known.
   - Leg_fail (_, _) maps to V_none, with no frame edge today.
     model/frame.ml:77-80 has no transition for a leg that produced no
     observation, because the three judge arms all start from a world
     in which the legs ran.  V_none is the initial verdict of
     model/state.ml:34, so a Leg_fail case is a world that never
     reaches a judge edge, which is what a missing leg result means.
     Whether M32 needs its own edge for it is an M32 question.

   CAP, BOUND AND DROP INVENTORY, in the style of shell/cover.ml.
   - channels: six, one fixed order.  BOUND.  [channels ()] below.
     Adding a channel is a table edit in the gate's expected heredoc
     and a new group 2 unit vector, both by hand.
   - comparison order: outcome first.  BOUND, load bearing.  The
     vacuity rule leans on it: a kind mismatch is reported once, on the
     first channel, and the later channels go vacuous for the same
     reason.
   - parties: 3 on Read_only, 2 on Signal_writing.  BOUND.
     DESIGN.md:67-69 and finding I3.  The rust cell of a
     Signal_writing sample is not read.
   - verdicts per case: exactly one.  BOUND.  The first unexcused
     divergence.  Case 5 diverges on class AND message and reports
     class.  A per-channel report is M31's shape, not M27's.
   - known entries: one, [ i1 ].  BOUND.  [known_seed ()] below.  [] is
     the no-allowlist input and every seed vector is tested both ways.
     M33 grows the list from a file with upstream citations.
   - printed rows: 48.  BOUND.  Four per case, in bin/m27.ml.  A count
     that is not 48 is a named verdict check.
   - seed table size: 12.  BOUND.  Hand-derived in the gate.  Growing
     it means recomputing that table by hand.
   - Leg_fail order: rust, js, reference.  BOUND.  Fixed so two absent
     parties give one stable verdict.  The order is the column order of
     the M26 table.
   - signal order: NOT compared.  DELIBERATE.  Three harnesses order an
     unordered map three ways, so an order difference is a property of
     the harnesses and not of the target semantics.  Comparing it would
     file repros against ourselves.
   - duplicate signal ids: not assumed absent.  BOUND.  The subset
     check runs both ways, so a repeated id cannot fake an agreement.
     The failure direction is the other one.  A repeated id with two
     values makes signals_eq report a difference between identical
     cells, a conservative false divergence that no leg produces
     today.
   - non-party absence: ignored.  STRUCTURAL.  A rust Absent on a
     Signal_writing sample is not a Leg_fail, because that cell is not
     a party.
   - rust and reference Absent: allowed, never produced today.
     STRUCTURAL.  The type carries it for M36's browser leg and for a
     rust capture line that fails to decode.  No M27 path builds one.
   - Absent reason text: the shell's, verbatim.  STRUCTURAL.
     Js_leg.cell composes it (shell/js_leg.ml:291-299) and core/ never
     invents or parses it.
   - string equality: String.equal, direct.  STRUCTURAL.  The ZxCaml
     subset admits it, so nothing is injected from the shell.
   - int equality: =, on signal ids and list lengths only.  STRUCTURAL.
     No polymorphic = or compare touches an observation, a value or a
     string.
   - case 10 class: excused by Tag "I1".  INVARIANT, recorded.  Finding
     I1.  Excusing it does NOT hide the message divergence, which is
     the reported verdict.
   - D1, D2, D4: Diverge verdicts.  STRUCTURAL.  Cases 5, 1, and 8 with
     10.  They are the pipeline's output and are never smoothed.
   - D3: Agree by the two-way rule.  INVARIANT.  Case 7, by design.
   - interpreter fuel: 10000.  CAP, real, inherited from
     Ref_leg.default_config.  Case 11 spends it on purpose and the
     result is O_no_terminate, which is an observation.
   - node timeouts: 2000 ms per case, 30000 ms startup.  CAP, real,
     inherited.  The js leg's own defaults, unchanged by M27.
   - orchestration duplication: bin/m27.ml copies bin/m26.ml.
     RESIDUAL R5.  Recorded, not fixed.  M31 hoists the shared part.
   - dropped samples: none.  DROP.  M27 reads a fixed twelve-case
     capture.  Nothing is dropped, truncated or wrapped here. *)

open Prelude

(* Which leg produced a cell. *)
type leg = L_rust | L_js | L_ref

(* The six comparison channels, IN COMPARISON ORDER. *)
type channel =
  | Ch_outcome
  | Ch_class
  | Ch_message
  | Ch_value
  | Ch_rendered
  | Ch_signals

(* How the parties split on a divergent channel.  Odd l: l differs from
   the other two, which agree.  All_three: three distinct cells.
   Two_way: the two parties of a Signal_writing sample differ. *)
type split = Odd of leg | All_three | Two_way

type tag = Tag of string

(* Absent carries the leg's own reason text, composed by the shell.
   core/ never invents that text. *)
type cell = Present of Obs.observation | Absent of string

(* [ref] is a keyword, so the reference field is [reference]. *)
type cells = { rust : cell; js : cell; reference : cell }

(* A known-divergence entry.  [applies] is a closure in a record, the
   Interp.ops precedent (shell/ops.ml, core/interp.ml:28-50). *)
type known = { tag : tag; applies : channel -> split -> cells -> bool }

type verdict =
  | Agree
  | Diverge of channel * split
  | Known of tag
  | Leg_fail of leg * string

(* ---------- the channel projections ---------- *)

(* Hand-written letters that happen to match the first byte of
   Obs.encode_outcome.  The differ never slices an encoding. *)
let kind_letter (o : Obs.outcome) : string =
  match o with
  | Obs.O_value _ -> "V"
  | Obs.O_panic (_, _) -> "P"
  | Obs.O_no_terminate -> "T"

let class_of (o : Obs.outcome) : string option =
  match o with
  | Obs.O_panic (p, _) -> Some (Obs.encode_panic_class p)
  | Obs.O_value _ -> None
  | Obs.O_no_terminate -> None

let message_of (o : Obs.outcome) : string option =
  match o with
  | Obs.O_panic (_, m) -> Some m
  | Obs.O_value _ -> None
  | Obs.O_no_terminate -> None

(* Obs.encode_value is INJECTIVE (core/obs.ml:7-10), so String.equal on
   it is exact value equality. *)
let value_of (o : Obs.outcome) : string option =
  match o with
  | Obs.O_value v -> Some (Obs.encode_value v)
  | Obs.O_panic (_, _) -> None
  | Obs.O_no_terminate -> None

let project (c : channel) (o : Obs.observation) : string option =
  match c with
  | Ch_outcome -> Some (kind_letter o.Obs.outcome)
  | Ch_class -> class_of o.Obs.outcome
  | Ch_message -> message_of o.Obs.outcome
  | Ch_value -> value_of o.Obs.outcome
  | Ch_rendered -> Some o.Obs.rendered
  | Ch_signals -> Some (Obs.encode_signals o.Obs.signals)

(* Presence, which the vacuity rule tests.  ~none:false is a constant,
   which the eager Option.fold rule requires. *)
let present (c : channel) (o : Obs.observation) : bool =
  Option.fold ~none:false ~some:(fun _ -> true) (project c o)

(* ---------- channel equality, and the signals rule ---------- *)

let proj_eq (c : channel) (a : Obs.observation) (b : Obs.observation) : bool =
  Option.fold ~none:false
    ~some:(fun x ->
      Option.fold ~none:false
        ~some:(fun y -> String.equal x y)
        (project c b))
    (project c a)

(* The ids are ints, so the key equality is = on ints.  That = and the
   length = of signals_eq are the only two in this module, and neither
   of them is applied to a string, a value or an observation.  The
   inventory at :112-114 states the same bound. *)
let signal_subset (xs : (int * Obs.value) list) (ys : (int * Obs.value) list) :
    bool =
  fold
    (fun ok kv ->
      ok
      && Option.fold ~none:false
           ~some:(fun v ->
             String.equal (Obs.encode_value v) (Obs.encode_value (snd kv)))
           (assoc_opt (fun a b -> a = b) (fst kv) ys))
    true xs

(* The subset check runs BOTH ways.  One way plus equal lengths is not
   enough when a party repeats an id.  Ids do not repeat today and this
   guard does not lean on that. *)
let signals_eq (a : Obs.observation) (b : Obs.observation) : bool =
  len a.Obs.signals = len b.Obs.signals
  && signal_subset a.Obs.signals b.Obs.signals
  && signal_subset b.Obs.signals a.Obs.signals

let chan_eq (c : channel) (a : Obs.observation) (b : Obs.observation) : bool =
  match c with
  | Ch_signals -> signals_eq a b
  | Ch_outcome | Ch_class | Ch_message | Ch_value | Ch_rendered ->
      proj_eq c a b

(* ---------- the parties, and the split ---------- *)

(* [rj], [rf] and [jf] are the pairwise agreements of the three parties
   on one channel.  Equality on the projections is an equivalence, and
   chan_eq on Ch_signals is one only while the signal ids are unique, so
   the three rows that are missing here cannot occur.  A repeated id with
   two values breaks the reflexivity of signals_eq, and three identical
   cells then fall to All_three, which is conservative and which no seed
   case reaches. *)
let three_split (rj : bool) (rf : bool) (jf : bool) : split option =
  match () with
  | () when rj && rf && jf -> None
  | () when rj -> Some (Odd L_ref)
  | () when rf -> Some (Odd L_js)
  | () when jf -> Some (Odd L_rust)
  | () -> Some All_three

(* The party order is positional: [a] is rust, [b] is js and [c] is the
   reference, which is what makes Odd name the right leg. *)
let three_way (ch : channel) (a : Obs.observation) (b : Obs.observation)
    (c : Obs.observation) : split option =
  match () with
  | () when not (present ch a) -> None
  | () when not (present ch b) -> None
  | () when not (present ch c) -> None
  | () -> three_split (chan_eq ch a b) (chan_eq ch a c) (chan_eq ch b c)

(* Two parties: equal is agreement, else Two_way. *)
let two_way (ch : channel) (a : Obs.observation) (b : Obs.observation) :
    split option =
  match () with
  | () when not (present ch a) -> None
  | () when not (present ch b) -> None
  | () when chan_eq ch a b -> None
  | () -> Some Two_way

(* None when some party is not present on [ch], None when the parties
   agree, Some split otherwise.  [c3] is the third party, absent on
   Signal_writing.  It is an option ARGUMENT, never an option-typed
   record field, so the sum-type shape rule is kept. *)
let channel_split (m : Taxonomy.mode) (a : Obs.observation)
    (b : Obs.observation) (c3 : Obs.observation option) (ch : channel) :
    split option =
  match m with
  | Taxonomy.Read_only ->
      Option.fold ~none:None ~some:(fun c -> three_way ch a b c) c3
  | Taxonomy.Signal_writing -> two_way ch a b

(* ---------- the Known walk ---------- *)

(* A FUNCTION of (), not a top-level constant: zxlint trap2 rejects a
   helper that reads a top-level constant and it fires cross-module. *)
let channels () =
  [ Ch_outcome; Ch_class; Ch_message; Ch_value; Ch_rendered; Ch_signals ]

let divergences (m : Taxonomy.mode) (a : Obs.observation)
    (b : Obs.observation) (c3 : Obs.observation option) :
    (channel * split) list =
  fold
    (fun acc ch ->
      Option.fold ~none:acc
        ~some:(fun s -> append acc [ (ch, s) ])
        (channel_split m a b c3 ch))
    [] (channels ())

let excuse (ks : known list) (ch : channel) (s : split) (cs : cells) :
    tag option =
  fold
    (fun acc k ->
      Option.fold
        ~none:(if k.applies ch s cs then Some k.tag else None)
        ~some:(fun t -> Some t)
        acc)
    None ks

(* The verdict is the FIRST UNEXCUSED Diverge.  If every divergent
   channel was excused, it is the first excused channel's Known tag.
   If no channel diverges, it is Agree.  A pair is taken apart with fst
   and snd because a tuple pattern nested in a cons pattern is outside
   the ZxCaml subset (core/prelude.ml:79-82). *)
let rec classify (ks : known list) (cs : cells) (ds : (channel * split) list)
    (acc : tag option) : verdict =
  match ds with
  | [] -> Option.fold ~none:Agree ~some:(fun t -> Known t) acc
  | d :: rest ->
      Option.fold
        ~none:(Diverge (fst d, snd d))
        ~some:(fun t ->
          classify ks cs rest
            (Option.fold ~none:(Some t) ~some:(fun t0 -> Some t0) acc))
        (excuse ks (fst d) (snd d) cs)

(* The same fold with no early stop, so the tags come out in channel
   order. *)
let excused_tags (ks : known list) (cs : cells) (ds : (channel * split) list) :
    tag list =
  fold
    (fun acc d ->
      Option.fold ~none:acc
        ~some:(fun t -> append acc [ t ])
        (excuse ks (fst d) (snd d) cs))
    [] ds

(* True only for a Present cell whose outcome is a panic of the given
   class.  An Absent cell is never a class. *)
let is_class (c : cell) (q : Obs.panic_class) : bool =
  match c with
  | Absent _ -> false
  | Present o -> (
      match o.Obs.outcome with
      | Obs.O_panic (p, _) ->
          String.equal (Obs.encode_panic_class p) (Obs.encode_panic_class q)
      | Obs.O_value _ -> false
      | Obs.O_no_terminate -> false)

(* I1 (M26 spec 8.6): on case 10 the reference names the panic class
   expect_err because it evaluated the left operand first
   (core/interp.ml:248-251), while both legs classify by message prefix
   and fall back to the static hint, which shell/driver.ml:598-602 maps
   to other.  Neither leg can do better with a static hint, so the
   class channel of that shape is excused, and only that channel. *)
let i1 () : known =
  {
    tag = Tag "I1";
    applies =
      (fun ch s cs ->
        match ch with
        | Ch_class -> (
            match s with
            | Odd L_ref ->
                is_class cs.reference Obs.P_expect_err
                && is_class cs.rust Obs.P_other
                && is_class cs.js Obs.P_other
            | Odd L_rust | Odd L_js | All_three | Two_way -> false)
        | Ch_outcome | Ch_message | Ch_value | Ch_rendered | Ch_signals ->
            false);
  }

(* [] is the no-allowlist input, and the unit vectors run every seed
   case both ways.  M33 relocates and grows the entries with upstream
   citations. *)
let known_seed () : known list = [ i1 () ]

(* ---------- Leg_fail, which precedes every comparison ---------- *)

(* The parties of one comparison, already resolved from the cells.  A
   sum type, never a record of options.  Missing carries the first
   absent PARTY in the order rust, js, reference;  a non-party absence
   never reaches it. *)
type party_view =
  | Three of Obs.observation * Obs.observation * Obs.observation
  | Two of Obs.observation * Obs.observation
  | Missing of leg * string

let view (m : Taxonomy.mode) (cs : cells) : party_view =
  match m with
  | Taxonomy.Read_only -> (
      match cs.rust with
      | Absent reason -> Missing (L_rust, reason)
      | Present a -> (
          match cs.js with
          | Absent reason -> Missing (L_js, reason)
          | Present b -> (
              match cs.reference with
              | Absent reason -> Missing (L_ref, reason)
              | Present c -> Three (a, b, c))))
  | Taxonomy.Signal_writing -> (
      match cs.js with
      | Absent reason -> Missing (L_js, reason)
      | Present a -> (
          match cs.reference with
          | Absent reason -> Missing (L_ref, reason)
          | Present b -> Two (a, b)))

let verdict (m : Taxonomy.mode) (ks : known list) (cs : cells) : verdict =
  match view m cs with
  | Missing (l, reason) -> Leg_fail (l, reason)
  | Three (a, b, c) -> classify ks cs (divergences m a b (Some c)) None
  | Two (a, b) -> classify ks cs (divergences m a b None) None

(* The tags of the channels this walk EXCUSED, in channel order.  A
   Leg_fail walk excuses nothing, because no channel is projected. *)
let excused (m : Taxonomy.mode) (ks : known list) (cs : cells) : tag list =
  match view m cs with
  | Missing (_, _) -> []
  | Three (a, b, c) -> excused_tags ks cs (divergences m a b (Some c))
  | Two (a, b) -> excused_tags ks cs (divergences m a b None)

(* ---------- the encoders ---------- *)

(* Every one injective, colon separated, no spaces.  These spellings
   ARE the V column of the printed table and the README. *)

let leg_name l = match l with L_rust -> "rust" | L_js -> "js" | L_ref -> "ref"

let channel_name c =
  match c with
  | Ch_outcome -> "outcome"
  | Ch_class -> "class"
  | Ch_message -> "message"
  | Ch_value -> "value"
  | Ch_rendered -> "rendered"
  | Ch_signals -> "signals"

let split_text s =
  match s with
  | Odd l -> "odd:" ^ leg_name l
  | All_three -> "all"
  | Two_way -> "two_way"

let tag_text t = match t with Tag s -> s

(* Injective because the four verdict prefixes are distinct words, the
   six channel names are distinct, the three leg names are distinct,
   and odd: is the only split text that carries a colon. *)
let verdict_text v =
  match v with
  | Agree -> "agree"
  | Diverge (c, s) -> "diverge:" ^ channel_name c ^ ":" ^ split_text s
  | Known t -> "known:" ^ tag_text t
  | Leg_fail (l, r) -> "leg_fail:" ^ leg_name l ^ ":" ^ r
