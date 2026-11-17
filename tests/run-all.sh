#!/usr/bin/env bash
# Runs every *.test.sh file of a folder and prints one table: the cases that passed,
# failed, and were skipped in each file. Usage: run-all.sh [folder]. The default is the
# folder this file is in. A test file reports a case as a line that starts with
# "ok   - ", "FAIL - ", or "skip - ".
# Exit 0: nothing failed. Exit 1: something failed. Exit 2: there was nothing to run.
set -uo pipefail

stop() { echo "run-all: $1" >&2; exit 2; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || stop "cannot find the folder of this file"
dir="${1:-$here}"
[ -d "$dir" ] || stop "no such folder: $dir"

tmp="$(mktemp -d)" || stop "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || stop "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT
: > "$tmp/all" || stop "cannot write to the temporary folder"

ran=0
for file in "$dir"/*.test.sh; do
  [ -f "$file" ] || continue
  ran=$((ran + 1))
  name="${file##*/}"
  echo "== $name"
  # A test gets no input, so one that reads cannot wait for a person.
  bash "$file" < /dev/null > "$tmp/out" 2>&1
  code=$?
  cat "$tmp/out"
  echo
  # One "row" line for the table, and one line for each case that failed or was skipped.
  RUN_ALL_NAME="$name" RUN_ALL_CODE="$code" LC_ALL=C awk '
    BEGIN { name = ENVIRON["RUN_ALL_NAME"]; code = ENVIRON["RUN_ALL_CODE"] + 0 }
    { sub(/\r$/, "") }
    /^ok   - / { passed++ }
    /^FAIL - / { failed++; print "failed\t" name ": " substr($0, 8) }
    /^skip - / { skipped++; print "skipped\t" name ": " substr($0, 8) }
    END {
      # A file that stopped without naming a failed case, or that reported no case.
      if (code != 0 && !failed) {
        failed = 1
        print "failed\t" name ": ended with exit code " code " without naming a failed case"
      }
      if (passed + failed + skipped == 0) {
        failed = 1
        print "failed\t" name ": reported no case"
      }
      printf "row\t%s\t%d\t%d\t%d\n", name, passed, failed, skipped
    }' "$tmp/out" >> "$tmp/all" || stop "cannot count the cases of $name"
done
[ "$ran" -gt 0 ] || stop "no test file in $dir"

# report <text|markdown>: the table, the failed cases, the skipped cases, and the result.
report() {
  RUN_ALL_STYLE="$1" LC_ALL=C awk -F '\t' '
    function listed(title, list, count,    i) {
      if (!count) return
      if (markdown) printf "\n%s:\n\n```text\n", title; else printf "\n%s:\n", title
      for (i = 1; i <= count; i++) print (markdown ? "" : "  ") list[i]
      if (markdown) print "```"
    }
    BEGIN { markdown = (ENVIRON["RUN_ALL_STYLE"] == "markdown") }
    $1 == "row" {
      n++; name[n] = $2; passed[n] = $3; failed[n] = $4; skipped[n] = $5
      passed_all += $3; failed_all += $4; skipped_all += $5
      if (length($2) > width) width = length($2)
    }
    # The name of a case is everything after the first tab, tabs of its own included.
    $1 == "failed" { fails[++fail_count] = substr($0, 8) }
    $1 == "skipped" { skips[++skip_count] = substr($0, 9) }
    END {
      if (markdown) {
        print "### Tests\n\n| File | Passed | Failed | Skipped |\n|---|---:|---:|---:|"
        for (i = 1; i <= n; i++) printf "| `%s` | %d | %d | %d |\n", name[i], passed[i], failed[i], skipped[i]
        printf "| Total | %d | %d | %d |\n", passed_all, failed_all, skipped_all
      } else {
        line = "%-" width "s  %6s  %6s  %7s\n"
        printf line, "file", "passed", "failed", "skipped"
        for (i = 1; i <= n; i++) printf line, name[i], passed[i], failed[i], skipped[i]
        printf line, "total", passed_all, failed_all, skipped_all
      }
      listed("Failed", fails, fail_count)
      listed("Skipped", skips, skip_count)
      print ""
      if (failed_all) print failed_all " failed"
      else if (skipped_all) print "all passed, " skipped_all " skipped"
      else print "all passed"
    }' "$tmp/all"
}

report text || stop "cannot print the table"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  report markdown >> "$GITHUB_STEP_SUMMARY" ||
    echo "run-all: cannot add the table to $GITHUB_STEP_SUMMARY" >&2
fi

# The exit code follows the table: a failed row fails the run.
LC_ALL=C awk -F '\t' '$1 == "row" && $4 > 0 { failed = 1 } END { exit failed ? 1 : 0 }' "$tmp/all"
