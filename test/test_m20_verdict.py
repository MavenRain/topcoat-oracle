"""Cold Cargo progress must not hide or impersonate M20 Rust diagnostics."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROGRESS = "   Compiling thiserror v2.0.20\n   Compiling thiserror-impl v2.0.20\n"
NEGATIVE = "src/lib.rs:105:19: error: unsupported literal type\n"
SUMMARY = "error: could not compile `m20-batch` (lib) due to 1 previous error\n"


class Verdict(unittest.TestCase):
    def verdict(self, log, cargo_exit=101, span="100 110\n"):
        with tempfile.TemporaryDirectory() as scratch:
            directory = Path(scratch)
            logfile = directory / "cargo.log"
            sidecar = directory / "case_neg.span"
            logfile.write_text(log, encoding="utf-8")
            if span is not None:
                sidecar.write_text(span, encoding="utf-8")
            return subprocess.run(["zsh", str(ROOT / "m20_verdict.sh"),
                                   str(logfile), str(sidecar), str(cargo_exit)],
                                  text=True, capture_output=True)

    def red(self, log, reason, **kwargs):
        result = self.verdict(log, **kwargs)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("M20 GATE RED", result.stdout)
        self.assertIn(reason, result.stdout)
        self.assertNotIn("M20 GATE GREEN", result.stdout)

    def test_cold_progress_and_expected_rejection(self):
        result = self.verdict(PROGRESS + NEGATIVE + SUMMARY)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("M20 GATE GREEN: 2 error line(s)", result.stdout)

    def test_coded_error_at_each_span_boundary(self):
        for line in [100, 110]:
            with self.subTest(line=line):
                result = self.verdict(PROGRESS +
                    f"src/lib.rs:{line}:19: error[E0308]: mismatched types\n" + SUMMARY)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_progress_alone_cannot_pass_a_nonzero_exit(self):
        self.red(PROGRESS, "nonzero cargo exit but no error lines")

    def test_dependency_diagnostic_beside_expected_rejection(self):
        for diagnostic in ["dep/src/lib.rs:10:2: error: missing symbol\n",
                           "dep/src/lib.rs:10:2: error[E0425]: missing symbol\n"]:
            with self.subTest(diagnostic=diagnostic):
                self.red(PROGRESS + NEGATIVE + diagnostic + SUMMARY,
                         "error lines not attributed to src/lib.rs")

    def test_unlocated_errors_are_rejected(self):
        for diagnostic in ["error: failed to run a build script\n",
                           "error[E0308]: mismatched types\n",
                           "sccache: error: failed to execute compile\n",
                           "cargo: error: could not execute process\n",
                           "error\n"]:
            with self.subTest(diagnostic=diagnostic):
                self.red(PROGRESS + NEGATIVE + diagnostic + SUMMARY,
                         "error lines not attributed to src/lib.rs")

    def test_out_of_span_errors_are_rejected(self):
        for line in [99, 111]:
            for token in ["error", "error[E0308]"]:
                with self.subTest(line=line, token=token):
                    self.red(PROGRESS + NEGATIVE +
                             f"src/lib.rs:{line}:1: {token}: unexpected failure\n" + SUMMARY,
                             "rustc errors outside case_neg span")

    def test_cargo_summary_without_expected_rejection_is_red(self):
        self.red(PROGRESS + SUMMARY, "no case_neg reject inside span")

    def test_zero_exit_is_red_even_with_expected_rejection(self):
        self.red(PROGRESS + NEGATIVE + SUMMARY, "cargo exit 0", cargo_exit=0)

    def test_missing_or_empty_span_is_red(self):
        for span in [None, ""]:
            with self.subTest(span=span):
                self.red(PROGRESS + NEGATIVE + SUMMARY, "span sidecar missing or empty", span=span)


if __name__ == "__main__":
    unittest.main()
