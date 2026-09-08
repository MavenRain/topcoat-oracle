#!/usr/bin/env python3
"""Pin M39's recovered M31 census and its eight corresponding judge changes."""
from collections import Counter
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import m31_plant_verdict as plant


CENSUS = {
    "straight": {"agree": 395, "diverge": 54, "leg_fail": 51},
    "planted": {"agree": 68, "diverge": 20, "leg_fail": 12},
}
CHANGED = frozenset(plant.FLOATS) - {16}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def trace_shape(trace, journal, name):
    require(len(trace) == len(journal), "trace count mismatch: " + name)
    header = {"m32": 1, **{k: v for k, v in journal[0].items() if k != "m31"}}
    require(trace[0] == header, "trace header mismatch: " + name)
    for key in ["m32", "seed", "batch"]:
        require(type(trace[0][key]) is int, "trace header integer mismatch: " + key)
    for index, row in enumerate(trace[1:]):
        require(isinstance(row, dict) and set(row) == {"i", "steps"},
                f"trace row shape mismatch: {name}:{index}")
        require(type(row["i"]) is int and row["i"] == index,
                f"trace index mismatch: {name}:{index}")
        require(type(row["steps"]) is list and bool(row["steps"])
                and all(type(step) is str for step in row["steps"]),
                f"trace step type mismatch: {name}:{index}")


def census(journal, name):
    counts = Counter(row["verdict"].split(":", 1)[0] for row in journal[1:])
    require(counts == CENSUS[name], "journal census mismatch: " + name)
    return counts


def report_matches(report, rows, counts, name):
    expected = (f"{rows} lines, dropped_agree {counts['agree']}, dropped_known 0, "
                f"minimizing_hi {counts['diverge']}, gen_bug 0, "
                f"leg_failed {counts['leg_fail']}, oracle_bug 0")
    match = re.fullmatch(r"m32 check [^:\n]+: (.*)\n", report)
    require(match is not None and match.group(1) == expected,
            "report disagrees with journal census: " + name)


def check(straight, planted, straight_trace, planted_trace, reports):
    # This independently checks the nine reference sign changes and derives
    # the eight verdict transitions before their trace changes are accepted.
    plant.check(straight, planted)
    for name, journal, trace in [("straight", straight, straight_trace),
                                 ("planted", planted, planted_trace)]:
        trace_shape(trace, journal, name)
        counts = census(journal, name)
        report_matches(reports[name], len(journal) - 1, counts, name)
        if name == "straight":
            report_matches(reports["resume"], len(journal) - 1, counts, "resume")
    for index, (before, after) in enumerate(zip(straight_trace[1:101], planted_trace[1:])):
        if index in CHANGED:
            require(before["steps"][:-1] == after["steps"][:-1],
                    f"plant changed steps before judge: {index}")
            require(before["steps"][-1] == "judge_agree"
                    and after["steps"][-1] == "judge_diverge",
                    f"plant judge transition mismatch: {index}")
        else:
            require(before == after, f"unexpected trace mutation: {index}")


def main():
    require(len(sys.argv) == 3, "usage: m32_plant_verdict.py M32_OUT M31_OUT")
    out, prior = Path(sys.argv[1]), Path(sys.argv[2])
    check(plant.read_journal(prior / "straight/journal.jsonl"),
          plant.read_journal(prior / "planted/journal.jsonl"),
          plant.read_journal(prior / "straight/trace.jsonl"),
          plant.read_journal(prior / "planted/trace.jsonl"),
          {name: (out / (name + ".stdout")).read_text(encoding="utf-8")
           for name in ["straight", "resume", "planted"]})
    print("m32_plant_verdict: GREEN: exact journal/report censuses, 8 judge_agree to judge_diverge transitions")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError) as error:
        print("m32_plant_verdict: RED " + str(error), file=sys.stderr)
        sys.exit(1)
