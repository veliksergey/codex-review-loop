#!/usr/bin/env bash
# Prints one hash of the request and the acceptance criteria in the task file of the
# current repository, so that a change to either during a review loop can be seen.
# Blank lines, spaces at line ends, and line endings do not change the hash.
# Prints "none" when there is no task file. Prints nothing and exits non-zero when the
# file lacks the request heading, or an acceptance criteria heading below it.
set -uo pipefail

fail() { echo "task-hash: $1" >&2; exit 1; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
[ -n "${HOME:-}" ] || fail "HOME is not set, so the log folder is unknown"
# The same file the review loop sends to the reviewer.
task="$HOME/.claude/codex-reviews/$(basename "$root")/task.md"
[ -f "$task" ] || { echo "none"; exit 0; }

# Only the five headings of the task template are structure; any other line is text of
# the section it stands in. Where a heading appears twice, the choice errs toward hashing
# more. A line inside a fenced block or an HTML comment is never a heading.
text="$(LC_ALL=C awk '
  { sub(/[ \t\r]+$/, "") }
  {
    line[NR] = $0
    mark = $0
    sub(/^ ? ? ?/, "", mark)
    # run: the three or more ` or ~ that the line starts with, after at most three spaces.
    run = match(mark, /^(```+|~~~+)/) ? substr(mark, 1, RLENGTH) : ""
    rest = substr(mark, length(run) + 1)
    if (comment) {
      # An HTML comment ends with the line that holds its closing mark.
      if (index(mark, "-->")) comment = 0
    } else if (fence != "") {
      # A fenced block closes on a line that holds only a run of its mark, at least as long.
      if (rest == "" && substr(run, 1, 1) == substr(fence, 1, 1) && length(run) >= length(fence)) fence = ""
    } else if (run != "" && !(substr(run, 1, 1) == "`" && index(rest, "`"))) {
      # It opens on such a run. After backticks the line may hold no other backtick.
      fence = run
    } else if (substr(mark, 1, 4) == "<!--") comment = !index(mark, "-->")
    else if (/^## Request/) head[NR] = "request"
    else if (/^## Acceptance criteria/) head[NR] = "criteria"
    else if (/^## Out of scope/) head[NR] = "scope"
    else if (/^## Decisions during implementation/) head[NR] = "decisions"
    else if (/^## Handoff/) head[NR] = "handoff"
  }
  END {
    # The first request heading, the last criteria heading, and the headings below that.
    for (i = 1; i <= NR; i++) {
      if (!start) { if (head[i] == "request") start = i }
      else if (head[i] == "criteria") { criteria = i; split("", below) }
      else if (criteria && head[i] != "" && head[i] != "request") below[head[i]] = i
    }
    if (!criteria) exit 3
    # The criteria end at the last out-of-scope heading; without one, at the last decisions
    # heading; without one, at the last handoff heading; without one, with the file.
    stop = NR + 1
    if ("scope" in below) stop = below["scope"]
    else if ("decisions" in below) stop = below["decisions"]
    else if ("handoff" in below) stop = below["handoff"]
    for (i = start; i <= NR; i++) {
      # Below that point a request heading counts again, up to the next of those three.
      if (i >= stop && head[i] != "") late = (head[i] == "request")
      if ((i < stop || late) && length(line[i])) print line[i]
    }
  }' "$task")" ||
  fail "cannot find a request heading with an acceptance criteria heading below it in $task (a fenced block or an HTML comment that never closes hides the headings below it)"

printf '%s\n' "$text" | git hash-object --stdin || fail "cannot hash the task file"
