## Toolchain probe results

### 1. OCaml switches
- `opam switch list`: many named switches (all tool-specific), current active `→ zxcaml-p1` (5.2.1). Default global switch resolves to OCaml 5.3.0 for bare `ocaml`/`dune` invocations in the shell env used here.
- Default switch: `ocaml -version` = OCaml 5.3.0. Lib dir contents matching `qcheck|alcotest|ctlk`: only `ctlk_topos` found. **No qcheck, no alcotest.**
- `zxcaml-p1` switch: `ocaml -version` = OCaml 5.2.1. Same result: only `ctlk_topos` present, **no qcheck, no alcotest.**
- Confirmed via `opam list` (not just lib-dir grep) on both switches: only `dune 3.24.2` matches (`dune`); no `qcheck`/`alcotest` package rows at all in either switch.
- `dune --version` = 3.24.2 on both switches (works via `opam exec --switch=... -- dune --version` too).
- Note: opam warns "environment is not in sync with the current switch — run `eval $(opam env)`" — shell PATH may not point at the active switch's bin by default; needs `eval $(opam env --switch=<name> --set-switch)` before invoking switch-specific tools (as `omlz-run.sh` already does for `zxcaml-p1`).

### 2. Node
- `node --version` = v23.10.0
- `which node` = `/opt/homebrew/bin/node`
- Node is available and recent; fine for spawning as a test subject/oracle.

### 3. Rust
- `rustc --version` = rustc 1.96.0-nightly (cf7da0b72 2026-03-30)
- `cargo --version` = cargo 1.96.0-nightly (e84cb639e 2026-03-21)
- Nightly toolchain only surfaced (per user's global convention, telcoin gates use pinned `+1.94`, but this is just the ambient toolchain — differential-testing repo should pin explicitly if it needs a specific Rust version).
- `~/.cache/solana` platform-tools dirs exist: `v1.48`, `v2.3.2` — not needed for this task, just noted as present.

### 4. topcoat repo
- HEAD: `51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a` — Tue Aug 25 00:20:36 2026 +0200 — "feat(core): add pretty printing impls for all `syn` types, remove `prettyplease` (#372)"
- remote: `origin` = `https://github.com/tokio-rs/topcoat` (fetch+push) — this is the upstream tokio-rs fork/mirror, not a personal fork (push URL is upstream too, so pushing would require a fork/PR flow).

### 5. ctlk-topos repo
- HEAD: `ba5c567c5ffaa6401a1f14d3c2f5a1a5001aa169` — "Extract the CTLK-in-topos checker kernel as a standalone library"
- remote: `origin` = `https://github.com/MavenRain/ctlk-topos.git` (fetch+push) — user-owned repo, matches MEMORY.md note it was committed+pushed 2026-08-26.

### 6. Local CLI tools (`~/.local/bin`)
- Present: `aikencho`, `dunecho`, `dunecho.bak-2026-07-26`, `zxlint`. **`omlz` is NOT in `~/.local/bin`** — `omlz --version` fails with "command not found".
- `zxlint --help` works: "zxlint: static pre-codegen linter for ZxCaml bpf programs." Usage: `zxlint [options] FILE.ml [FILE.ml ...]`, `--entrypoint NAME` option (default: entrypoint).

### 7. zxcaml-bench omlz wrapper
- `/Users/oobi/Documents/claude1/zxcaml-bench/omlz-run.sh` exists and reads:
```bash
#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/zig/zig-aarch64-macos-0.16.0:$HOME/.local/bin:$PATH"
eval "$(opam env --switch=zxcaml-p1 --set-switch)"
cd /Users/oobi/Documents/claude1/zxcaml-bench-src
exec zig-out/bin/omlz "$@"
```
This wrapper does NOT depend on a bare `omlz` in PATH — it execs a prebuilt binary at `zig-out/bin/omlz` inside `zxcaml-bench-src`, after setting up zig PATH and the `zxcaml-p1` opam env. Whether that binary still exists was not directly checked (only `cat` was requested); the script logic itself is intact and would work if `zig-out/bin/omlz` is present in that dir.

### 8. dunecho
- `dunecho --version` = `0.1.0`

## Blockers for a new OCaml differential-testing repo
1. **QCheck property tests: BLOCKED.** Neither the default opam switch (5.3.0) nor `zxcaml-p1` (5.2.1) has `qcheck` or `alcotest` installed (confirmed via both lib-dir listing and `opam list`). Would need `opam install qcheck qcheck-alcotest alcotest` (or similar) on whichever switch the new repo targets — this is an install step, not runnable read-only here.
2. **`dune build`: not blocked.** Dune 3.24.2 is present and working on both switches.
3. **Spawning rustc: not blocked.** rustc/cargo 1.96.0-nightly available; if the new repo needs a *specific* pinned Rust version (per user convention for telcoin-style pins), that must be set up explicitly — ambient toolchain is nightly only.
4. **Spawning node: not blocked.** Node v23.10.0 at `/opt/homebrew/bin/node`.
5. Minor: opam env is reported "not in sync" with the active switch (`zxcaml-p1`) in a bare interactive shell — any script depending on switch-specific binaries must explicitly `eval $(opam env --switch=<name> --set-switch)` first (the `omlz-run.sh` wrapper already does this correctly).
6. `omlz` itself is not a general `~/.local/bin` CLI — only reachable via the `omlz-run.sh` wrapper's direct exec path, not standalone.

## Key files

