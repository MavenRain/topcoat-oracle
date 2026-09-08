#!/usr/bin/env python3
"""Run the README quickstart and check fresh evidence, replay and resume."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

PIN = "51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a"
SEED = 0x4d3336
SWITCH = "anvil-ocaml"
START = "<!-- m37-quickstart:start -->"
END = "<!-- m37-quickstart:end -->"
EVIDENCE = ("journal.jsonl", "trace.jsonl")
HEADS = ("agree", "known", "diverge", "leg_fail", "dropped", "no_line", "batch_fail")
ADJUDICATED = ("agree", "known", "diverge")
# The floor sits below the measured census (agree 9, known 0, diverge 6), so a
# Node parser that loses one more comparison does not turn the gate RED with
# no defect in the oracle.  The census itself is checked against the M32
# correspondence below, which is a function of the journal alone.
FLOOR = 10
# Each adjudicated head allows exactly one M32 end stage
# (shell/correspond.ml:508-510).
STAGES = {"agree": "dropped_agree", "known": "dropped_known",
          "diverge": "minimizing_hi"}
# The truncated copy keeps this many sample rows, so the resume of that copy
# runs real batches for the rest.  A resume of the COMPLETE directory
# short-circuits to the summary (shell/pipeline.ml:583) and runs no leg.
KEPT = 50


def require(ok, message):
    if not ok:
        raise ValueError(message)


def quickstart(text):
    require(text.count(START) == text.count(END) == 1,
            "README needs exactly one quickstart marker pair")
    start, end = text.index(START) + len(START), text.index(END)
    require(start < end, "quickstart markers are reversed")
    match = re.fullmatch(r"\s*```sh\n([^`]*?)\n```\s*", text[start:end])
    require(match is not None, "quickstart must contain exactly one fenced sh block")
    require(bool(match[1].strip()), "quickstart block is empty")
    return match[1] + "\n"


def read_records(directory, name):
    data = (directory / name).read_bytes()
    require(data.endswith(b"\n"), name + " lacks final newline")
    rows = [json.loads(line) for line in data.splitlines()]
    require(len(rows) == 101, name + " must contain 100 samples")
    version = "m31" if name == "journal.jsonl" else "m32"
    expected = {version: 1, "seed": SEED, "batch": 100, "plant": "none", "topcoat": PIN}
    require(rows[0] == expected and all(type(rows[0][k]) is int
            for k in (version, "seed", "batch")), name + " header mismatch")
    require(all(isinstance(row, dict) and type(row.get("i")) is int
                and row["i"] == i for i, row in enumerate(rows[1:])),
            name + " identities are missing or reordered")
    return rows[1:]


def validate(directory):
    rows = read_records(directory, "journal.jsonl")
    read_records(directory, "trace.jsonl")
    require({row["mode"] for row in rows} == {"read_only", "signal_writing"},
            "quickstart must exercise both modes")
    heads = [row["verdict"].split(":", 1)[0] for row in rows]
    require(set(heads) <= set(HEADS), "unknown verdict head")
    census = {head: heads.count(head) for head in HEADS}
    compared = adjudicated(census)
    require(compared >= FLOOR, f"only {compared} adjudicated rows, minimum {FLOOR}")
    require((directory / "run.txt").read_bytes() == (directory / "replay.txt").read_bytes(),
            "documented replay differs from run")
    return census


def adjudicated(census):
    return sum(census[head] for head in ADJUDICATED)


def checked_census(text, relative):
    """Read the WHOLE M32 check line, not only its prefix."""
    prefix = f"m32 check {relative}: 100 lines, "
    require(text.startswith(prefix),
            "the M32 check line does not report 100 lines of " + relative)
    fields = dict(item.split(" ", 1) for item in text[len(prefix):].strip().split(", "))
    return {key: int(value) for key, value in fields.items()}


def verify_correspondence(text, census, relative):
    """The M32 census must name no bug and must agree with the journal."""
    counts = checked_census(text, relative)
    require(counts.get("gen_bug") == 0 and counts.get("oracle_bug") == 0,
            f"the M32 check reports gen_bug {counts.get('gen_bug')} and "
            f"oracle_bug {counts.get('oracle_bug')}, both must be 0")
    for head, stage in STAGES.items():
        require(counts.get(stage) == census[head],
                f"M32 counted {counts.get(stage)} {stage} rows and the journal "
                f"holds {census[head]} {head} rows")


def truncated(data, keep):
    """The header plus the first [keep] sample rows of an evidence file."""
    lines = data.splitlines(keepends=True)
    require(len(lines) == 101, "evidence must hold 100 samples before truncation")
    return b"".join(lines[:keep + 1])


def verify_resume(directory, before, label):
    for name in EVIDENCE:
        require((directory / name).read_bytes() == before[name],
                f"{label} changed " + name)


def execute(root, logs, label, argv):
    with (logs / (label + ".stdout")).open("wb") as out, \
            (logs / (label + ".stderr")).open("wb") as err:
        result = subprocess.run(argv, cwd=root, stdout=out, stderr=err)
    (logs / (label + ".code")).write_text(str(result.returncode) + "\n")
    require(result.returncode == 0, f"{label} failed ({result.returncode}); logs: {logs}")
    return (logs / (label + ".stdout")).read_bytes()


def binary(root, name):
    return str(root / "_build/default/bin" / name)


def resume_argv(root, target):
    """The documented run command, under the switch the documented block uses."""
    return ["opam", "exec", f"--switch={SWITCH}", "--", binary(root, "m31.exe"),
            "run", target, "--samples", "100", "--seed", "0x4d3336",
            "--batch", "100", "--root", ".", "--clone", "../topcoat"]


def sibling(output, prefix, before, keep=None):
    """A fresh directory beside the smoke tree, at the same depth, holding a
    copy of the evidence.  A generated crate names its dependencies with a
    fixed prefix (shell/legs.ml:71), so the depth is part of the contract."""
    made = Path(tempfile.mkdtemp(prefix=prefix, dir=output))
    for name in EVIDENCE:
        data = before[name] if keep is None else truncated(before[name], keep)
        (made / name).write_bytes(data)
    return made


def verify_relocated_replay(root, logs, output, relative, before, summary):
    """Replay a COPY at another path.  A run and a replay of the SAME
    directory print the same bytes by construction (shell/pipeline.ml:530-533),
    so only a relocated replay can fail.  The journal path is the one
    permitted difference."""
    moved = sibling(output, "replay.", before)
    target = moved.relative_to(root).as_posix()
    printed = execute(root, logs, "relocated",
                      [binary(root, "m31.exe"), "replay", target])
    require(printed.replace(target.encode(), relative.encode()) == summary,
            "the relocated replay differs from the documented run beyond its path")


def verify_partial_resume(root, logs, output, before):
    """Truncate a copy of the evidence, resume THAT copy, and require the
    rebuilt bytes to equal the untruncated originals."""
    partial = sibling(output, "partial.", before, keep=KEPT)
    execute(root, logs, "partial",
            resume_argv(root, partial.relative_to(root).as_posix()))
    verify_resume(partial, before, "truncated resume")
    return partial


def run(root):
    script = quickstart((root / "README.md").read_text())
    emit = root / "_emit/m37"
    emit.mkdir(parents=True, exist_ok=True)
    logs = Path(tempfile.mkdtemp(prefix="gate.", dir=emit))
    output = emit / "out"
    prior = {path.resolve() for path in output.iterdir()} if output.exists() else set()
    (logs / "quickstart.sh").write_text(script)
    print(f"m37 quickstart running; logs: {logs}", flush=True)
    # -f keeps an ambient zshenv from unsetting err_exit or from shadowing a
    # command inside the documented block.
    stdout = execute(root, logs, "quickstart",
                     ["zsh", "-f", "-e", str(logs / "quickstart.sh")])
    paths = re.findall(rb"^Quickstart artifacts: (.+)$", stdout, re.MULTILINE)
    require(len(paths) == 1, "quickstart did not report exactly one artifact directory")
    relative = paths[0].decode()
    directory = (root / relative).resolve()
    require(not Path(relative).is_absolute() and directory.parent == output.resolve()
            and directory.name.startswith("smoke.") and directory not in prior,
            "quickstart did not create a fresh smoke directory")
    census = validate(directory)
    # Invoke the checker directly as well, so a printed success cannot replace
    # it.  The equality with check.txt is a determinism check on the documented
    # command; the census check below is the independent one.
    check = execute(root, logs, "check", [binary(root, "m32.exe"), "check", relative])
    require(check == (directory / "check.txt").read_bytes(),
            "documented checker output differs from the real M32 check")
    verify_correspondence(check.decode(), census, relative)
    before = {name: (directory / name).read_bytes() for name in EVIDENCE}
    for name, data in before.items():
        (logs / ("before." + name)).write_bytes(data)
    summary = execute(root, logs, "resume", resume_argv(root, relative))
    (directory / "resume.txt").write_bytes(summary)
    verify_resume(directory, before, "completed resume")
    verify_relocated_replay(root, logs, output, relative, before,
                            (directory / "run.txt").read_bytes())
    partial = verify_partial_resume(root, logs, output, before)
    print(f"M37 GATE GREEN: 100 samples, {adjudicated(census)} adjudicated "
          f"(agree {census['agree']}, known {census['known']}, "
          f"diverge {census['diverge']}), both modes; M32 correspondence, "
          f"relocated replay and a resume that rebuilt {100 - KEPT} rows "
          f"byte-identically; {directory} {partial}")


if __name__ == "__main__":
    try:
        require(len(sys.argv) == 3 and sys.argv[1] == "run",
                "usage: m37_verdict.py run <root>")
        run(Path(sys.argv[2]).resolve())
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        print(f"m37: RED {exc}", file=sys.stderr)
        sys.exit(1)
