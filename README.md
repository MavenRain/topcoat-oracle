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

## Status

Phase A in progress. The CTLK pipeline model is green, including the
negative-control expectations (see DESIGN.md section 4).

## License

MIT OR Apache-2.0.
