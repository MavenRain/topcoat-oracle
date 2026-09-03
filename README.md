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

## Status

Phase A in progress. The CTLK pipeline model is green, including the
negative-control expectations (see DESIGN.md section 4).

## License

MIT OR Apache-2.0.
