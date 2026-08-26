## 1. API cheat sheet

### `Topos` (module `T`, file `lib/topos.ml`) — the subobject calculus

```ocaml
type 'a obj = { carrier : 'a list; compare : 'a -> 'a -> int }
val obj_of_list : ('a -> 'a -> int) -> 'a list -> 'a obj   (* sorts+dedups *)
val size : 'a obj -> int

type 'a sub = 'a -> bool                       (* characteristic arrow / subobject *)

val top : 'a sub
val bot : 'a sub
val meet : 'a sub -> 'a sub -> 'a sub           (* AND *)
val join : 'a sub -> 'a sub -> 'a sub           (* OR *)
val imp  : 'a sub -> 'a sub -> 'a sub           (* implies *)
val neg  : 'a sub -> 'a sub

val tabulate : 'a obj -> 'a sub -> 'a sub       (* memoize a predicate over carrier into a Set-membership closure *)
val sub_leq   : 'a obj -> 'a sub -> 'a sub -> bool
val sub_equal : 'a obj -> 'a sub -> 'a sub -> bool
val holds_everywhere : 'a obj -> 'a sub -> bool  (* "AG" over the whole carrier, i.e. validity *)

val pullback : ('a -> 'b) -> 'b sub -> 'a sub
val exists_along : 'a obj -> 'b obj -> ('a -> 'b) -> 'a sub -> 'b sub
val forall_along : 'a obj -> 'b obj -> ('a -> 'b) -> 'a sub -> 'b sub

val prod : 'a obj -> 'b obj -> ('a * 'b) obj    (* only used in conformance tests, never on the hot path *)
val ex_rel : 'a obj -> ('a * 'a) sub -> 'a sub -> 'a sub   (* slow Kripke-Joyal EX, direct on R subobject *)
val ax_rel : 'a obj -> ('a * 'a) sub -> 'a sub -> 'a sub   (* slow Kripke-Joyal AX *)

val fixpoint_from : 'a obj -> ('a sub -> 'a sub) -> 'a sub -> 'a sub
val lfp : 'a obj -> ('a sub -> 'a sub) -> 'a sub   (* start = bot *)
val gfp : 'a obj -> ('a sub -> 'a sub) -> 'a sub   (* start = top *)
```
Fixpoint fuel = `size o + 1` iterations (finite lattice, Knaster-Tarski) so it is total regardless of monotonicity of `step`.

### `Ctlk` (module `C`, file `lib/ctlk.ml`) — interpreted systems + CTLK

```ocaml
type ('s, 'ag) system = {
  space : 's T.obj;
  next  : 's -> 's list;          (* successor / transition map *)
  agents : 'ag list;
  view  : 'ag -> 's -> string;    (* observation map; kernel pair = epistemic accessibility *)
}

val reachable : ('s -> 's -> int) -> ('s -> 's list) -> 's -> 's list

val system_of :
  ('s -> 's -> int) -> ('s -> 's list) -> 's ->    (* compare, next, init *)
  'ag list -> ('ag -> 's -> string) ->             (* agents, view *)
  ('s, 'ag) system
  (* builds sys.space by BFS reachable-closure from init *)

val rel_of_next : ('s, 'ag) system -> ('s * 's) T.sub   (* successor map as a genuine R subobject, for conformance/spec use *)
val serial : ('s, 'ag) system -> bool                   (* every state has >=1 successor *)

val ex : ('s, 'ag) system -> 's T.sub -> 's T.sub   (* fast fiberwise EX step *)
val ax : ('s, 'ag) system -> 's T.sub -> 's T.sub   (* fast fiberwise AX step *)

val know  : ('s, 'ag) system -> 'ag -> 's T.sub -> 's T.sub          (* K_i phi: groups carrier by view i, class holds iff every member holds *)
val eknow : ('s, 'ag) system -> 'ag list -> 's T.sub -> 's T.sub     (* everyone-in-group-knows step (used to build Common via gfp) *)

type ('p, 'ag) form =
  | Tt | Ff | Atom of 'p
  | Not of form | And of form*form | Or of form*form | Imp of form*form
  | Ex of form | Ax of form              (* EX / AX, one-step *)
  | Ef of form | Af of form              (* EF / AF *)
  | Eg of form | Ag of form              (* EG / AG *)
  | Eu of form*form | Au of form*form    (* E[g U h] / A[g U h] *)
  | Know of 'ag * form                   (* K_i phi *)
  | Common of 'ag list * form            (* common knowledge over a group: gfp of "everyone knows (phi & X)" *)

val eval : ('s,'ag) system -> ('p -> 's T.sub) -> ('p,'ag) form -> 's T.sub
  (* den: atom -> subobject (the interpretation function I). eval returns the truth-set. *)
val holds_at : ('s,'ag) system -> ('p -> 's T.sub) -> ('p,'ag) form -> 's -> bool
```
Notes: `Af`/`Au` are both implemented as **lfp** with the `ax` step (matches the CTL fixpoint characterizations). `Common` is a **gfp** of `eknow group (meet pg x)`. There is no separate `EG`/pastless operator set beyond the 8 temporal forms above; no "next" primitive beyond `Ex`/`Ax` (no bare `X`).

### `Witness` (file `lib/witness.ml`) — counterexamples

```ocaml
type 's witness =
  | Path of 's list                    (* failed AG: shortest E-path init -> violating state (BFS) *)
  | Successors of ('s * bool) list      (* failed EX: successor dump w/ per-successor verdict *)
  | Confusion of 's * 's                (* failed K_i: an indistinguishable state where body fails *)
  | At_state of 's * bool               (* fallback: state + honest verdict, for every other connective *)

val path_to : ('s -> 's -> int) -> ('s -> 's list) -> 's T.sub -> 's -> 's list option
val explain : ('s,'ag) Ctlk.system -> ('p -> 's T.sub) -> ('p,'ag) Ctlk.form -> 's -> 's witness
```
`explain` only special-cases `Ag`, `Ex`, `Know`; everything else falls back to `At_state`. Intended to be called on formulas whose `holds_at` verdict already came out false (fallback re-evaluates honestly if that expectation is violated).

### `Presheaf` (file `lib/presheaf.ml`) — non-Boolean layer over a finite preorder

```ocaml
type 'w order = { carrier : 'w list; le : 'w -> 'w -> bool }
val prop_ok : 'w order -> ('w -> bool) -> bool         (* well-formedness: predicate must be monotone (upper set) along le *)
val top/bot/meet/join : ('w -> bool) ...
val imp : 'w order -> ('w -> bool) -> ('w -> bool) -> ('w -> bool)   (* Kripke implication: forced at w iff holds at every w' >= w *)
val neg : 'w order -> ('w -> bool) -> ('w -> bool)      (* = imp _ p bot *)
val prop_equal : 'w order -> ('w -> bool) -> ('w -> bool) -> bool
val order_of_steps :
  ('w -> 'w -> int) -> ('w -> 'w list) -> ('w -> 'w -> bool) -> 'w list -> 'w order
  (* reflexive-transitive closure of a successor map filtered by a `stay` predicate; built via Ctlk.reachable *)
```
This layer is entirely separate from `Ctlk` (no `Ctlk.form` support) — it gives Heyting (not Boolean) `imp`/`neg` for reasoning about monotone predicates over an evolving order. Neither `ctlk-topos` test suite nor the tinysvid consumer wires it into `Ctlk.eval`; it is a standalone lattice utility. `Presheaf` depends on `Ctlk.reachable` (cross-module use inside the library, `wrapped false`).

## 2. Worked example (verbatim, from `test/test_topos.ml`)

```ocaml
module T = Topos
module C = Ctlk

(* Toy Kripke frame: 0 -> 1 -> 2, 2 -> 2, and 0 -> 0. *)
let toy_next (s : int) : int list =
  match s with
  | 0 -> [ 0; 1 ]
  | 1 -> [ 2 ]
  | _ -> [ 2 ]

let toy_view (ag : int) (s : int) : string =
  (* Agent 0 cannot tell 0 from 1; agent 1 sees everything. *)
  match ag with
  | 0 -> if s <= 1 then "low" else "high"
  | _ -> string_of_int s

let toy () : (int, int) C.system =
  C.system_of Int.compare toy_next 0 [ 0; 1 ] toy_view

let atom_at (v : int) : int T.sub = fun s -> s = v

let sys = toy () in
let den (p : int) : int T.sub = atom_at p in
let holds (f : (int, int) C.form) (s : int) : bool = C.holds_at sys den f s in
(* EF: state 2 is reachable from everywhere; 0 is unreachable from 2. *)
assert (T.holds_everywhere sys.C.space (C.eval sys den (C.Ef (C.Atom 2))));
assert (not (holds (C.Ef (C.Atom 0)) 2));
(* AF: from 1 every path hits 2; from 0 the self-loop can dodge it. *)
assert (holds (C.Af (C.Atom 2)) 1);
assert (not (holds (C.Af (C.Atom 2)) 0));
(* Knowledge: agent 0 merges 0 and 1, so it cannot know Atom 0 there;
   agent 1 distinguishes them and knows it at 0. *)
assert (not (holds (C.Know (0, C.Atom 0)) 0));
assert (holds (C.Know (1, C.Atom 0)) 0);
(* Common knowledge of a global truth / failure where one agent is unsure. *)
assert (holds (C.Common ([ 0; 1 ], C.Or (C.Or (C.Atom 0, C.Atom 1), C.Atom 2))) 0);
assert (not (holds (C.Common ([ 0; 1 ], C.Atom 0)) 0));
```
`system_of Int.compare toy_next 0 [0;1] toy_view` is the minimal call: `compare`, `next`, `init`, `agents`, `view`.

## 3. Integration pattern for a new consumer repo

`ctlk-topos` is committed at `ba5c567` and pushed to `origin` (fetch/push):
```
https://github.com/MavenRain/ctlk-topos.git
```

**Library shape (already committed, no `pin-depends` line is used):**
- `dune-project`: `(lang dune 3.0)` / `(name ctlk_topos)`
- `lib/dune`: `(library (name ctlk_topos) (public_name ctlk_topos) (wrapped false) (modules topos ctlk witness presheaf))`
- `ctlk_topos.opam`: stdlib-only, `depends: [ "ocaml" {>= "5.0"} "dune" {>= "3.0"} ]`, `build:` runs `dune build -p name -j jobs` and (with-test) `dune runtest -p name -j jobs`.

**What a new consumer needs, verified against the tinysvid integration (see README/commit message: "Both dependencies arrive as opam pins (ctlk_topos, sha2) in the build switch"):**
1. **Pin the package into the opam switch itself** (not a repo-local `pin-depends` stanza — tinysvid has no `.opam` file at all, just `dune-project`):
   ```
   opam pin add ctlk_topos https://github.com/MavenRain/ctlk-topos.git
   ```
   (this installs `ctlk_topos` as a findlib library into the active switch; no in-repo pin metadata is checked in for tinysvid).
2. **Consumer `dune-project`**: just `(lang dune 3.13)` / `(name tinysvid)` — no ctlk-topos reference needed there since `wrapped false` exposes `Topos`/`Ctlk`/`Witness`/`Presheaf` directly.
3. **Consumer library/test `dune` stanza** (verbatim, `/Users/oobi/Documents/tinysvid/model/dune`):
   ```
   (library
    (name svid_model)
    (libraries ctlk_topos)
    (modules state frame props))

   (test
    (name check)
    (modules check)
    (libraries svid_model ctlk_topos))
   ```
   Note the `ctlk_topos` name is used directly as a `libraries` entry (unwrapped library, module names `Topos`/`Ctlk`/`Witness`/`Presheaf` come in bare).
4. **Pin-drift guard (R0)**: exact pattern from `/Users/oobi/Documents/tinysvid/model/check.ml`:
   ```ocaml
   (* Frame.reachable serves the correspondence and zx gates; it must
      agree with the kernel closure the property systems are built on. *)
   let reach_agree =
     State.StateSet.equal
       (Frame.reachable Frame.Coupled State.init)
       (State.StateSet.of_list sys_c.Ctlk.space.T.carrier)
     && State.StateSet.equal
          (Frame.reachable Frame.Uncoupled State.init)
          (State.StateSet.of_list sys_u.Ctlk.space.T.carrier)
   in
   Printf.printf "%s R0-reachable-agrees-kernel   both frames\n"
     (if reach_agree then "PASS" else "FAIL");
   ```
   and `Frame.reachable` itself just delegates to the kernel (`/Users/oobi/Documents/tinysvid/model/frame.ml`):
   ```ocaml
   let reachable coupling start =
     Ctlk.reachable Stdlib.compare (post coupling) start |> StateSet.of_list
   ```
   This makes any consumer's own domain-level "reachable" helper a thin wrapper over `Ctlk.reachable`, then asserts (as check #0/"R0" — counted separately from the numbered property checks, `Bool.to_int (not reach_agree)` seeds the failure accumulator) that its result set equals `sys.Ctlk.space.T.carrier` built by `Ctlk.system_of`. This guards against the consumer's hand-rolled closure and the kernel's BFS closure silently diverging (e.g. after an edit to the successor map that only one of the two call sites picks up).

## 4. Modeling idioms (from tinysvid `model/{state,frame,props}.ml`)

- **State representation: a record**, not int-encoded. `type state = { auth : epoch; bundle : bundle; svid : svid; link : link }` where `epoch = E0|E1|E2`, `bundle = Held of freshness*epoch | Void`, `svid = No_svid | Svid of epoch`, `link = Up|Down`. Compare is `Stdlib.compare` (structural), used both for `Ctlk.system_of`'s `compare` argument and for a local `StateSet = Set.Make(struct type t = state let compare = Stdlib.compare end)`.
- **State-space size**: not explicitly stated, but bounded — 3 epochs x (2 freshness x 3 epoch + 1 void) bundle x (1 + 3) svid x 2 link, capped further by reachability from `init`; `check.ml` prints `worlds: coupled %d, uncoupled %d` via `T.size sys_c.Ctlk.space` at runtime rather than asserting a fixed bound, i.e. the practical ceiling is discovered empirically, not pre-declared. The kernel's own `fixpoint_from` fuel is `size o + 1`, so eval cost scales with carrier size per fixpoint (roughly O(|carrier|^2) per lfp/gfp given the fiberwise `ex`/`ax` scan each state's successors); this repo's toy-scale frame (a handful of components x small enums) is well inside where `eval` stays instant, and is the only evidence available on where it "chokes" — no consumer here pushes past that.
- **Transition modeling**: `Frame.steps coupling w : (tname * state) list` returns named, possibly-absent transitions via `Option.map`/`List.filter_map Fun.id` over a fixed set of named moves (`Rotate | Tick | Sync | Renew | Expire | Link_flip`); `Frame.post coupling w = List.map snd (steps coupling w)` is what's fed as `next` to `Ctlk.system_of`. A `coupling` parameter (`Coupled | Uncoupled`) selects between two systems built from the *same* state/transition code, letting one property suite check both the shipped design and a negative control (`Frame.post Frame.Coupled` vs `Frame.post Frame.Uncoupled`), each wrapped in its own `Ctlk.system_of ... State.init ...` call (`sys_c`, `sys_u`).
- **Knowledge modalities**: two agents, `Workload` and `Authority`. Each gets an **injective string view** over only the components it can observe — this is the required shape for `Ctlk.know`, which groups states by `sys.view ag s : string` equality:
  - `view_workload w = bundle_view w.bundle ^ "|" ^ svid_view w.svid ^ "|" ^ link_view w.link` (never includes `w.auth`)
  - `view_authority w = "auth:" ^ epoch_index w.auth ^ "|" ^ link_view w.link` (never includes bundle/svid)
  Comment in `props.ml`: "The kernel compares observations as strings, so each view renders its components injectively" — i.e. the encoding discipline required by `Ctlk.know`'s `Map.Make(String)` grouping is: pick exactly the fields the agent can see, then serialize them with unambiguous separators/tags so distinct semantic observations never collide as strings.
  - Formulas used: `Know (Workload, Atom (Gap_is 0))`, `Know (Workload, Atom (Gap_at_most 1))`, `Not (Know (Workload, ...))`, `Not (Know (Authority, Atom Usable))` — only single-agent `Know`, no `Common` used in this consumer (unlike the kernel's own test suite, which does exercise `Common`).
  - Properties are plain CTL (`Imp`, `Ex Tt`, `Ag (Ef (Atom Fresh))`) mixed freely with `Know`, evaluated via `Ctlk.eval sys den_f c.form`, then classified `Must_be_valid` (checked with `T.holds_everywhere`) vs `Must_be_satisfiable` (checked with `List.exists sub sys.Ctlk.space.T.carrier`) — a two-kind check-table pattern (`type kind = Must_be_valid | Must_be_satisfiable`) that any consumer can reuse verbatim for validity vs satisfiability specs.

