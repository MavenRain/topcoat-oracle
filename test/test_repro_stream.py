"""The mapping gate must reject holes, duplicates, stale evidence and tampering."""
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import m35_verdict as gate

ORACLE_SHA = "abcdef0123456789abcdef0123456789abcdef01"


class Stub:
    """One subprocess result, so a replay polarity test needs no binary."""

    def __init__(self, returncode, stderr):
        self.returncode = returncode
        self.stderr = stderr
        self.stdout = ""


class Mapping(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        campaign = self.root / "research/campaign-1/journal.jsonl.gz"
        campaign.parent.mkdir(parents=True)
        campaign.write_bytes(b"campaign evidence")
        self.archive = self.root / "repros/campaign-1"
        for i in [4, 9]:
            directory = self.archive / str(i)
            directory.mkdir(parents=True)
            for name in gate.FILES:
                (directory / name).write_text(f"case {i} {name}\n")
        self.meta = {"format": 1, "indices": [4, 9], "oracle_sha": ORACLE_SHA,
                     "sources": {"code": "abc"},
                     "campaign_sha256": gate.digest(campaign),
                     "files": {f"{i}/{name}": gate.digest(self.archive / str(i) / name)
                               for i in [4, 9] for name in gate.FILES}}
        (self.archive / "manifest.json").write_text(json.dumps(self.meta))
        mocked = patch.object(gate, "sources", return_value={"code": "abc"})
        mocked.start()
        self.addCleanup(mocked.stop)

    def check(self, meta=None):
        gate.check_mapping(self.root, [4, 9], self.meta if meta is None else meta)

    def test_complete_mapping(self):
        self.check()

    def test_missing_repro(self):
        (self.archive / "9").rename(self.root / "missing")
        with self.assertRaisesRegex(ValueError, "missing or extra"):
            self.check()

    def test_extra_agree_or_known_repro(self):
        (self.archive / "7").mkdir()
        with self.assertRaisesRegex(ValueError, "missing or extra"):
            self.check()

    def test_duplicate_identity(self):
        """One directory can never answer for two campaign divergences."""
        shutil.rmtree(self.archive / "9")
        altered = copy.deepcopy(self.meta)
        altered["indices"] = [4, 4]
        altered["files"] = {f"4/{name}": gate.digest(self.archive / "4" / name)
                            for name in gate.FILES}
        with self.assertRaisesRegex(ValueError, "duplicate divergence index"):
            gate.check_mapping(self.root, [4, 4], altered)

    def test_manifest_without_oracle_sha(self):
        altered = copy.deepcopy(self.meta)
        altered["oracle_sha"] = "not a sha"
        with self.assertRaisesRegex(ValueError, "oracle sha"):
            self.check(altered)

    def test_replay_refuses_a_wrong_refusal(self):
        """A control that exits non-zero for another cause is not a control."""
        good = Stub(1, "m35: walk shape mismatch\n")
        with patch.object(gate.subprocess, "run", return_value=good):
            gate.replay(self.root, 4, self.archive / "4", ORACLE_SHA,
                        good=False, reason="walk shape mismatch")
            with self.assertRaisesRegex(ValueError, "corruption accepted or wrong refusal"):
                gate.replay(self.root, 4, self.archive / "4", ORACLE_SHA,
                            good=False, reason="walk metadata mismatch")

    def test_replay_polarity(self):
        with patch.object(gate.subprocess, "run", return_value=Stub(0, "")):
            with self.assertRaisesRegex(ValueError, "corruption accepted"):
                gate.replay(self.root, 4, self.archive / "4", ORACLE_SHA,
                            good=False, reason="walk shape mismatch")
            gate.replay(self.root, 4, self.archive / "4", ORACLE_SHA)
        with patch.object(gate.subprocess, "run", return_value=Stub(1, "m35: boom\n")):
            with self.assertRaisesRegex(ValueError, "replay 4"):
                gate.replay(self.root, 4, self.archive / "4", ORACLE_SHA)

    def test_missing_fingerprint(self):
        altered = copy.deepcopy(self.meta)
        del altered["files"]["9/js.jsonl"]
        with self.assertRaisesRegex(ValueError, "fingerprint inventory"):
            self.check(altered)

    def test_tampered_witness(self):
        (self.archive / "9/js.jsonl").write_text("forged\n")
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            self.check()

    def test_stale_sources(self):
        altered = copy.deepcopy(self.meta)
        altered["sources"]["code"] = "new"
        with self.assertRaisesRegex(ValueError, "sources changed"):
            self.check(altered)

    def test_different_campaign(self):
        altered = copy.deepcopy(self.meta)
        altered["campaign_sha256"] = "different"
        with self.assertRaisesRegex(ValueError, "campaign archive changed"):
            self.check(altered)


    def test_publisher_refuses_stale_live_receipt(self):
        receipt = self.root / "_emit/m35/completed.json"
        receipt.parent.mkdir(parents=True)
        receipt.write_text(json.dumps({"sources": {"producer": "old"},
                                       "executable_sha256": "old"}))
        with patch.object(gate, "expected", return_value=[4, 9]), \
             patch.object(gate, "execution_sources", return_value={"producer": "new"}):
            with self.assertRaisesRegex(ValueError, "live producer sources changed"):
                gate.publish(self.root)

    def test_publisher_requires_completed_run(self):
        with patch.object(gate, "expected", return_value=[4, 9]):
            with self.assertRaises(FileNotFoundError):
                gate.publish(self.root)


if __name__ == "__main__":
    unittest.main()
