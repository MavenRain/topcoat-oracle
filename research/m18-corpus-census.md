# M18 corpus census: runtime expressions in the topcoat examples

Pin: topcoat @ 51caa01d (workspace 0.6.2), clone at ~/Documents/topcoat.

Corpus: every `$(...)` runtime-expression fragment in `examples/` and
`demos/`, plus the `signal` declarations that type them. Sweep:
`rg -c '\$\(' examples demos -g '*.rs'`. Total: 24 fragments in 6
files. No other corpus tier exists at this pin: the remaining
examples use server-side templates only.

## Fragment inventory

| File | Fragments |
| --- | --- |
| examples/runtime/src/counter.rs | 3 (lines 9, 11, 17) |
| examples/runtime/src/show.rs | 3 (lines 8, 10, 14) |
| examples/procedure/src/main.rs | 3 (lines 38, 39, 45) |
| examples/shard/src/main.rs | 3 (line 47 x2, line 50) |
| demos/coffee-shop/src/app/menu/drink.rs | 7 (lines 57, 68, 73, 81, 90, 98, 99) |
| demos/coffee-shop/src/app/menu.rs | 5 (lines 35, 36, 43, 44, 51) |

Signal declarations (7): String x4 (`input` x2, `query`,
`confirmation`), f64 x2 (`count` = 0.0, `quantity` = 1.0), bool x1
(`show` = false).

## Per-construct counts

Counted per occurrence across the 24 fragments.

| Construct | Count | Witness |
| --- | --- | --- |
| signal `.get()` | 16 | counter.rs:17, menu.rs:35, ... |
| signal `.set()` | 7 | procedure:39/47, shard:47, drink:61/92, menu:36/44 |
| signal `.increment()`/`.decrement()` | 4 | counter:9/11, drink:59/73 |
| signal `.toggle()` | 1 | show:8 |
| bare signal receiver (E_var at Signal) | 28 | every get/write receiver |
| sync closure | 9 | counter:9/11, show:8, procedure:39, shard:47, drink:57/73, menu:36/44 |
| async closure | 2 | procedure:45, drink:90 |
| plain closure body | 8 | the unbraced handler bodies |
| braced closure body | 3 | drink:57, procedure:45, drink:90 |
| `.await` | 2 | procedure:46, drink:91 |
| async fn call (future source) | 2 | print_on_server, place_order |
| sync fn call | 0 | |
| `let` statement | 2 | procedure:46, drink:91 |
| expression statement | 5 | procedure:47, drink:59/61/92, plus the if/else at drink:58 |
| unit block body (E_block_unit) | 3 | procedure:45, drink:90, drink:57 bodies |
| value block (E_block) | 0 | |
| `if`/`else` | 2 | show:10 (String), drink:58 (unit arms) |
| bare `if` (no else) | 0 | |
| `!` (U_not) | 1 | show:14 |
| unary `-` | 0 | |
| arithmetic binary | 1 | drink:81 (`*`) |
| comparison (`<`) | 1 | drink:58 |
| `==`/`!=` | 0 | |
| `.is_empty()` | 2 | drink:98, menu:43 |
| `.to_owned()` | 2 | drink:91, menu:44 |
| environment variable use | 4 | price, name, server_response, message |
| literals | 5 | 1.0 x2, "hide", "reveal", "" |
| loops, break, continue, return | 0 | |
| Option/Result constructors and methods | 0 | |
| trim family, starts/ends/contains, len | 0 | |
| `.clone()`, `.unwrap()`, `.expect()` | 0 | |

Out of vocabulary, noted only: event field access `e.target.value`
(3: procedure:39, shard:47, menu:36). The oracle AST has no event
object; the driver binds handler parameters outside the expression.

## Seeding rule

For a production site the census counts:

    weight = 1 + ceil(log2(count + 1))

A corpus-absent production keeps the floor weight 1. It stays
reachable because the corpus-absent constructs are the least
exercised Rust/TS parity surface, which is the expected bug-yield
zone. Sites the census cannot see keep their M17 structural values:
f64 pool vs random bits (render-vector coverage), loop-body suffix
(termination lever), fuel draws.

Applied values: shell/weights.ml `default`, one comment per field
with the census count or the `M17` marker.

## Type-draw seeding

Types of corpus expressions: Fn (handlers) 9, unit (write statements)
12, String 7, f64 3, bool 3, AsyncFn 2, Future (await operands) 2,
Option/Result/Signal-as-target/tuple 0. Same formula.

## M18 gate

test/test_gen.ml: 10k samples, fixed seed, Tally.of_samples. Every
required constructor appears at least once; the excluded set
(E_tuple, E_field, E_index, U_deref, T_tuple) stays at zero. The
counter report prints before the alcotest run. M_expect_err gained a
production in this milestone; before M18 the generator never emitted
it, so the full-vocabulary assertion would have failed.

Review fixes folded in before commit: plain closure bodies recounted
8 (weight 5, not 4); E_block_unit recounted 3 (same weight); and
gen_ty now draws T_unit in the fuel-free base list, because the
fuel-gated placement excluded unit targets from every tyfuel=0
sample (a third of the draw) and would have undershot the census
weight.
