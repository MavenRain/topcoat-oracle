# topcoat-oracle

Differential conformance oracle for the Rust-expression-to-JS compiler
inside [Topcoat](https://github.com/tokio-rs/topcoat) (the `expr!`
macro plus browser runtime in `crates/topcoat-runtime`).

Three legs per generated expression: rustc-native, topcoat-emitted JS
under node, and an OCaml reference interpreter. Divergences shrink to
minimized repros under `repros/`.

- Design and milestone plan: [DESIGN.md](DESIGN.md)
- Pipeline model (CTLK, checked by ctlk_topos): `model/`
- Pinned study notes on the target: `research/`

## Run the gates

    ./gates.sh

Requires the karamel-710 opam switch with ctlk_topos, qcheck and
alcotest installed, plus node and cargo on PATH.

## Coverage report

    dune exec bin/coverage.exe -- --samples 10000 --scope default

Prints what a drawn batch covers: the constructor tally with the
required body names and the required init shapes that stayed
unreached, the mode counters, the environment coverage, the
target-type and expression-size histograms, and one line per dropped
sample. Flags:

    --samples N     batch size (default 10000)
    --seed S        decimal or 0x hex (default 0x4d3138)
    --mode M        mixed, read-only or signal-writing
    --scope S       default, m20 or m18
    --strict        exit 1 on a drop, an unreached required body
                    name, an unreached required init shape or a
                    reached excluded name
    --json          one JSON line instead of the text report

Scope m18 redraws the M18 generator stream and takes --mode mixed
only. Its constructor block is byte-identical to the block
test_gen.exe prints, which m22_gate.sh checks. A drop is any sample
the pipeline did not keep, for any reason; only kept samples feed a
histogram, and the drop lines have no cap.

## Rust leg

    ./m23_gate.sh

Builds two crates under _emit/ from shell/driver.ml, copies
driver-rs/harness.rs in as src/harness.rs, and runs them. The seed
crate is a fixed twelve-case vector whose JSONL value channel is
compared byte for byte with the table in m23_verdict.sh, with js_hex
and debug_hex masked first: both carry a fresh Signal uuid per run. The
JS channel is checked by one decoded substring per case. The seed's
last case spins, so exit 3 is the expected code. The same crate carries
the harness unit tests, which the gate runs with cargo test. The drawn
crate is 300 samples at scope m20, seed 0x4d3233, and must exit 0 with
one line per kept case; a drawn case that spins costs one exit 3, and
the gate resumes at the next index up to 20 times. Both JSONL captures
stay under _emit/m23/out/, which is gitignored.

Driver flags: --from I, --to J, --timeout-ms N (default 2000, and 0 or
a value that does not fit u64 is a usage error). Exit 0 all cases done,
1 an IO error, 2 usage, 3 a case timed out, 4 the closure call site
lost the direct body on at least one case. Exit 4 is folded over the
range, so an inconsistent case still writes its line and every later
case still runs; every value line carries js_consistent, so a resumed
run cannot lose the verdict between segments.

## Status

Phase D in progress. The CTLK pipeline model is green, including the
negative-control expectations (see DESIGN.md section 4).

## License

MIT OR Apache-2.0.
