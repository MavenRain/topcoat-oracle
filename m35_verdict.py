#!/usr/bin/env python3
"""Publish and verify the exact campaign divergence-to-repro mapping."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import m34_verdict

FILES = ("repro.md", "walk.jsonl", "rust.jsonl", "js.jsonl")
CAMPAIGN = "_emit/m34/check/archive"


def require(ok, message):
    if not ok:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_sha40(text):
    return isinstance(text, str) and len(text) == 40 and all(
        c in "0123456789abcdef" for c in text)


def git_head(root):
    """The oracle provenance sha every repro claims, read from git."""
    result = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                            text=True, capture_output=True)
    require(result.returncode == 0, f"git rev-parse HEAD failed: {result.stderr}")
    head = result.stdout.strip()
    require(is_sha40(head), f"oracle head is not a sha40: {head}")
    return head


def execution_sources(root):
    names = m34_verdict.source_inventory(root) | {"bin/m35.ml", "bin/dune"}
    return {name: digest(root / name) for name in sorted(names)}


def sources(root):
    names = set(execution_sources(root)) | {"m35_verdict.py"}
    return {name: digest(root / name) for name in sorted(names)}


def expected(root):
    _, rows, _, _ = m34_verdict.load_evidence(root, root / "_emit/m34/check")
    return [r["i"] for r in rows if r["verdict"].startswith("diverge:")]


def replay(root, index, directory, oracle_sha, good=True, reason=None):
    """Replay one repro. A corruption control names the refusal it expects,
    so a refusal for another cause is a failure of the control."""
    result = subprocess.run([str(root / "_build/default/bin/m35.exe"), "replay",
                             CAMPAIGN, str(index), str(directory), oracle_sha],
                            cwd=root, text=True, capture_output=True)
    if good:
        require(result.returncode == 0, f"replay {index}: {result.stderr}")
    else:
        require(result.returncode != 0 and reason is not None
                and reason in result.stderr,
                f"corruption accepted or wrong refusal for {index}: {result.stderr}")


def check_mapping(root, indices, meta):
    require(meta["format"] == 1, "unsupported repro archive")
    require(meta["indices"] == indices, "divergence index mapping changed")
    require(len(set(indices)) == len(indices), "duplicate divergence index")
    require(is_sha40(meta["oracle_sha"]), "manifest oracle sha is not a sha40")
    require(meta["campaign_sha256"] == digest(root / "research/campaign-1/journal.jsonl.gz"),
            "campaign archive changed")
    require(meta["sources"] == sources(root), "repro execution sources changed; renew evidence")
    archive = root / "repros/campaign-1"
    require({p.name for p in archive.iterdir()} == {str(i) for i in indices} | {"manifest.json"},
            "missing or extra repro entries")
    want_files = {f"{i}/{name}" for i in indices for name in FILES}
    require(set(meta["files"]) == want_files, "incomplete repro fingerprint inventory")
    for i in indices:
        require({p.name for p in (archive / str(i)).iterdir()} == set(FILES),
                f"unexpected files for repro {i}")
    for name, value in meta["files"].items():
        require(digest(archive / name) == value, f"repro digest mismatch: {name}")


def run(root):
    expected(root)
    subprocess.run(["opam", "exec", "--switch=anvil-ocaml", "--", "dune",
                    "build", "bin/m35.exe"], cwd=root, check=True)
    output = root / "_emit/m35/out"
    output.mkdir(parents=True, exist_ok=True)
    receipt = root / "_emit/m35/completed.json"
    # Invalidate a previous completion before starting a new live run.
    receipt.unlink(missing_ok=True)
    before = execution_sources(root)
    executable = root / "_build/default/bin/m35.exe"
    binary = digest(executable)
    subprocess.run([str(executable), "stream", CAMPAIGN, ".", "../topcoat"],
                   cwd=root, check=True)
    require(execution_sources(root) == before and digest(executable) == binary,
            "producer changed during live minimization")
    receipt.write_text(json.dumps({"sources": before, "executable_sha256": binary},
                                 indent=2, sort_keys=True) + "\n")


def publish(root):
    indices = expected(root)
    receipt = json.loads((root / "_emit/m35/completed.json").read_text())
    require(receipt["sources"] == execution_sources(root), "live producer sources changed")
    require(receipt["executable_sha256"] == digest(root / "_build/default/bin/m35.exe"),
            "live producer executable changed")
    require(bool(indices), "campaign has no divergences")
    archive = root / "repros/campaign-1"
    require(not archive.exists(), "publication directory already exists")
    archive.parent.mkdir(parents=True, exist_ok=True)
    head = git_head(root)
    # Validate all evidence before creating the published directory. A temporary
    # sibling is renamed only after it holds the complete checked mapping.
    for i in indices:
        replay(root, i, root / "_emit/m35/out" / str(i), head)
    with tempfile.TemporaryDirectory(prefix=".m35-", dir=archive.parent) as scratch:
        staged = Path(scratch) / "campaign-1"
        staged.mkdir()
        for i in indices:
            dest = staged / str(i)
            dest.mkdir()
            for name in FILES:
                shutil.copyfile(root / "_emit/m35/out" / str(i) / name, dest / name)
        # The staged bytes, not the live source, are the bytes this manifest
        # fingerprints and the rename publishes, so they are replayed here.
        for i in indices:
            replay(root, i, staged / str(i), head)
        meta = {"format": 1, "indices": indices, "oracle_sha": head,
                "sources": sources(root),
                "campaign_sha256": digest(root / "research/campaign-1/journal.jsonl.gz"),
                "files": {f"{i}/{name}": digest(staged / str(i) / name)
                          for i in indices for name in FILES}}
        (staged / "manifest.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n")
        staged.rename(archive)
    print(f"m35 published {len(indices)} repros")


def controls(root, index, oracle_sha):
    original = root / "repros/campaign-1" / str(index)
    (root / "_emit/m35").mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="m35-controls-", dir=root / "_emit/m35") as scratch:
        dest = Path(scratch) / str(index)
        def reset():
            shutil.copytree(original, dest, dirs_exist_ok=True)
        reset()
        # A missing final refusal round cannot certify a fixpoint.
        walk = (dest / "walk.jsonl").read_text().splitlines()
        (dest / "walk.jsonl").write_text("\n".join(walk[:-1]) + "\n")
        replay(root, index, dest, oracle_sha, good=False, reason="walk shape mismatch")
        reset()
        meta = json.loads(walk[0])
        meta["index"] = index + 1
        (dest / "walk.jsonl").write_text("\n".join([json.dumps(meta)] + walk[1:]) + "\n")
        replay(root, index, dest, oracle_sha, good=False, reason="walk metadata mismatch")
        reset()
        (dest / "js.jsonl").write_text("")
        replay(root, index, dest, oracle_sha, good=False,
               reason="witness must contain exactly one line")
        reset()
        # The first archived case is a class split. A valid wire observation
        # on another outcome must fail the preserving-witness guard as well.
        # The key set per outcome is exact (core/wire_js.ml:7), so a decodable
        # no_terminate witness carries the three no_terminate keys and no more.
        js = json.loads((dest / "js.jsonl").read_text())
        (dest / "js.jsonl").write_text(json.dumps(
            {"case": js["case"], "outcome": "no_terminate", "hint": js["hint"]}) + "\n")
        replay(root, index, dest, oracle_sha, good=False,
               reason="fresh witness does not preserve the original divergence")
        reset()
        (dest / "repro.md").write_text((dest / "repro.md").read_text() + "forged\n")
        replay(root, index, dest, oracle_sha, good=False,
               reason="repro does not match reconstructed walk and witness")
        reset()
        meta = json.loads(walk[0])
        meta["fuel"] = 1
        (dest / "walk.jsonl").write_text("\n".join([json.dumps(meta)] + walk[1:]) + "\n")
        replay(root, index, dest, oracle_sha, good=False, reason="walk metadata mismatch")
        reset()
        # A repro claims one oracle provenance sha. A shape-valid substitute
        # is not that sha.
        meta = json.loads(walk[0])
        meta["oracle_sha"] = "0" * 40
        (dest / "walk.jsonl").write_text("\n".join([json.dumps(meta)] + walk[1:]) + "\n")
        replay(root, index, dest, oracle_sha, good=False, reason="walk metadata mismatch")
        reset()
        # A forged round answer that no verdict class writes is refused.
        rounds = [json.loads(line) for line in walk[1:]]
        rounds[0]["answers"] = ["forged answer"] * len(rounds[0]["answers"])
        (dest / "walk.jsonl").write_text("\n".join(
            [walk[0]] + [json.dumps(r) for r in rounds]) + "\n")
        replay(root, index, dest, oracle_sha, good=False, reason="unknown answer text")
        reset()
        replay(root, index, dest, oracle_sha)


def check(root):
    indices = expected(root)
    require(bool(indices), "vacuous divergence mapping")
    archive = root / "repros/campaign-1"
    meta = json.loads((archive / "manifest.json").read_text())
    check_mapping(root, indices, meta)
    oracle_sha = meta["oracle_sha"]
    for i in indices:
        replay(root, i, archive / str(i), oracle_sha)
    controls(root, indices[0], oracle_sha)
    repros = len([p for p in archive.iterdir() if p.is_dir()])
    print(f"M35 GATE GREEN: {len(indices)} divergences, {repros} minimized repros, replay and corruption controls passed")


def main():
    require(len(sys.argv) == 3 and sys.argv[1] in {"run", "publish", "check"},
            "usage: m35_verdict.py run|publish|check <root>")
    root = Path(sys.argv[2]).resolve()
    {"run": run, "publish": publish, "check": check}[sys.argv[1]](root)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        print(f"m35: RED {exc}", file=sys.stderr)
        sys.exit(1)
