#!/usr/bin/env bash
# Runs the tests of tests/loop_stats.py. Run from anywhere: bash tests/loop-stats.test.sh
# They need Python 3.8 or newer. Python is used by repository tooling only, never by the
# plugin, so a system without it reports a skip instead of a failure.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The first of these names that really is a new enough Python. On Windows the name
# python3 can be a stand-in that only prints where to get Python.
py=""
for candidate in python3 python; do
  if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
    py="$candidate"
    break
  fi
done

if [ -z "$py" ]; then
  echo "skip - the statistics script: no Python 3.8 or newer on this system"
  echo "all passed, 1 skipped"
  exit 0
fi

# -B: write no cache folder into the repository. -I: load nothing from the user's own
# Python settings.
"$py" -B -I "$here/test_loop_stats.py"
