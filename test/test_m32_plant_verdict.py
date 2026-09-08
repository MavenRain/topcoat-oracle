"""Pin recovered censuses and exact planted judge changes independently."""
import copy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "test"))
import m32_plant_verdict as gate
import test_m31_plant_verdict as fixture


def evidence():
    straight, planted = fixture.journals()
    ordinary = [i for i in range(100) if i not in fixture.gate.FLOATS]
    # First hundred: 76 agree, 12 diverge, 12 losses. The reference plant
    # moves eight of those agreements to rendered divergences.
    for indices, verdict in [(ordinary[:12], "leg_fail:js:no_line"),
                             (ordinary[12:23], "diverge:message:odd:js")]:
        for index in indices:
            straight[index + 1]["verdict"] = verdict
            planted[index + 1]["verdict"] = verdict
    for index in range(100, 142):
        straight[index + 1]["verdict"] = "diverge:message:odd:js"
    for index in range(142, 181):
        straight[index + 1]["verdict"] = "leg_fail:js:no_line"

    def trace(journal):
        rows = [{"m32": 1, **{k: v for k, v in journal[0].items() if k != "m31"}}]
        for row in journal[1:]:
            judge = {"agree": "judge_agree", "diverge": "judge_diverge",
                     "leg_fail": "judge_infra"}[row["verdict"].split(":", 1)[0]]
            rows.append({"i": row["i"], "steps": ["shape_ok", "print_ok", "compile_ok",
                "exec_rust_ok", "exec_js_ok", "exec_ref_ok", judge]})
        return rows

    reports = {
        "straight": "m32 check straight: 500 lines, dropped_agree 395, dropped_known 0, minimizing_hi 54, gen_bug 0, leg_failed 51, oracle_bug 0\n",
        "resume": "m32 check resume: 500 lines, dropped_agree 395, dropped_known 0, minimizing_hi 54, gen_bug 0, leg_failed 51, oracle_bug 0\n",
        "planted": "m32 check planted: 100 lines, dropped_agree 68, dropped_known 0, minimizing_hi 20, gen_bug 0, leg_failed 12, oracle_bug 0\n",
    }
    return [straight, planted, trace(straight), trace(planted), reports]


class Correspondence(unittest.TestCase):
    def setUp(self):
        self.data = evidence()

    def check(self):
        gate.check(*self.data)

    def test_exact_census_and_eight_judge_changes(self):
        self.check()

    def test_wrong_journal_census_cannot_match_a_forged_report(self):
        self.data[0][500]["verdict"] = "leg_fail:js:no_line"
        for name in ["straight", "resume"]:
            self.data[4][name] = self.data[4][name].replace("agree 395", "agree 394").replace("failed 51", "failed 52")
        with self.assertRaisesRegex(ValueError, "journal census mismatch: straight"):
            self.check()

    def test_report_mismatch_is_rejected_for_each_run(self):
        for name in ["straight", "resume", "planted"]:
            with self.subTest(name=name):
                original = self.data[4][name]
                self.data[4][name] = original.replace("oracle_bug 0", "oracle_bug 1")
                with self.assertRaisesRegex(ValueError, "report disagrees with journal census: " + name):
                    self.check()
                self.data[4][name] = original

    def test_extra_report_line_is_rejected(self):
        self.data[4]["straight"] *= 2
        with self.assertRaisesRegex(ValueError, "report disagrees with journal census"):
            self.check()

    def test_wrong_trace_count_is_rejected(self):
        self.data[3].pop()
        with self.assertRaisesRegex(ValueError, "trace count mismatch: planted"):
            self.check()

    def test_wrong_or_float_trace_index_is_rejected(self):
        for index in [8, 7.0]:
            with self.subTest(index=index):
                self.data[3][8]["i"] = index
                with self.assertRaisesRegex(ValueError, "trace index mismatch: planted:7"):
                    self.check()

    def test_expected_judge_change_cannot_be_skipped_or_changed(self):
        for step in ["judge_agree", "judge_known", "judge_infra"]:
            with self.subTest(step=step):
                self.data[3][8]["steps"][-1] = step
                with self.assertRaisesRegex(ValueError, "plant judge transition mismatch: 7"):
                    self.check()

    def test_earlier_trace_step_cannot_change(self):
        self.data[3][8]["steps"][4] = "exec_js_crash"
        with self.assertRaisesRegex(ValueError, "plant changed steps before judge: 7"):
            self.check()

    def test_same_number_of_changes_at_wrong_indices_is_rejected(self):
        self.data[3][8]["steps"][-1] = "judge_agree"
        self.data[3][2]["steps"][-1] = "judge_diverge"
        with self.assertRaisesRegex(ValueError, "unexpected trace mutation: 1"):
            self.check()

    def test_index16_and_other_unchanged_rows_cannot_change(self):
        for index in [16, 90]:
            with self.subTest(index=index):
                original = copy.deepcopy(self.data[3][index + 1])
                self.data[3][index + 1]["steps"][-1] = "judge_known"
                with self.assertRaisesRegex(ValueError, "unexpected trace mutation: " + str(index)):
                    self.check()
                self.data[3][index + 1] = original

    def test_trace_header_is_bound_to_its_own_journal_header(self):
        for key, changed in [("plant", "none"), ("m32", 2),
                             ("seed", 1), ("batch", 1)]:
            with self.subTest(key=key):
                original = self.data[3][0][key]
                self.data[3][0][key] = changed
                with self.assertRaisesRegex(ValueError, "trace header mismatch: planted"):
                    self.check()
                self.data[3][0][key] = original

    def test_trace_header_integers_cannot_be_floats(self):
        # The header equality accepts 5059377.0, so the type loop is the guard.
        self.data[3][0]["seed"] = float(self.data[3][0]["seed"])
        with self.assertRaisesRegex(ValueError, "trace header integer mismatch: seed"):
            self.check()

    def test_trace_types_and_keys_are_exact(self):
        original = copy.deepcopy(self.data[3][8])
        for changed in [{**original, "extra": 1}, {**original, "steps": [False]},
                        {**original, "steps": "judge_diverge"}]:
            with self.subTest(changed=changed):
                self.data[3][8] = changed
                with self.assertRaisesRegex(ValueError, "trace (row shape|step type) mismatch"):
                    self.check()


if __name__ == "__main__":
    unittest.main()
