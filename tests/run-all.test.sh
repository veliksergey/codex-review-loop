#!/usr/bin/env bash
# Regression test for tests/run-all.sh. Run from anywhere: bash tests/run-all.test.sh
# RUN_ALL=<script> runs the same cases against another implementation.
# The test files it runs are made in a temporary folder; it never runs the real ones.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ra="${RUN_ALL:-$here/run-all.sh}"
fails=0
skips=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
skip() { echo "skip - $1"; skips=$((skips + 1)); }

tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT
# On GitHub this names the summary of the real run, which the made-up runs must not touch.
unset GITHUB_STEP_SUMMARY

# folder <name>: a new, empty folder of test files; its path is in $dir.
folder() { dir="$tmp/$1"; mkdir -p "$dir" || abort "mkdir $dir"; }
# file <name> <exit code> <line...>: a test file that prints the lines and exits.
file() {
  local name="$1" code="$2"; shift 2
  { printf '#!/usr/bin/env bash\n' && printf 'printf "%%s\\n" "%s"\n' "$@" && printf 'exit %s\n' "$code"; } > "$dir/$name" ||
    abort "write $dir/$name"
}
# run [folder]: runs the script; output in $out, messages in $tmp/err, exit code in $rc.
run() { out="$(bash "$ra" "${1:-$dir}" 2>"$tmp/err")"; rc=$?; }
# has <text>: the output holds this line, whole.
has() { printf '%s\n' "$out" | grep -q -x -F -- "$1"; }
last() { printf '%s\n' "$out" | sed -n '$p'; }
# row <width> <file> <passed> <failed> <skipped>: a line of the table as it must look.
row() { printf "%-${1}s  %6s  %6s  %7s" "$2" "$3" "$4" "$5"; }
# shown: the output, set in so that none of its lines reads as a result of this file.
shown() { printf '\n'; printf '%s\n' "$out" | sed 's/^/    | /'; }

# --- The table, the lists, and the result ------------------------------------------------
folder mixed
file a.test.sh 0 "ok   - first" "ok   - second" "all passed"
file b.test.sh 0 "ok   - third" "skip - fourth: this system cannot" "all passed, 1 skipped"
run
if [ $rc -eq 0 ] && [ "$(last)" = "all passed, 1 skipped" ]; then pass "passes and a skip: exits 0, and the last line counts the skip"
else fail "passes and a skip: exit $rc$(shown)"; fi
if has "file       passed  failed  skipped" && has "a.test.sh       2       0        0" &&
  has "$(row 9 b.test.sh 1 0 1)" && has "$(row 9 total 3 0 1)"; then
  pass "the table has a row for each file and a row of totals"
else fail "the table$(shown)"; fi
if has "Skipped:" && has "  b.test.sh: fourth: this system cannot" && ! has "Failed:"; then
  pass "a skipped case is named with its file, and no list of failures is printed"
else fail "the list of skipped cases$(shown)"; fi
if has "== a.test.sh" && has "ok   - first" && has "== b.test.sh" && has "skip - fourth: this system cannot"; then
  pass "the output of each file is shown under its name"
else fail "the output of each file$(shown)"; fi

folder clean
file a.test.sh 0 "ok   - first" "all passed"
run
if [ $rc -eq 0 ] && [ "$(last)" = "all passed" ] && ! has "Skipped:" && ! has "Failed:"; then
  pass "passes only: exits 0, the last line is all passed, and no list is printed"
else fail "passes only: exit $rc$(shown)"; fi

folder failing
file a.test.sh 0 "ok   - first" "all passed"
file b.test.sh 1 "ok   - second" "FAIL - third: wanted 1" "FAIL - fourth" "skip - fifth" "2 failed"
run
if [ $rc -eq 1 ] && [ "$(last)" = "2 failed" ] && has "$(row 9 b.test.sh 1 2 1)" && has "$(row 9 total 2 2 1)"; then
  pass "failed cases: exits 1, and the last line and the table count them"
else fail "failed cases: exit $rc$(shown)"; fi
if has "Failed:" && has "  b.test.sh: third: wanted 1" && has "  b.test.sh: fourth" && has "  b.test.sh: fifth"; then
  pass "failed and skipped cases are both named"
else fail "the lists after a failure$(shown)"; fi

# --- A file that does not report as it should ----------------------------------------------
folder stopped
file a.test.sh 3 "ok   - first" "setup failed: no folder"
run
if [ $rc -eq 1 ] && [ "$(last)" = "1 failed" ] && has "$(row 9 a.test.sh 1 1 0)" &&
  has "  a.test.sh: ended with exit code 3 without naming a failed case"; then
  pass "a file that stops without naming a failed case counts as one failure"
else fail "a file that stops: exit $rc$(shown)"; fi

folder silent
file a.test.sh 0 "nothing to see"
file b.test.sh 0 "ok   - first"
run
if [ $rc -eq 1 ] && [ "$(last)" = "1 failed" ] && has "  a.test.sh: reported no case"; then
  pass "a file that exits 0 without reporting a case counts as one failure"
else fail "a file that reports no case: exit $rc$(shown)"; fi

folder onlyskip
file a.test.sh 0 "skip - everything: no tool for it" "all passed, 1 skipped"
run
if [ $rc -eq 0 ] && [ "$(last)" = "all passed, 1 skipped" ] && has "$(row 9 a.test.sh 0 0 1)"; then
  pass "a file that reports only a skip is not a failure"
else fail "a file that reports only a skip: exit $rc$(shown)"; fi

folder lying
file a.test.sh 0 "ok   - first" "FAIL - second" "all passed"
run
if [ $rc -eq 1 ] && [ "$(last)" = "1 failed" ] && has "$(row 9 a.test.sh 1 1 0)"; then
  pass "a failed case in a file that exits 0 still fails the run"
else fail "a failed case with exit 0: exit $rc$(shown)"; fi

folder both
file a.test.sh 1 "FAIL - first" "1 failed"
run
if [ $rc -eq 1 ] && [ "$(last)" = "1 failed" ] && has "$(row 9 a.test.sh 0 1 0)" &&
  [ "$(printf '%s\n' "$out" | grep -c '^  a.test.sh: ')" -eq 1 ]; then
  pass "a file that names its failure and exits 1 counts once, and is listed once"
else fail "a named failure with exit 1: exit $rc$(shown)"; fi

folder quoted
file a.test.sh 0 "ok   - real" "    | ok   - set in" "see FAIL - in a sentence" "a skip - in a sentence"
run
if [ $rc -eq 0 ] && [ "$(last)" = "all passed" ] && has "$(row 9 a.test.sh 1 0 0)"; then
  pass "a line counts only when it starts with the mark of a result"
else fail "marks in the middle of a line: exit $rc$(shown)"; fi

# --- Which files run, and how ---------------------------------------------------------------
folder chosen
file a.test.sh 0 "ok   - first"
file helper.sh 1 "FAIL - a helper is not a test"
file old.test.sh.bak 1 "FAIL - a copy is not a test"
mkdir -p "$dir/folder.test.sh" || abort "mkdir"
run
if [ $rc -eq 0 ] && [ "$(last)" = "all passed" ] && has "$(row 9 total 1 0 0)"; then
  pass "only files whose names end in .test.sh are run"
else fail "which files run: exit $rc$(shown)"; fi

folder reading
printf '#!/usr/bin/env bash\nif read -r line; then echo "FAIL - got input: $line"; exit 1; fi\necho "ok   - no input"\n' > "$dir/a.test.sh" ||
  abort "write"
out="$(echo typed | bash "$ra" "$dir" 2>"$tmp/err")"; rc=$?
if [ $rc -eq 0 ] && [ "$(last)" = "all passed" ]; then pass "a test file gets no input from the caller"
else fail "input of a test file: exit $rc$(shown)"; fi

folder errors
printf '#!/usr/bin/env bash\necho "a trace on the error stream" >&2\necho "ok   - first"\n' > "$dir/a.test.sh" || abort "write"
run
if [ $rc -eq 0 ] && has "a trace on the error stream"; then pass "what a test file writes to the error stream is shown"
else fail "the error stream of a test file: exit $rc$(shown)"; fi

folder returns
printf '#!/usr/bin/env bash\nprintf "ok   - first\\r\\nskip - second: cannot\\r\\nFAIL - third\\r\\n"\nexit 1\n' > "$dir/a.test.sh" || abort "write"
run
if [ $rc -eq 1 ] && has "$(row 9 a.test.sh 1 1 1)" && has "  a.test.sh: second: cannot" && has "  a.test.sh: third"; then
  pass "lines that end in a carriage return are counted, and named without it"
else fail "carriage returns: exit $rc$(shown)"; fi
# Some shells and some awk builds drop the carriage return themselves; there the case
# above cannot tell whether the script handles it.
probe="$(printf 'a\r\n')"
if [ "${#probe}" -ne 2 ] || [ "$(printf 'ab\r\n' | LC_ALL=C awk '{ print length($0) }')" != 3 ]; then
  skip "the script's own carriage-return handling: this shell or this awk drops carriage returns itself"
fi

folder tabs
printf '#!/usr/bin/env bash\nprintf "skip - one\\ttwo\\tthree: cannot\\nFAIL - four\\tfive\\n"\nexit 1\n' > "$dir/a.test.sh" || abort "write"
run
if [ $rc -eq 1 ] && has "  a.test.sh: one	two	three: cannot" && has "  a.test.sh: four	five"; then
  pass "a case name with tabs in it is named whole"
else fail "a case name with tabs: exit $rc$(shown)"; fi

folder widths
long="a-much-longer-name-than-the-others.test.sh"
file "$long" 0 "ok   - first"
file b.test.sh 0 "ok   - second"
run
if has "$(row ${#long} file passed failed skipped)" && has "$(row ${#long} "$long" 1 0 0)" &&
  has "$(row ${#long} b.test.sh 1 0 0)" && has "$(row ${#long} total 2 0 0)"; then
  pass "the first column is as wide as the longest file name"
else fail "the width of the first column$(shown)"; fi

folder "with space"
file a.test.sh 0 "ok   - first"
run
if [ $rc -eq 0 ] && [ "$(last)" = "all passed" ]; then pass "a folder with a space in its name"
else fail "a folder with a space: exit $rc$(shown)"; fi

# Without a folder, the script runs the test files beside itself.
folder beside
cp "$ra" "$dir/run-all.sh" || abort "copy the script"
file a.test.sh 0 "ok   - beside"
out="$(cd "$tmp" && bash "$dir/run-all.sh" 2>"$tmp/err")"; rc=$?
if [ $rc -eq 0 ] && has "== a.test.sh" && has "$(row 9 total 1 0 0)"; then
  pass "without a folder: the files beside the script are run"
else fail "without a folder: exit $rc$(shown)"; fi

# --- Nothing to run -------------------------------------------------------------------------
folder empty
run
if [ $rc -eq 2 ] && [ -z "$out" ] && grep -q "no test file in" "$tmp/err"; then pass "a folder without test files: exits 2 and says why"
else fail "a folder without test files: exit $rc$(shown)"; fi
run "$tmp/missing"
if [ $rc -eq 2 ] && [ -z "$out" ] && grep -q "no such folder" "$tmp/err"; then pass "a folder that does not exist: exits 2 and says why"
else fail "a folder that does not exist: exit $rc$(shown)"; fi

# --- The summary on GitHub ------------------------------------------------------------------
printf 'earlier step\n' > "$tmp/summary.md" || abort "write"
out="$(GITHUB_STEP_SUMMARY="$tmp/summary.md" bash "$ra" "$tmp/failing" 2>"$tmp/err")"; rc=$?
want='earlier step
### Tests

| File | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `a.test.sh` | 1 | 0 | 0 |
| `b.test.sh` | 1 | 2 | 1 |
| Total | 2 | 2 | 1 |

Failed:

```text
b.test.sh: third: wanted 1
b.test.sh: fourth
```

Skipped:

```text
b.test.sh: fifth
```

2 failed'
if [ $rc -eq 1 ] && [ "$(cat "$tmp/summary.md")" = "$want" ]; then
  pass "the summary file gets the table, both lists, and the result, below what it held"
else out="$(cat "$tmp/summary.md")"; fail "the summary file: exit $rc$(shown)"; fi
out="$(GITHUB_STEP_SUMMARY="$tmp/summary-again.md" bash "$ra" "$tmp/failing" 2>"$tmp/err")"; rc=$?
if [ $rc -eq 1 ] && [ "$(last)" = "2 failed" ] && has "$(row 9 b.test.sh 1 2 1)" && has "  b.test.sh: fifth"; then
  pass "with a summary file the table and the lists are still printed"
else fail "the printed table beside a summary file: exit $rc$(shown)"; fi

out="$(GITHUB_STEP_SUMMARY="$tmp/summary-clean.md" bash "$ra" "$tmp/clean" 2>"$tmp/err")"; rc=$?
want='### Tests

| File | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `a.test.sh` | 1 | 0 | 0 |
| Total | 1 | 0 | 0 |

all passed'
if [ $rc -eq 0 ] && [ "$(cat "$tmp/summary-clean.md")" = "$want" ]; then pass "a summary of passes only has no list"
else out="$(cat "$tmp/summary-clean.md")"; fail "a summary of passes only: exit $rc$(shown)"; fi

out="$(GITHUB_STEP_SUMMARY="$tmp/no such folder/summary.md" bash "$ra" "$tmp/failing" 2>"$tmp/err")"; rc=$?
if [ $rc -eq 1 ] && [ "$(last)" = "2 failed" ] && grep -q "cannot add the table" "$tmp/err"; then
  pass "a summary file that cannot be written: said so, and the result stands"
else fail "a summary file that cannot be written: exit $rc$(shown)"; fi
out="$(GITHUB_STEP_SUMMARY="$tmp/no such folder/summary.md" bash "$ra" "$tmp/clean" 2>"$tmp/err")"; rc=$?
if [ $rc -eq 0 ] && [ "$(last)" = "all passed" ]; then pass "a summary file that cannot be written does not fail a run that passed"
else fail "a summary file that cannot be written, passing run: exit $rc$(shown)"; fi

out="$(GITHUB_STEP_SUMMARY="" bash "$ra" "$tmp/clean" 2>"$tmp/err")"; rc=$?
if [ $rc -eq 0 ] && [ "$(last)" = "all passed" ] && [ ! -s "$tmp/err" ]; then pass "an empty name for the summary file: none is written"
else fail "an empty name for the summary file: exit $rc, message: $(cat "$tmp/err")"; fi

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
elif [ $skips -ne 0 ]; then
  echo "all passed, $skips skipped"
else
  echo "all passed"
fi
