#!/bin/zsh
# M20 gate verdict. Args: <log> <span-file> <cargo-exit>.
# PASS iff: cargo exit is NONZERO, at least one error line exists,
# every src/lib.rs:L:C: error line has L inside the case_neg span
# (read from the sidecar), and at least one such line sits INSIDE the
# span. An error outside the span is a printer or scope bug: print
# the offending lines and go red. Zero in-span errors means the batch
# crate never reached rustc (a dep-build failure alone must not pass).
# An error line with any other path prefix (a span rustc attributes to
# the macro def-site, or a dep build) is never trusted: red.
set -e
LOG="$1"
SPAN="$2"
CARGO_EXIT="$3"
if [ ! -s "$SPAN" ]; then
  echo "M20 GATE RED: case_neg span sidecar missing or empty: $SPAN"
  exit 1
fi
read -r LO HI < "$SPAN"
SPANOK=$(printf '%s %s\n' "$LO" "$HI" |
  awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $1 <= $2 { print "ok" }')
if [ -z "$SPANOK" ]; then
  echo "M20 GATE RED: malformed case_neg span sidecar $SPAN (want two line numbers, got '$LO $HI')"
  exit 1
fi
if [ "$CARGO_EXIT" -eq 0 ]; then
  echo "M20 GATE RED: cargo exit 0, zero errors (case_neg reject missing)"
  exit 1
fi
ERRS=$(rg -c 'error' "$LOG" 2>/dev/null || true)
if [ -z "$ERRS" ] || [ "$ERRS" -eq 0 ]; then
  echo "M20 GATE RED: nonzero cargo exit but no error lines in $LOG"
  exit 1
fi
UNATTR=$(awk -F: '/error/ &&
  $1 != "src/lib.rs" &&
  $0 !~ /^error: aborting due to/ &&
  $0 !~ /^error: could not compile/ { print }' "$LOG")
if [ -n "$UNATTR" ]; then
  echo "M20 GATE RED: error lines not attributed to src/lib.rs:"
  echo "$UNATTR"
  exit 1
fi
BAD=$(awk -v lo="$LO" -v hi="$HI" -F: \
  '$1 == "src/lib.rs" && $4 ~ /^ error/ { if ($2 + 0 < lo || $2 + 0 > hi) print }' \
  "$LOG")
if [ -n "$BAD" ]; then
  echo "M20 GATE RED: rustc errors outside case_neg span [$LO,$HI]:"
  echo "$BAD"
  exit 1
fi
NEG=$(awk -v lo="$LO" -v hi="$HI" -F: \
  '$1 == "src/lib.rs" && $4 ~ /^ error/ { if ($2 + 0 >= lo && $2 + 0 <= hi) print }' \
  "$LOG")
if [ -z "$NEG" ]; then
  echo "M20 GATE RED: no case_neg reject inside span [$LO,$HI]; batch never reached rustc"
  exit 1
fi
echo "M20 GATE GREEN: $ERRS error line(s), all src/lib.rs errors inside case_neg span [$LO,$HI]"
