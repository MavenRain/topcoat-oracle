#!/usr/bin/env python3
"""Check the M31 reference display plant against its fixed seed witnesses."""
import json
from pathlib import Path
import sys


HEADER = {"m31": 1, "seed": 5059377, "batch": 100, "plant": "none",
          "topcoat": "51caa01dca3a8f20bdacfa771b1b8ac8b6f2668a"}
ROW_KEYS = {"i", "mode", "size", "verdict", "r", "j", "f", "env", "body"}
# The nine displayed floats at seed 0x4d3331, before the plant flips
# f_display's sign bit. Their value bits and final signals do not change.
FLOATS = {
    7: (1069128089, 2576980378, "0.1"),
    16: (4293918720, 0, "-inf"),
    24: (1132161460, 3127054133, "123456789012345680"),
    34: (1073217536, 0, "1.5"),
    60: (1055193269, 2296604913, "0.00001"),
    71: (1132161460, 3127054133, "123456789012345680"),
    72: (1072483532, 3435973837, "0.9"),
    75: (1072693248, 0, "1"),
    82: (1132161460, 3127054133, "123456789012345680"),
}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, "duplicate JSON key: " + key)
        value[key] = item
    return value


def read_journal(path):
    raw = path.read_bytes()
    require(raw.endswith(b"\n"), "journal lacks final newline")
    return [json.loads(line, object_pairs_hook=unique_object) for line in raw.splitlines()]


def shape(journal, count, plant):
    require(len(journal) == count + 1, "journal sample count mismatch: " + plant)
    require(journal[0] == {**HEADER, "plant": plant}, "journal header mismatch: " + plant)
    for key in ["m31", "seed", "batch"]:
        require(type(journal[0][key]) is int, "invalid header integer: " + key)
    for index, row in enumerate(journal[1:]):
        require(isinstance(row, dict) and set(row) == ROW_KEYS,
                f"row shape mismatch: {plant}:{index}")
        require(type(row["i"]) is int and row["i"] == index,
                f"row index mismatch: {plant}:{index}")
        require(type(row["size"]) is int, f"row size type mismatch: {plant}:{index}")
        for key in ["mode", "verdict", "r", "j", "f", "body"]:
            require(type(row[key]) is str, f"row {key} type mismatch: {plant}:{index}")
        require(type(row["env"]) is list and all(type(item) is str for item in row["env"]),
                f"row env type mismatch: {plant}:{index}")


def flipped_reference(index, baseline):
    hi, lo, rendered = FLOATS[index]
    prefix = f"Vf{hi}:{lo};|r{len(rendered)}:{rendered}|"
    require(baseline.startswith(prefix), f"baseline float witness mismatch: {index}")
    flipped = rendered[1:] if rendered.startswith("-") else "-" + rendered
    return f"Vf{hi}:{lo};|r{len(flipped)}:{flipped}|" + baseline[len(prefix):]


def check(straight, planted):
    shape(straight, 500, "none")
    shape(planted, 100, "ref:display_sign")
    for index, (before, after) in enumerate(zip(straight[1:101], planted[1:])):
        for key in ROW_KEYS - {"f", "verdict"}:
            require(before[key] == after[key], f"plant changed {key}: {index}")
        if index not in FLOATS:
            require(before["f"] == after["f"], f"unexpected reference mutation: {index}")
            require(before["verdict"] == after["verdict"], f"unexpected verdict mutation: {index}")
            continue
        require(before["mode"] == "read_only", f"plant witness mode mismatch: {index}")
        require(after["f"] == flipped_reference(index, before["f"]),
                f"reference sign mutation mismatch: {index}")
        require(before["r"] == before["f"], f"baseline Rust/reference mismatch: {index}")
        if index == 16:
            # JS panics here, while Rust and the reference return -infinity.
            # Outcome precedes rendered text, so the original split remains.
            require(before["j"].startswith("P"), "baseline JS outcome mismatch: 16")
            original = changed = "diverge:outcome:odd:js"
        else:
            # All channels initially agree. Only reference rendering moves,
            # so the three-party comparison has reference as the odd leg.
            require(before["j"] == before["f"], f"baseline JS/reference mismatch: {index}")
            original, changed = "agree", "diverge:rendered:odd:ref"
        require(before["verdict"] == original, f"baseline verdict mismatch: {index}")
        require(after["verdict"] == changed, f"planted verdict mismatch: {index}")


def main():
    require(len(sys.argv) == 3, "usage: m31_plant_verdict.py STRAIGHT PLANTED")
    check(read_journal(Path(sys.argv[1])), read_journal(Path(sys.argv[2])))
    print("m31_plant_verdict: GREEN: 9 reference sign changes, 8 rendered verdict changes, outcome split preserved")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError) as error:
        print("m31_plant_verdict: RED " + str(error), file=sys.stderr)
        sys.exit(1)
