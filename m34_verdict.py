#!/usr/bin/env python3
"""Check archived campaign evidence independently of the OCaml aggregator."""

from collections import Counter
import gzip
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def source_inventory(root):
    patterns = ["core/*.ml", "shell/*.ml", "model/*.ml", "driver-js/*.mjs",
                "driver-js/lib/*.mjs", "driver-rs/**/*.rs"]
    names = {str(path.relative_to(root)) for pattern in patterns for path in root.glob(pattern)}
    names.update(["bin/m31.ml", "bin/m34_slice.ml", "m34_campaign.py",
                  "driver-js/package.json", "driver-js/package-lock.json"])
    return names


def load_evidence(root, out):
    archive = root / "research/campaign-1"
    meta = json.loads((archive / "provenance.json").read_text())
    require(meta["format"] == 1, "unsupported evidence format")
    require(re.fullmatch(r"[0-9a-f]{40}", meta["oracle_revision"]) is not None,
            "missing oracle revision")
    require(set(meta["sources"]) == source_inventory(root), "incomplete source inventory")
    for name, expected in meta["sources"].items():
        path = Path(name)
        require(not path.is_absolute() and ".." not in path.parts,
                "unsafe source path")
        require(sha((root / path).read_bytes()) == expected,
                "campaign source changed: " + name + "; renew the evidence")
    require(bool(meta["sources"]), "missing source fingerprints")
    for name in ["journal.jsonl.gz", "trace.jsonl.gz", "plants.txt"]:
        require(sha((archive / name).read_bytes()) == meta["files"][name],
                "archive digest mismatch: " + name)
    journal = gzip.decompress((archive / "journal.jsonl.gz").read_bytes())
    trace = gzip.decompress((archive / "trace.jsonl.gz").read_bytes())
    require(sha(journal) == meta["journal_sha256"], "journal digest mismatch")
    require(sha(trace) == meta["trace_sha256"], "trace digest mismatch")
    jlines = [json.loads(line) for line in journal.splitlines()]
    tlines = [json.loads(line) for line in trace.splitlines()]
    header, rows = jlines[0], jlines[1:]
    require(header["plant"] == "none", "baseline is planted")
    require(header["seed"] == meta["seed"] and header["batch"] == meta["batch"],
            "run parameters disagree")
    require(header["topcoat"] == meta["topcoat_revision"], "target revision disagrees")
    require(len(rows) == meta["samples"] and len(rows) >= 5000, "short campaign")
    require(len(tlines) == len(jlines), "trace length disagrees")
    require([row["i"] for row in rows] == list(range(len(rows))), "index gap")
    require(set(row["mode"] for row in rows) == {"read_only", "signal_writing"},
            "campaign does not contain both modes")
    if not (out / "archive").exists():
        (out / "archive").mkdir(parents=True)
    (out / "archive/journal.jsonl").write_bytes(journal)
    (out / "archive/trace.jsonl").write_bytes(trace)
    return header, rows, jlines, tlines


def summary_line(text, prefix):
    matches = [line for line in text.splitlines() if line.startswith(prefix)]
    require(len(matches) == 1, "missing or repeated report summary: " + prefix)
    fields = matches[0].split()[1:]
    require(len(fields) % 2 == 0, "odd summary fields")
    return {fields[i]: int(fields[i + 1]) for i in range(0, len(fields), 2)}


def uncode(text):
    require(text.startswith("<code>") and text.endswith("</code>"), "bad table code cell")
    return html.unescape(text[6:-7])


def check_report(header, rows, report):
    modes = Counter(row["mode"] for row in rows)
    require(summary_line(report, "m34 samples ") == {"samples": len(rows), **modes},
            "mode census disagrees with journal")
    heads = Counter(row["verdict"].split(":", 1)[0] for row in rows)
    keys = ["agree", "known", "diverge", "leg_fail", "dropped", "no_line", "batch_fail", "other"]
    require(summary_line(report, "m34 agree ") == {k: heads[k] for k in keys},
            "verdict totals disagree with journal")
    require(sum(heads[k] for k in keys) == len(rows), "unrecognized verdict head")
    compared = sum(heads[k] for k in ["agree", "known", "diverge"])
    require(compared > 0, "all campaign rows were lost")
    require(summary_line(report, "m34 adjudicated ") ==
            {"adjudicated": compared, "losses": len(rows) - compared},
            "adjudication census disagrees")
    census = {}
    members = []
    group_keys = set()
    firsts = []
    section = ""
    for line in report.splitlines():
        if line.startswith("## "):
            section = line
        if not line.startswith("| <code>"):
            continue
        fields = [x.strip() for x in line.split("|")[1:-1]]
        if section == "## Verdict census" and len(fields) == 2:
            verdict = uncode(fields[0])
            require(verdict not in census, "duplicate census row")
            census[verdict] = int(fields[1])
        elif section == "## Unexcused divergence groups" and len(fields) == 7:
            mode, verdict = uncode(fields[0]), uncode(fields[1])
            indices = [int(x) for x in uncode(fields[5]).split(",")]
            require(indices == sorted(set(indices)) and indices, "bad member order")
            require(all(0 <= i < len(rows) for i in indices), "member outside campaign")
            require(int(fields[2]) == len(indices), "group size disagrees")
            require(uncode(fields[3]) == str(header["seed"]) + ":" + str(indices[0]),
                    "representative is not the first group member")
            require(int(fields[4]) == min(rows[i]["size"] for i in indices),
                    "group minimum size disagrees")
            require(verdict.startswith("diverge:") and
                    all(rows[i]["mode"] == mode and rows[i]["verdict"] == verdict for i in indices),
                    "group merges different verdicts or modes")
            key = (mode, verdict, uncode(fields[6]))
            require(key not in group_keys, "duplicate construct group")
            group_keys.add(key)
            firsts.append(indices[0])
            members.extend(indices)
    expected_census = dict(Counter(row["verdict"] for row in rows))
    expected_census.setdefault("agree", 0)
    require(census == expected_census, "complete reason histogram disagrees")
    expected_members = [row["i"] for row in rows if row["verdict"].startswith("diverge:")]
    require(sorted(members) == expected_members, "divergences are missing or repeated")
    require(firsts == sorted(firsts), "groups are not in first appearance order")
    require(summary_line(report, "m34 groups ") ==
            {"groups": len(group_keys), "members": len(expected_members)},
            "dedup census disagrees")


def write_jsonl(path, rows):
    # The OCaml JSON subset accepts literal UTF-8 and its six escapes, not \u.
    path.write_text("".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n"
                            for row in rows))


def negatives(root, out, jlines, tlines):
    binary = root / "_build/default/bin/m34.exe"
    for name in ["body", "trace", "plant", "short", "verdict"]:
        directory = out / ("negative-" + name)
        directory.mkdir(exist_ok=True)
        js = json.loads(json.dumps(jlines))
        ts = json.loads(json.dumps(tlines))
        extra = []
        if name == "body":
            js[1]["body"] += " "
        elif name == "trace":
            ts[-1]["steps"] = []
        elif name == "plant":
            js[0]["plant"] = ts[0]["plant"] = "ref:display_sign"
        elif name == "short":
            extra = ["--minimum", str(len(jlines))]
        elif name == "verdict":
            js[1]["verdict"] = "agree:invented"
        write_jsonl(directory / "journal.jsonl", js)
        write_jsonl(directory / "trace.jsonl", ts)
        result = subprocess.run([str(binary), "report", str(directory), *extra], capture_output=True)
        require(result.returncode == 1 and not result.stdout and result.stderr,
                "corruption control accepted or wrote success output: " + name)
        (directory / "stderr.txt").write_bytes(result.stderr)


def main():
    require(len(sys.argv) == 4 and sys.argv[1] in ["prepare", "check"],
            "usage: m34_verdict.py prepare|check ROOT OUT")
    root, out = Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve()
    header, rows, jlines, tlines = load_evidence(root, out)
    if sys.argv[1] == "check":
        check_report(header, rows, (out / "report.md").read_text())
        plants = (root / "research/campaign-1/plants.txt").read_text().splitlines()
        require(len(plants) == 2, "missing corpus plant witnesses")
        for line, plant, op in zip(plants, ["ref:add_sign", "ref:length_plus_one"],
                                   ["f_add", "f_of_int"]):
            match = re.fullmatch(r"m34 plant " + plant + " op " + op +
                                 r" index ([0-9]+) control agree planted (diverge:(?:value|rendered):odd:ref|diverge:signals:two_way)", line)
            require(match is not None, "invalid corpus plant evidence")
            index = int(match.group(1))
            require(0 <= index < len(rows) and rows[index]["verdict"] == "agree",
                    "plant lacks baseline agreement")
            mode = rows[index]["mode"]
            allowed = {"diverge:value:odd:ref", "diverge:rendered:odd:ref"} if mode == "read_only" else set()
            if mode == "signal_writing" and plant == "ref:add_sign":
                allowed = {"diverge:signals:two_way"}
            require(match.group(2) in allowed, "plant verdict does not match its mode or operation")
        negatives(root, out, jlines, tlines)
        print("m34_verdict: GREEN")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, IndexError, EOFError) as error:
        print("m34_verdict: RED " + str(error), file=sys.stderr)
        sys.exit(1)
