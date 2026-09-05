(* M29 minimizer (DESIGN.md M29, spec section 3).  The shrink loop that
   turns a diverging sample into a small diverging sample.

   The module is PURE: no process, no file, no channel and no clock.
   The three legs enter as ONE injected function value, the way the
   interpreter takes Interp.ops, so this file is dual-compiled with the
   rest of core/ and the suite of test/test_minimize.ml drives the whole
   loop with a fake oracle that runs nothing.

   TERMINATION.  The size of a sample is `size_of s`: `Shrink.size` of
   its body, plus the number of inputs, plus the number of signals.
   Every body candidate comes from `Shrink.cands`, which is strictly
   smaller under `Shrink.size` by construction (core/shrink.ml:1-18),
   and a body candidate keeps every binding, so it lowers `size_of` by
   at least one.  Every binding candidate drops exactly one binding and
   keeps the body, so it lowers `size_of` by exactly one.  The loop
   moves only to an ACCEPTED candidate, so `size_of` strictly decreases
   at every step of the walk.  `size_of` is a sum of non-negative
   integers, so the walk is at most `size_of s0` steps long and the loop
   stops.  The fuel of the config is a SECOND and independent bound: it
   caps the number of rounds the loop enters and it is a stop reason,
   never an error.

   MODE.  A shrunk body can change the mode, because Taxonomy.mode_of
   reads the body and a dropped signal write is a real change.  Every
   candidate therefore recomputes its own mode: the differ picks the
   party set from the mode (core/differ.ml:405-428), so a carried-over
   mode would compare the wrong legs.

   ONE BUG.  A candidate is accepted only when its verdict is a Diverge
   on the SAME channel with the SAME split as the start verdict.  Agree,
   Known, Leg_fail and a no-verdict never preserve, so a leg failure and
   a timeout are never evidence and the loop cannot walk off one bug
   onto another.

   BLINDNESS IS NOT A FIXPOINT.  A round whose answers are all
   A_no_verdict told the loop nothing about any candidate: the legs were
   blind, because the crate writer dropped the whole batch, or the rust
   JSONL decoded to nothing, or the whole run failed.  That is NOT the
   same as a round whose answers are real verdicts that merely fail to
   preserve, and reporting it as Fixpoint would let a broken run print
   the shape of a good one.  The loop stops with Stuck and carries the
   reason, so the gate reads a named failure and not a small sample
   (decision sheet Q8, OVERRULED default). *)

open Prelude

(* What one round says about one candidate.  A_no_verdict carries the
   runner's own reason text: the rust crate writer dropped the sample,
   a leg failed as a whole, the js driver reported a driver error, or a
   run timed out.  A no-verdict never preserves a divergence. *)
type answer = A_verdict of Differ.verdict | A_no_verdict of string

(* The injected legs.  One call takes one whole round's candidate batch
   and answers one entry per candidate, in the same order, so the caller
   pays one cargo build and one node run per ROUND and not per
   candidate.  The round index rides along because the runner writes one
   crate directory per round (spec section 4.4) and a counter hidden in
   the runner would be state this loop cannot see. *)
type oracle = { o_run : round:int -> Sample.t list -> answer list }

(* The round fuel.  64 is far above the six rounds the two M29 cases
   need (spec section 8), so the gate measures a fixpoint and never a
   fuel stop.  A fuel of 1 is the second tooth of spec section 13. *)
type config = { fuel : int }

(* The shipped configuration. *)
let default_config : config = { fuel = 64 }

(* Which candidate a round accepted.  A two-constructor sum type and not
   an int option, because an option-typed record field is the shape the
   house rules refuse and this carries the same information. *)
type accepted = Acc_none | Acc_index of int

(* One round of the walk.  st_size is the size BEFORE the round, so the
   trace reads as a strictly decreasing column. *)
type step = {
  st_round : int;
  st_size : int;
  st_cands : int;
  st_accepted : accepted;
}

(* Why the loop stopped.

   Fixpoint means the last round offered candidates, got VERDICTS back,
   and none of them preserved the divergence.  That is the wanted answer
   and the one the gate requires.  A round that offered no candidate at
   all is a Fixpoint too, by definition.

   Fuel means the round budget ran out first, which is a stop and not an
   error.

   Stuck means the last round offered at least one candidate and EVERY
   answer was A_no_verdict, so the legs said nothing at all.  The string
   is the batch-level reason: the runner gives every candidate of a batch
   it could not run the same text, so the first answer carries it, and
   the literal "no_verdict" stands in when there is no text.  A round
   whose answers are verdicts that merely fail to preserve (Agree, Known,
   Leg_fail, or a Diverge on a different channel or split) is a Fixpoint
   and NOT Stuck. *)
type stop = Fixpoint | Fuel | Stuck of string

(* What M30 reads.  m_verdict is the divergence the walk preserved, that
   is the verdict of the sample the walk started from, so an emitter can
   name the bug without re-running a leg. *)
type result = {
  m_final : Sample.t;
  m_verdict : Differ.verdict;
  m_stop : stop;
  m_rounds : int;
  m_evaluated : int;
  m_trace : step list;
}

(* Leg equality by construction. *)
let leg_eq (a : Differ.leg) (b : Differ.leg) : bool =
  match a with
  | Differ.L_rust -> (
      match b with
      | Differ.L_rust -> true
      | Differ.L_js -> false
      | Differ.L_ref -> false)
  | Differ.L_js -> (
      match b with
      | Differ.L_js -> true
      | Differ.L_rust -> false
      | Differ.L_ref -> false)
  | Differ.L_ref -> (
      match b with
      | Differ.L_ref -> true
      | Differ.L_rust -> false
      | Differ.L_js -> false)

(* Channel equality by construction.  A new channel in core/differ.ml
   breaks this match, which is the point. *)
let channel_eq (a : Differ.channel) (b : Differ.channel) : bool =
  match a with
  | Differ.Ch_outcome -> (
      match b with
      | Differ.Ch_outcome -> true
      | Differ.Ch_class | Differ.Ch_message | Differ.Ch_value
      | Differ.Ch_rendered | Differ.Ch_signals ->
          false)
  | Differ.Ch_class -> (
      match b with
      | Differ.Ch_class -> true
      | Differ.Ch_outcome | Differ.Ch_message | Differ.Ch_value
      | Differ.Ch_rendered | Differ.Ch_signals ->
          false)
  | Differ.Ch_message -> (
      match b with
      | Differ.Ch_message -> true
      | Differ.Ch_outcome | Differ.Ch_class | Differ.Ch_value
      | Differ.Ch_rendered | Differ.Ch_signals ->
          false)
  | Differ.Ch_value -> (
      match b with
      | Differ.Ch_value -> true
      | Differ.Ch_outcome | Differ.Ch_class | Differ.Ch_message
      | Differ.Ch_rendered | Differ.Ch_signals ->
          false)
  | Differ.Ch_rendered -> (
      match b with
      | Differ.Ch_rendered -> true
      | Differ.Ch_outcome | Differ.Ch_class | Differ.Ch_message
      | Differ.Ch_value | Differ.Ch_signals ->
          false)
  | Differ.Ch_signals -> (
      match b with
      | Differ.Ch_signals -> true
      | Differ.Ch_outcome | Differ.Ch_class | Differ.Ch_message
      | Differ.Ch_value | Differ.Ch_rendered ->
          false)

(* Split equality by construction.  Two Odd splits agree only on the
   same odd leg, so a rust-odd candidate never preserves a js-odd
   start. *)
let split_eq (a : Differ.split) (b : Differ.split) : bool =
  match a with
  | Differ.Odd l -> (
      match b with
      | Differ.Odd m -> leg_eq l m
      | Differ.All_three -> false
      | Differ.Two_way -> false)
  | Differ.All_three -> (
      match b with
      | Differ.All_three -> true
      | Differ.Odd _ -> false
      | Differ.Two_way -> false)
  | Differ.Two_way -> (
      match b with
      | Differ.Two_way -> true
      | Differ.Odd _ -> false
      | Differ.All_three -> false)

(* R3, the preservation rule.  A candidate preserves the divergence
   only when its own verdict is a Diverge on the same channel with the
   same split.  Agree means the candidate lost the bug, Known means the
   candidate hit a catalogued difference instead, Leg_fail means a leg
   broke and says nothing about the bug, and a no-verdict means no
   evidence at all.  None of them may be accepted. *)
let preserves (target : Differ.verdict) (a : answer) : bool =
  match a with
  | A_no_verdict _ -> false
  | A_verdict v -> (
      match v with
      | Differ.Diverge (c, s) -> (
          match target with
          | Differ.Diverge (c0, s0) -> channel_eq c c0 && split_eq s s0
          | Differ.Agree -> false
          | Differ.Known _ -> false
          | Differ.Leg_fail (_, _) -> false)
      | Differ.Agree -> false
      | Differ.Known _ -> false
      | Differ.Leg_fail (_, _) -> false)

(* R5, the size.  The body weight of the shrinker plus one per binding,
   so dropping a binding is a real step and not a tie. *)
let size_of (s : Sample.t) : int =
  Shrink.size s.Sample.body + len s.Sample.inputs + len s.Sample.signals

(* The bindings of a list the body never mentions.  Shrink.mentions is
   conservative, so a binding it reports as mentioned stays even when a
   sharper reading would drop it (core/shrink.ml:87-89).  Written as
   a fold because Prelude has no filter. *)
let unmentioned (body : Ast.expr) (bs : Sample.binding list) :
    Sample.binding list =
  rev
    (fold
       (fun acc b ->
         if Shrink.mentions b.Sample.id body then acc else b :: acc)
       [] bs)

(* The same list without ONE binding, named by its id.  The ids of a
   sample are distinct by construction, so this drops exactly one. *)
let without (id : int) (bs : Sample.binding list) : Sample.binding list =
  rev (fold (fun acc b -> if b.Sample.id = id then acc else b :: acc) [] bs)

(* R4, the body candidates.  Shrink.cands is asked at the sample's
   TARGET type, so every candidate is well formed at the same type in
   the same context, and the mode is recomputed from the candidate body
   for the reason the header gives. *)
let body_cands (s : Sample.t) : Sample.t list =
  map
    (fun c ->
      { s with Sample.body = c; Sample.mode = Taxonomy.mode_of c })
    (Shrink.cands s.Sample.target s.Sample.body)

(* R4, the binding candidates.  One per never-mentioned binding, inputs
   before signals, each dropping that one binding and keeping the body
   and the mode.  A mentioned binding is never offered, because dropping
   it would leave a free variable and Wf would refuse the sample. *)
let drop_cands (s : Sample.t) : Sample.t list =
  append
    (map
       (fun b -> { s with Sample.inputs = without b.Sample.id s.Sample.inputs })
       (unmentioned s.Sample.body s.Sample.inputs))
    (map
       (fun b ->
         { s with Sample.signals = without b.Sample.id s.Sample.signals })
       (unmentioned s.Sample.body s.Sample.signals))

(* R4, the round's batch: every body candidate, then every binding
   drop.  The order IS the policy, because the loop is greedy and takes
   the first preserving entry, so a body step is always preferred to a
   binding drop and the collapse to the minimal term is always tried
   first (core/shrink.ml:272-278). *)
let candidates (s : Sample.t) : Sample.t list =
  append (body_cands s) (drop_cands s)

(* The greedy pick of one round, with the index the trace records. *)
type pick = P_none | P_at of int * Sample.t

(* The first candidate whose answer preserves the divergence.  The
   answers are aligned with the candidates by position, so a short
   answer list makes the missing tail unusable: nth_opt answers None
   there and Option.fold reads that as "does not preserve". *)
let rec first_preserving (target : Differ.verdict) (cs : Sample.t list)
    (answers : answer list) (i : int) : pick =
  match cs with
  | [] -> P_none
  | c :: rest ->
      let ok =
        Option.fold ~none:false ~some:(preserves target) (nth_opt answers i)
      in
      if ok then P_at (i, c) else first_preserving target rest answers (i + 1)

(* The trace field of one round. *)
let accepted_of (p : pick) : accepted =
  match p with P_none -> Acc_none | P_at (i, _) -> Acc_index i

(* The result record, with the accumulated trace put back in round
   order.  m_rounds is the number of rounds the loop ENTERED, which is
   the length of the trace. *)
let finish ~(stop : stop) ~(cur : Sample.t) ~(target : Differ.verdict)
    ~(evaluated : int) ~(trace : step list) : result =
  {
    m_final = cur;
    m_verdict = target;
    m_stop = stop;
    m_rounds = len trace;
    m_evaluated = evaluated;
    m_trace = rev trace;
  }

(* Did this round learn anything at all?  True when every answer is a
   no-verdict, which includes the degenerate case of an oracle that
   answered a SHORTER list than the batch and so said nothing about the
   tail.  Written as a fold and not a filter, because Prelude has no
   filter (spec finding 3). *)
let blind (answers : answer list) : bool =
  fold
    (fun acc a -> match a with A_verdict _ -> false | A_no_verdict _ -> acc)
    true answers

(* The reason a blind round carries.  The runner gives every candidate of
   a batch it could not run the SAME text, its own error text, so the
   first answer carries the batch-level reason.  A blind round with no
   answer at all has no text and the literal no_verdict stands in. *)
let blind_reason (answers : answer list) : string =
  Option.fold ~none:"no_verdict"
    ~some:(fun a ->
      match a with
      | A_verdict _ -> "no_verdict"
      | A_no_verdict why ->
          if String.length why = 0 then "no_verdict" else why)
    (nth_opt answers 0)

(* One round.  The oracle is called ONLY when the batch is non-empty: a
   round with no candidate is a fixpoint by definition and an empty
   batch would make the runner build an empty crate (spec finding 4).

   A round that accepted nothing stops, and the stop reason separates
   the two ways of accepting nothing.  n > 0 && blind answers means the
   legs were blind, which is Stuck.  Everything else is Fixpoint,
   including the zero-candidate round, whose empty answer list makes
   `blind` vacuously true and is excluded by the n > 0 test. *)
let rec round_of (o : oracle) ~(target : Differ.verdict) ~(round : int)
    ~(fuel : int) ~(cur : Sample.t) ~(evaluated : int) ~(trace : step list) :
    result =
  let cs = candidates cur in
  let n = len cs in
  let answers = if n = 0 then [] else o.o_run ~round cs in
  let p = first_preserving target cs answers 0 in
  let st =
    {
      st_round = round;
      st_size = size_of cur;
      st_cands = n;
      st_accepted = accepted_of p;
    }
  in
  let seen = evaluated + n in
  match p with
  | P_none ->
      let why =
        match () with
        | () when n > 0 && blind answers -> Stuck (blind_reason answers)
        | () -> Fixpoint
      in
      finish ~stop:why ~cur ~target ~evaluated:seen ~trace:(st :: trace)
  | P_at (_, c) ->
      go o ~target ~round:(round + 1) ~fuel:(fuel - 1) ~cur:c ~evaluated:seen
        ~trace:(st :: trace)

(* The loop.  The fuel is checked BEFORE a round is entered, so a fuel
   of n enters at most n rounds and a fuel stop leaves the last accepted
   sample as the final one. *)
and go (o : oracle) ~(target : Differ.verdict) ~(round : int) ~(fuel : int)
    ~(cur : Sample.t) ~(evaluated : int) ~(trace : step list) : result =
  match () with
  | () when fuel <= 0 -> finish ~stop:Fuel ~cur ~target ~evaluated ~trace
  | () -> round_of o ~target ~round ~fuel ~cur ~evaluated ~trace

(* R6, the entry point.  The start verdict is MEASURED by the caller and
   passed in, so this module holds no policy about what a run means and
   the suite can drive it with any target. *)
let run (o : oracle) (cfg : config) ~(target : Differ.verdict) (s : Sample.t) :
    result =
  go o ~target ~round:0 ~fuel:cfg.fuel ~cur:s ~evaluated:0 ~trace:[]
