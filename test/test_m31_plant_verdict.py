"""Reference plant checks must preserve programs, product legs and verdict order."""
import copy
from pathlib import Path
import tempfile
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import m31_plant_verdict as gate


def journals():
    straight = [dict(gate.HEADER)]
    for index in range(500):
        row = {"i": index, "mode": "read_only", "size": 5, "verdict": "agree",
               "r": "Vb1|r4:true|", "j": "Vb1|r4:true|", "f": "Vb1|r4:true|",
               "env": ["inputs and signals"], "body": "program " + str(index)}
        if index in gate.FLOATS:
            hi, lo, rendered = gate.FLOATS[index]
            observation = f"Vf{hi}:{lo};|r{len(rendered)}:{rendered}|g3:s3:a|b"
            row.update(r=observation, j=observation, f=observation)
            if index == 16:
                row.update(j="Pexpect:4:boom|r0:|g3:s3:a|b", verdict="diverge:outcome:odd:js")
        straight.append(row)
    planted = copy.deepcopy(straight[:101])
    planted[0]["plant"] = "ref:display_sign"
    for index, (hi, lo, text) in gate.FLOATS.items():
        flipped = text.removeprefix("-") if text.startswith("-") else "-" + text
        planted[index + 1]["f"] = f"Vf{hi}:{lo};|r{len(flipped)}:{flipped}|g3:s3:a|b"
        if index != 16:
            planted[index + 1]["verdict"] = "diverge:rendered:odd:ref"
    return straight, planted


class Plant(unittest.TestCase):
    def setUp(self):
        self.straight, self.planted = journals()

    def check(self):
        gate.check(self.straight, self.planted)

    def test_correct_plant_and_outcome_precedence(self):
        self.check()

    def test_program_environment_size_and_mode_cannot_change(self):
        for key, changed in [("body", "forged program"), ("env", ["forged environment"]),
                             ("size", 6), ("mode", "signal_writing")]:
            with self.subTest(key=key):
                original = self.planted[8][key]
                self.planted[8][key] = changed
                with self.assertRaisesRegex(ValueError, "plant changed " + key):
                    self.check()
                self.planted[8][key] = original

    def test_neither_product_leg_can_change(self):
        for key in ["r", "j"]:
            with self.subTest(key=key):
                original = self.planted[8][key]
                self.planted[8][key] = self.planted[8]["f"]
                with self.assertRaisesRegex(ValueError, "plant changed " + key):
                    self.check()
                self.planted[8][key] = original

    def test_size_integer_cannot_be_replaced_by_equal_float(self):
        self.planted[8]["size"] = float(self.straight[8]["size"])
        with self.assertRaisesRegex(ValueError, "row size type mismatch"):
            self.check()

    def test_boolean_cannot_impersonate_an_integer(self):
        self.straight[8]["size"] = 1
        self.planted[8]["size"] = True
        with self.assertRaisesRegex(ValueError, "row size type mismatch"):
            self.check()
        self.planted[8]["size"] = 1
        self.planted[1]["i"] = False
        with self.assertRaisesRegex(ValueError, "row index mismatch"):
            self.check()

    def test_environment_requires_a_list_of_strings(self):
        for env in ["inputs and signals", [True], [1], [1.0], [["nested"]]]:
            with self.subTest(env=env):
                self.planted[8]["env"] = env
                with self.assertRaisesRegex(ValueError, "row env type mismatch"):
                    self.check()

    def test_observation_and_program_fields_require_strings(self):
        for key in ["mode", "verdict", "r", "j", "f", "body"]:
            with self.subTest(key=key):
                original = self.planted[8][key]
                self.planted[8][key] = None
                with self.assertRaisesRegex(ValueError, "row " + key + " type mismatch"):
                    self.check()
                self.planted[8][key] = original

    def test_new_rendered_divergence_cannot_be_suppressed(self):
        self.planted[8]["verdict"] = "agree"
        with self.assertRaisesRegex(ValueError, "planted verdict mismatch: 7"):
            self.check()

    def test_earlier_outcome_divergence_cannot_be_replaced(self):
        self.planted[17]["verdict"] = "diverge:rendered:odd:ref"
        with self.assertRaisesRegex(ValueError, "planted verdict mismatch: 16"):
            self.check()

    def test_unaffected_verdict_cannot_change(self):
        self.planted[1]["verdict"] = "diverge:rendered:odd:ref"
        with self.assertRaisesRegex(ValueError, "unexpected verdict mutation: 0"):
            self.check()

    def test_skipped_reference_plant_is_rejected(self):
        self.planted[8]["f"] = self.straight[8]["f"]
        with self.assertRaisesRegex(ValueError, "reference sign mutation mismatch: 7"):
            self.check()

    def test_reference_value_render_length_and_signals_cannot_change(self):
        original = self.planted[8]["f"]
        for changed in [original.replace("1069128089", "1069128088"),
                        original.replace("r4:-0.1", "r4:-0.2"),
                        original.replace("r4:-0.1", "r3:-0.1"),
                        original.replace("g3:s3:a|b", "g3:s3:a|c"), ""]:
            with self.subTest(changed=changed):
                self.planted[8]["f"] = changed
                with self.assertRaisesRegex(ValueError, "reference sign mutation mismatch: 7"):
                    self.check()
        self.planted[8]["f"] = original

    def test_extra_reference_mutation_is_rejected(self):
        self.planted[1]["f"] += "forged"
        with self.assertRaisesRegex(ValueError, "unexpected reference mutation: 0"):
            self.check()

    def test_count_and_index_changes_are_rejected(self):
        original = copy.deepcopy(self.planted)
        for changed in [original[:-1], original + [original[-1]], original[:8] + original[9:]]:
            with self.subTest(count=len(changed)):
                self.planted = changed
                with self.assertRaisesRegex(ValueError, "journal sample count mismatch"):
                    self.check()
        self.planted = original
        self.planted[8]["i"] = 8
        with self.assertRaisesRegex(ValueError, "row index mismatch"):
            self.check()

    def test_baseline_float_and_leg_agreement_are_checked(self):
        original = copy.deepcopy(self.straight)
        for key, changed, reason in [
                ("f", "Vf0:0;|r1:0|", "baseline float witness mismatch"),
                ("j", "", "baseline JS/reference mismatch"),
                ("r", "", "baseline Rust/reference mismatch"),
                ("verdict", "leg_fail:js:no_line", "baseline verdict mismatch")]:
            with self.subTest(key=key):
                self.straight = copy.deepcopy(original)
                self.straight[8][key] = changed
                # Product cells must match across runs before the independent
                # baseline-witness relation is reached.
                if key in ["r", "j"]:
                    self.planted[8][key] = changed
                with self.assertRaisesRegex(ValueError, reason):
                    self.check()
                self.planted[8]["r"] = original[8]["r"]
                self.planted[8]["j"] = original[8]["j"]

    def test_header_integers_cannot_be_floats_or_booleans(self):
        # The header equality accepts 5059377.0 and True, so the type loop is
        # the only guard on these fields.
        for journal, key, changed in [(self.straight, "seed", 5059377.0),
                                      (self.planted, "m31", True)]:
            with self.subTest(key=key):
                original = journal[0][key]
                journal[0][key] = changed
                with self.assertRaisesRegex(ValueError, "invalid header integer: " + key):
                    self.check()
                journal[0][key] = original

    def test_a_witness_row_must_be_read_only_in_both_journals(self):
        for journal in [self.straight, self.planted]:
            journal[8]["mode"] = "signal_writing"
        with self.assertRaisesRegex(ValueError, "plant witness mode mismatch: 7"):
            self.check()

    def test_the_outcome_split_row_must_start_from_a_JS_panic(self):
        agreeing = self.straight[17]["f"]
        for journal in [self.straight, self.planted]:
            journal[17]["j"] = agreeing
        with self.assertRaisesRegex(ValueError, "baseline JS outcome mismatch: 16"):
            self.check()

    def test_header_plant_is_pinned(self):
        self.planted[0]["plant"] = "none"
        with self.assertRaisesRegex(ValueError, "journal header mismatch"):
            self.check()

    def test_duplicate_journal_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "journal.jsonl"
            path.write_text('{"i":7,"i":8}\n', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate JSON key: i"):
                gate.read_journal(path)


if __name__ == "__main__":
    unittest.main()
