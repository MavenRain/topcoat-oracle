"""Historical producers stay verifiable without weakening live evidence guards."""
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import archive_sources
import m34_verdict
import m35_verdict


REVISION = "9d8780b0947a9483d7f2bc28b11dd7d0fdabddee"


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class Sources(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.stored = {"core/a.ml": "let x = 1\n", "driver-js/worker.mjs": "// original\n"}
        self.manifests = {
            "campaign": {"sources": {"core/a.ml": digest(self.stored["core/a.ml"])}},
            "repros": {"sources": {name: digest(text) for name, text in self.stored.items()}},
        }
        self.write_manifests()
        self.write_snapshot()

    def write_manifests(self):
        for label, name in archive_sources.MANIFESTS.items():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(self.manifests[label]), encoding="utf-8")

    def write_snapshot(self, text=None):
        target = self.root / archive_sources.SNAPSHOT
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = (json.dumps({"format": 1, "revision": REVISION, "sources": self.stored})
                   if text is None else text)
        target.write_bytes(gzip.compress(payload.encode("utf-8"), mtime=0))

    def commit_sources(self, texts):
        """Commit one revision of the named sources; return its sha40."""
        for name, text in texts.items():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")
        env = dict(os.environ,
                   HOME=str(self.root), GIT_CONFIG_GLOBAL=os.devnull,
                   GIT_CONFIG_SYSTEM=os.devnull,
                   GIT_AUTHOR_NAME="archive test", GIT_COMMITTER_NAME="archive test",
                   GIT_AUTHOR_EMAIL="archive@example.invalid",
                   GIT_COMMITTER_EMAIL="archive@example.invalid")
        for argv in [["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "sources"]]:
            subprocess.run(["git", "-C", str(self.root)] + argv, check=True, env=env)
        head = subprocess.run(["git", "-C", str(self.root), "rev-parse", "HEAD"],
                              check=True, capture_output=True, text=True, env=env)
        return head.stdout.strip()

    def test_capture_refuses_a_revision_whose_blob_is_not_the_archived_source(self):
        forged = dict(self.stored)
        forged["core/a.ml"] = "let x = 2\n"
        revision = self.commit_sources(forged)
        with self.assertRaisesRegex(ValueError,
                                    "archived source digest mismatch: core/a.ml"):
            archive_sources.snapshot_bytes(self.root, revision)

    def test_capture_writes_a_snapshot_that_verify_accepts(self):
        revision = self.commit_sources(self.stored)
        target = self.root / archive_sources.SNAPSHOT
        target.unlink()
        archive_sources.capture(self.root, revision)
        self.assertEqual(archive_sources.verify(self.root),
                         {label: meta["sources"] for label, meta in self.manifests.items()})
        written = json.loads(gzip.decompress(target.read_bytes()).decode("utf-8"))
        self.assertEqual(written["revision"], revision)
        self.assertEqual(written["sources"], self.stored)

    def test_retained_bytes_survive_current_source_changes_without_git(self):
        current = self.root / "driver-js/worker.mjs"
        current.parent.mkdir()
        current.write_text("// changed current producer\n", encoding="utf-8")
        (current.parent / "new-module.mjs").write_text("// new source\n", encoding="utf-8")
        self.assertFalse((self.root / ".git").exists())
        self.assertEqual(archive_sources.verify(self.root),
                         {label: meta["sources"] for label, meta in self.manifests.items()})

    def test_modified_source(self):
        self.stored["core/a.ml"] += "let forged = true\n"
        self.write_snapshot()
        with self.assertRaisesRegex(ValueError, "source snapshot digest mismatch: core/a.ml"):
            archive_sources.verify(self.root)

    def test_missing_source(self):
        del self.stored["driver-js/worker.mjs"]
        self.write_snapshot()
        with self.assertRaisesRegex(ValueError, "source snapshot inventory mismatch"):
            archive_sources.verify(self.root)

    def test_extra_source(self):
        self.stored["core/extra.ml"] = "let extra = true\n"
        self.write_snapshot()
        with self.assertRaisesRegex(ValueError, "source snapshot inventory mismatch"):
            archive_sources.verify(self.root)

    def test_missing_manifest_entry(self):
        del self.manifests["repros"]["sources"]["driver-js/worker.mjs"]
        self.write_manifests()
        with self.assertRaisesRegex(ValueError, "source snapshot inventory mismatch"):
            archive_sources.verify(self.root)

    def test_conflicting_manifest_digests(self):
        self.manifests["repros"]["sources"]["core/a.ml"] = "0" * 64
        self.write_manifests()
        with self.assertRaisesRegex(ValueError, "conflicting archived source digest"):
            archive_sources.verify(self.root)

    def test_invalid_manifest_digest(self):
        self.manifests["repros"]["sources"]["driver-js/worker.mjs"] = "not a digest"
        self.write_manifests()
        with self.assertRaisesRegex(ValueError, "invalid source digest"):
            archive_sources.verify(self.root)

    def test_unsafe_manifest_and_snapshot_names(self):
        original = copy.deepcopy(self.manifests)
        for name in ["../escape.ml", "/absolute.ml", "core//a.ml", "core/./a.ml",
                     "core\\a.ml", "core/\0.ml", "", "."]:
            with self.subTest(name=name, location="manifest"):
                self.manifests = copy.deepcopy(original)
                self.manifests["repros"]["sources"][name] = "0" * 64
                self.write_manifests()
                with self.assertRaisesRegex(ValueError, "unsafe source path"):
                    archive_sources.verify(self.root)
            with self.subTest(name=name, location="snapshot"):
                self.manifests = copy.deepcopy(original)
                self.write_manifests()
                self.stored[name] = "unsafe"
                self.write_snapshot()
                with self.assertRaisesRegex(ValueError, "unsafe source path"):
                    archive_sources.verify(self.root)
                del self.stored[name]

    def test_duplicate_snapshot_keys(self):
        for text in ['{"format":1,"format":1,"sources":{}}',
                     '{"format":1,"sources":{"core/a.ml":"a","core/a.ml":"b"}}']:
            with self.subTest(text=text):
                self.write_snapshot(text)
                with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                    archive_sources.verify(self.root)

    def test_duplicate_manifest_keys(self):
        target = self.root / archive_sources.MANIFESTS["campaign"]
        target.write_text('{"sources":{},"sources":{}}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key: sources"):
            archive_sources.verify(self.root)

    def test_invalid_snapshot_format(self):
        for snapshot in [[], {"format": True, "revision": REVISION, "sources": self.stored},
                         {"format": 1, "sources": self.stored},
                         {"format": 1, "revision": REVISION, "sources": self.stored,
                          "extra": 1}]:
            with self.subTest(snapshot=snapshot):
                self.write_snapshot(json.dumps(snapshot))
                with self.assertRaisesRegex(ValueError, "unsupported source snapshot format"):
                    archive_sources.verify(self.root)

    def test_snapshot_revision_must_name_one_commit(self):
        for revision in [REVISION.upper(), REVISION[:39], REVISION + "0", "", 1, None]:
            with self.subTest(revision=revision):
                self.write_snapshot(json.dumps({"format": 1, "revision": revision,
                                                "sources": self.stored}))
                with self.assertRaisesRegex(ValueError, "invalid snapshot revision"):
                    archive_sources.verify(self.root)

    def test_capture_refuses_a_revision_that_is_not_a_sha40(self):
        for revision in [REVISION.upper(), REVISION[:39], "HEAD", "", None]:
            with self.subTest(revision=revision):
                with self.assertRaisesRegex(ValueError, "invalid snapshot revision"):
                    archive_sources.snapshot_bytes(self.root, revision)

    def test_snapshot_requires_text(self):
        self.stored["core/a.ml"] = ["not", "source", "text"]
        self.write_snapshot()
        with self.assertRaisesRegex(ValueError, "invalid source snapshot text"):
            archive_sources.verify(self.root)

    def test_truncated_snapshot_has_a_named_failure(self):
        target = self.root / archive_sources.SNAPSHOT
        target.write_bytes(target.read_bytes()[:-6])
        with self.assertRaisesRegex(ValueError, "invalid source snapshot gzip"):
            archive_sources.verify(self.root)


class Guards(unittest.TestCase):
    def test_checked_snapshot_matches_both_unchanged_archives(self):
        verified = archive_sources.verify(ROOT)
        self.assertEqual(len(verified["campaign"]), 65)
        self.assertEqual(len(verified["repros"]), 68)

    def test_snapshot_bytes_are_deterministic_and_reproducible_from_git(self):
        raw = (ROOT / archive_sources.SNAPSHOT).read_bytes()
        self.assertEqual(raw[3], 0)
        self.assertEqual(raw[4:8], b"\x00\x00\x00\x00")
        payload = gzip.decompress(raw).decode("utf-8")
        snapshot = json.loads(payload)
        self.assertEqual(payload, json.dumps(snapshot, sort_keys=True,
                                             separators=(",", ":"),
                                             ensure_ascii=True) + "\n")
        self.assertEqual(archive_sources.snapshot_bytes(ROOT, snapshot["revision"]), raw)

    def test_live_campaign_loading_is_still_the_default(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            source = root / "core/a.ml"
            source.parent.mkdir()
            source.write_text("changed", encoding="utf-8")
            # The real inventory decides the manifest, so the equality that
            # guards the digest loop runs on these bytes and is not mocked.
            names = m34_verdict.source_inventory(root)
            self.assertIn("core/a.ml", names)
            for name in names - {"core/a.ml"}:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("original", encoding="utf-8")
            self.assertEqual(m34_verdict.source_inventory(root), names)
            meta = {"format": 1, "oracle_revision": "a" * 40,
                    "sources": {name: digest("original") for name in sorted(names)}}
            with patch.object(archive_sources, "read_json", return_value=meta):
                with self.assertRaisesRegex(ValueError, "campaign source changed: core/a.ml"):
                    m34_verdict.load_evidence(root, root / "out")
            short = dict(meta, sources={name: value
                                        for name, value in meta["sources"].items()
                                        if name != "archive_sources.py"})
            with patch.object(archive_sources, "read_json", return_value=short):
                with self.assertRaisesRegex(ValueError, "incomplete source inventory"):
                    m34_verdict.load_evidence(root, root / "out")

    def test_the_live_inventory_holds_two_producers_the_manifest_lacks(self):
        manifest = set(archive_sources.read_json(
            ROOT / "research/campaign-1/provenance.json")["sources"])
        inventory = m34_verdict.source_inventory(ROOT)
        # Measured on 2026-09-08: this slice adds two producers that the
        # archived campaign manifest predates, so m35_verdict.py run and
        # publish need renewed evidence. VALIDATION.md records the limit.
        self.assertEqual(sorted(inventory - manifest),
                         ["archive_sources.py", "driver-js/lib/signals.mjs"])
        self.assertEqual(manifest - inventory, set())

    def test_the_live_refusal_names_the_producers_the_campaign_lacks(self):
        # The real tree, read only: the output directory is a tempdir and
        # load_evidence raises before it writes anything. KNOWN.md records
        # the limit under L-campaign-1-historical.
        with tempfile.TemporaryDirectory() as scratch:
            with self.assertRaises(ValueError) as caught:
                m34_verdict.load_evidence(ROOT, Path(scratch), historical=False)
            self.assertEqual(os.listdir(scratch), [])
        message = str(caught.exception)
        self.assertTrue(message.startswith("incomplete source inventory: "), message)
        self.assertIn("live producers not in the campaign manifest: "
                      "archive_sources.py, driver-js/lib/signals.mjs", message)
        self.assertNotIn("that are not live producers", message)

    def test_the_inventory_gap_names_both_sides_in_sorted_order(self):
        self.assertEqual(
            m34_verdict.inventory_gap({"kept", "gone.ml"}, {"kept", "new.mjs"}),
            "live producers not in the campaign manifest: new.mjs; "
            "campaign manifest paths that are not live producers: gone.ml")
        self.assertEqual(m34_verdict.inventory_gap({"kept"}, {"kept"}), "")

    def test_historical_campaign_refuses_a_manifest_changed_mid_run(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            meta = {"format": 1, "oracle_revision": "a" * 40,
                    "sources": {"core/a.ml": digest("original")}}
            verified = {"campaign": {"core/a.ml": digest("changed")}}
            with patch.object(archive_sources, "read_json", return_value=meta), \
                 patch.object(archive_sources, "verify", return_value=verified):
                with self.assertRaisesRegex(
                        ValueError, "campaign source manifest changed during verification"):
                    m34_verdict.load_evidence(root, root / "out", historical=True)

    def test_historical_repros_refuse_a_manifest_changed_mid_run(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            meta = {"format": 1, "indices": [4], "oracle_sha": "a" * 40,
                    "campaign_sha256": "b" * 64,
                    "sources": {"driver-js/worker.mjs": digest("original")}}
            verified = {"repros": {"driver-js/worker.mjs": digest("changed")}}
            with patch.object(m35_verdict, "digest", return_value="b" * 64), \
                 patch.object(archive_sources, "verify", return_value=verified):
                with self.assertRaisesRegex(
                        ValueError, "repro source manifest changed during verification"):
                    m35_verdict.check_mapping(root, [4], meta, historical=True)

    def test_repro_production_requests_live_campaign_verification(self):
        for action in [m35_verdict.run, m35_verdict.publish]:
            with self.subTest(action=action.__name__), \
                 patch.object(m34_verdict, "load_evidence", side_effect=ValueError("stop")) as load:
                with self.assertRaisesRegex(ValueError, "stop"):
                    action(ROOT)
                self.assertEqual(load.call_args.kwargs, {"historical": False})

    def test_publisher_refuses_a_changed_executable(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            receipt = root / "_emit/m35/completed.json"
            receipt.parent.mkdir(parents=True)
            receipt.write_text(json.dumps({"sources": {"producer": "same"},
                                           "executable_sha256": "old"}), encoding="utf-8")
            with patch.object(m35_verdict, "expected", return_value=[4]), \
                 patch.object(m35_verdict, "execution_sources", return_value={"producer": "same"}), \
                 patch.object(m35_verdict, "digest", return_value="changed"):
                with self.assertRaisesRegex(ValueError, "live producer executable changed"):
                    m35_verdict.publish(root)


if __name__ == "__main__":
    unittest.main()
