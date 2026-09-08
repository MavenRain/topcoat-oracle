# Archived v1 producer sources

`sources.json.gz` retains the exact UTF-8 source bytes named by the unchanged
Campaign 1 and repro manifests. Its 68 entries were read from Git commit
`9d8780b0947a9483d7f2bc28b11dd7d0fdabddee`, which the snapshot records as its
`revision`, and checked against every recorded SHA-256 digest before capture.
The producer revision in `research/campaign-1/provenance.json` alone does not
identify all these bytes, because some source additions were staged when the
original evidence was earned.

The gzip payload is a JSON object with `format: 1`, the capture `revision` and
a `sources` object that maps repository paths to their source text. Keys are
sorted, JSON uses compact separators and ASCII escaping, and the payload ends
with one newline. The gzip header has an empty filename and timestamp zero.
`python3 -P archive_sources.py ROOT REVISION` writes exactly these bytes again
from Git history, so the snapshot is reproducible from its recorded revision.

`archive_sources.verify` requires the exact union of both manifest inventories
and a `revision` of 40 hex digits, rejects duplicate JSON keys and unsafe paths,
and checks every source digest.
Verification reads the snapshot as data and needs no Git history. It neither
extracts nor executes the retained sources.

Historical source verification is followed by the existing live report and
semantic replay checks. A change to generation, minimization or reference
semantics can still fail those checks. Live campaign and repro production keep
their current-source and executable guards.
