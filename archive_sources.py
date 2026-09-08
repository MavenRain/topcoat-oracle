"""Verify retained producer bytes for the historical v1 campaign and repros.

Sources remain data: verification neither extracts nor executes the snapshot.
Current binaries still perform the report and semantic replay checks.
"""
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


SNAPSHOT = "research/archive-v1/sources.json.gz"
SNAPSHOT_FORMAT = 1
REVISION = re.compile(r"[0-9a-f]{40}")
MANIFESTS = {
    "campaign": "research/campaign-1/provenance.json",
    "repros": "repros/campaign-1/manifest.json",
}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result


def read_json(path):
    """Read metadata without silently accepting a repeated source or field."""
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def source_name(name):
    require(isinstance(name, str) and bool(name), "unsafe source path")
    path = PurePosixPath(name)
    require(bool(path.parts) and not path.is_absolute() and ".." not in path.parts
            and path.as_posix() == name and "\\" not in name and "\0" not in name,
            "unsafe source path: " + name)


def manifest_digests(root):
    """Read both manifests and the one digest each named source must have."""
    manifests = {}
    expected = {}
    for label, path in MANIFESTS.items():
        meta = read_json(root / path)
        require(isinstance(meta, dict) and isinstance(meta.get("sources"), dict)
                and bool(meta["sources"]), "missing source fingerprints: " + label)
        manifests[label] = meta["sources"]
        for name, digest in meta["sources"].items():
            source_name(name)
            require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest),
                    "invalid source digest: " + name)
            require(name not in expected or expected[name] == digest,
                    "conflicting archived source digest: " + name)
            expected[name] = digest
    return manifests, expected


def blob(root, revision, name):
    """Read one retained source out of Git history. The bytes stay data."""
    read = subprocess.run(["git", "-C", str(root), "cat-file", "blob",
                           revision + ":" + name], capture_output=True)
    require(read.returncode == 0, "archived source is not in " + revision + ": " + name)
    return read.stdout


def snapshot_bytes(root, revision):
    """Build the deterministic snapshot of one revision's producer sources.

    Every source is checked against its manifest digest before capture, so a
    revision that does not hold the archived bytes cannot be recorded.
    """
    require(isinstance(revision, str) and REVISION.fullmatch(revision) is not None,
            "invalid snapshot revision")
    expected = manifest_digests(root)[1]
    sources = {}
    for name, digest in expected.items():
        text = blob(root, revision, name).decode("utf-8")
        require(hashlib.sha256(text.encode("utf-8")).hexdigest() == digest,
                "archived source digest mismatch: " + name)
        sources[name] = text
    payload = json.dumps({"format": SNAPSHOT_FORMAT, "revision": revision,
                          "sources": sources},
                         sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n"
    return gzip.compress(payload.encode("utf-8"), mtime=0)


def capture(root, revision):
    """Write the retained producer bytes for one revision."""
    (root / SNAPSHOT).write_bytes(snapshot_bytes(root, revision))


def verify(root):
    """Check the exact manifest union and every retained source digest.

    Live source files and local Git history are deliberately not inputs.
    A changed generator, minimizer or reference can still fail live replay.
    """
    manifests, expected = manifest_digests(root)

    try:
        payload = gzip.decompress((root / SNAPSHOT).read_bytes())
    except (OSError, EOFError) as error:
        raise ValueError("invalid source snapshot gzip") from error
    snapshot = json.loads(payload.decode("utf-8"), object_pairs_hook=unique_object)
    require(isinstance(snapshot, dict) and set(snapshot) == {"format", "revision", "sources"}
            and type(snapshot["format"]) is int and snapshot["format"] == SNAPSHOT_FORMAT,
            "unsupported source snapshot format")
    require(isinstance(snapshot["revision"], str)
            and REVISION.fullmatch(snapshot["revision"]) is not None,
            "invalid snapshot revision")
    stored = snapshot["sources"]
    require(isinstance(stored, dict), "invalid source snapshot contents")
    for name in stored:
        source_name(name)
    require(set(stored) == set(expected), "source snapshot inventory mismatch")
    for name, digest in expected.items():
        require(isinstance(stored[name], str), "invalid source snapshot text: " + name)
        require(hashlib.sha256(stored[name].encode("utf-8")).hexdigest() == digest,
                "source snapshot digest mismatch: " + name)
    return manifests


if __name__ == "__main__":
    require(len(sys.argv) == 3, "usage: archive_sources.py ROOT REVISION")
    capture(Path(sys.argv[1]).resolve(), sys.argv[2])
