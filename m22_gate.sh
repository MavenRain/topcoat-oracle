#!/bin/zsh
# M22 gate (DESIGN.md M22).  Runs standalone or from gates.sh.
#
# Four steps:
#   1. A strict smoke run over the default scope.  It must emit a
#      report with the header line and the requested count, drop
#      nothing, reach every required body name and init shape, and
#      reach no excluded name.
#   2. A strict run over the m18 scope, whose constructor block must
#      be BYTE-IDENTICAL to the block test/test_gen.exe prints.  The
#      CLI counts KEPT samples and test_gen counts all 10000, so this
#      step is also the drop check: one drop and the blocks differ.
#   3. The two blocks must not be empty.  An extraction that silently
#      matches nothing would make step 2 pass on two empty files, so
#      the guard runs before the compare.
#   4. The json path at the same flags.  Without it a regression in
#      json_report reaches the CLI unchecked.
set -e
ROOT="${0:A:h}"
eval "$(opam env --switch=karamel-710 --set-switch)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

dune build --root "$ROOT" @all
COV="$ROOT/_build/default/bin/coverage.exe"

# Step 1: the strict smoke run.
"$COV" --samples 10000 --seed 0x4d3138 --scope default --strict \
  > "$WORK/default.txt" \
  || { echo "M22 GATE RED: the strict default run failed";  exit 1;  }
rg -q '^coverage report$' "$WORK/default.txt" \
  || { echo "M22 GATE RED: the report header line is missing";  exit 1;  }
rg -q '^samples_requested 10000$' "$WORK/default.txt" \
  || { echo "M22 GATE RED: samples_requested is missing";  exit 1;  }
rg -q '^samples_dropped 0$' "$WORK/default.txt" \
  || { echo "M22 GATE RED: the default run dropped a sample";  exit 1;  }
rg -q '^unreached_required none$' "$WORK/default.txt" \
  || { echo "M22 GATE RED: a required body name is unreached";  exit 1;  }
rg -q '^unreached_required_inits none$' "$WORK/default.txt" \
  || { echo "M22 GATE RED: a required init shape is unreached";  exit 1;  }

# Step 2: the m18 scope, then the same block from test_gen.
"$COV" --samples 10000 --seed 0x4d3138 --scope m18 --strict \
  > "$WORK/m18.txt" \
  || { echo "M22 GATE RED: the strict m18 run failed";  exit 1;  }
dune exec --root "$ROOT" test/test_gen.exe > "$WORK/testgen.txt" 2>&1 \
  || { echo "M22 GATE RED: test_gen failed";  exit 1;  }

# The counter lines only.  The two headers differ by construction:
# test_gen writes "m18 counter report (..)" and the CLI writes
# "constructor tally (..)" with the scope and the mode.
awk '{ if ($0 ~ /^constructor tally /) { f = 1; next }
       if (f) { if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]* [0-9]+$/) print; else exit } }' \
  "$WORK/m18.txt" > "$WORK/cli-block.txt"
awk '{ if ($0 ~ /^m18 counter report /) { f = 1; next }
       if (f) { if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]* [0-9]+$/) print; else exit } }' \
  "$WORK/testgen.txt" > "$WORK/gen-block.txt"

# Step 3: the empty-extraction guard, before the compare.
[ -s "$WORK/cli-block.txt" ] \
  || { echo "M22 GATE RED: the CLI m18 block is empty";  exit 1;  }
[ -s "$WORK/gen-block.txt" ] \
  || { echo "M22 GATE RED: the test_gen m18 block is empty";  exit 1;  }

cmp -s "$WORK/cli-block.txt" "$WORK/gen-block.txt" \
  || { echo "M22 GATE RED: the m18 constructor blocks differ";  exit 1;  }

# Step 4: the json path, at the flags of step 1.
"$COV" --samples 10000 --seed 0x4d3138 --scope default --json \
  > "$WORK/default.json" \
  || { echo "M22 GATE RED: the json run failed";  exit 1;  }
rg -q '"samples_kept":10000' "$WORK/default.json" \
  || { echo "M22 GATE RED: the json samples_kept is missing";  exit 1;  }

echo "M22 GATE GREEN"
