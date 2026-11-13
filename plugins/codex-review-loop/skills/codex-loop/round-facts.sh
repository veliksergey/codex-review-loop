#!/usr/bin/env bash
# Prints the facts of one Codex review log as key=value lines: the header values, how
# many shell commands started, ran, and failed to start, and the tool calls outside the
# shell. Two more lines identify the round: a hash of the prompt file beside the log,
# and the commit the repository is at. Without an argument it reads the newest round log
# of the current repository.
# Prints nothing and exits non-zero if there is no log or it has no Codex header.
set -uo pipefail

fail() { echo "round-facts: $1" >&2; exit "${2:-2}"; }

if [ $# -ge 1 ]; then
  log="$1"
else
  # The same folder the review loop writes its logs to.
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
  dir="$HOME/.claude/codex-reviews/$(basename "$root")"
  log="$(ls -t "$dir"/*-codex.log 2>/dev/null | head -n 1)"
  [ -n "$log" ] || fail "no review log in $dir"
fi
[ -f "$log" ] || fail "no such log: $log"

# LC_ALL=C: a log can hold bytes that are not valid text in the current locale.
facts="$(LC_ALL=C awk '
  function value(line) { sub(/^[^:]*: */, "", line); return line }
  { sub(/\r$/, "") }
  # The header: a version line, then key lines between two rules.
  !seen && /^OpenAI Codex v/ { seen = 1; version = $0; sub(/^OpenAI Codex v/, "", version); next }
  seen && !closed && /^--------$/ { rules++; if (rules == 2) closed = 1; next }
  seen && !closed {
    if ($0 ~ /^model: /) model = value($0)
    else if ($0 ~ /^reasoning effort: /) effort = value($0)
    else if ($0 ~ /^sandbox: /) sandbox = value($0)
    else if ($0 ~ /^approval: /) approval = value($0)
    else if ($0 ~ /^session id: /) session = value($0)
    next
  }
  !closed { next }
  # The prompt is echoed after the header; nothing in it is an event. Events are counted
  # from the line after the prompt ends, or from the header when that line is absent.
  $0 == "</grounding_rules>" && !reset { started = 0; ran = 0; nostart = 0; reset = 1; next }
  /^exec$/ { started++; next }
  /^ succeeded in [0-9.]+[a-z]+:$/ { ran++; next }
  /^ exited [0-9]+ in [0-9.]+[a-z]+:$/ { ran++; next }
  /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.]+Z +ERROR .*error=exec_command failed/ { nostart++; next }
  END {
    if (!closed) exit 3
    print "codex_cli=" version
    print "model=" model
    print "effort=" effort
    print "sandbox=" sandbox
    print "approval=" approval
    print "session_id=" session
    print "shell_started=" started + 0
    print "shell_ran=" ran + 0
    print "shell_start_failed=" nostart + 0
    print "shell_usable=" (ran > 0 ? "yes" : "no")
  }' "$log")" || fail "not a Codex review log: $log" 3

# Tool calls outside the shell, counted after the echoed prompt like the events above.
# Each tool carries the log line of every one of its calls, so that a reader can check
# each call. A failure here must not read as "no tool was called".
tools="$(LC_ALL=C awk '
  { sub(/\r$/, "") }
  $0 == "</grounding_rules>" && !reset { split("", calls); reset = 1; next }
  /^mcp: [^ ]+ started$/ { lines[$2] = (($2 in calls) ? lines[$2] "," : "") NR; calls[$2]++ }
  END { for (name in calls) print "tool=" name " calls=" calls[name] " lines=" lines[name] }' "$log" |
  LC_ALL=C sort)" || fail "could not count the tool calls in $log" 3

total=0; web=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  n="${line##* calls=}"; n="${n%% *}"
  # Only a plain number may reach the arithmetic below.
  case "$n" in '' | *[!0-9]*) fail "unexpected tool line in $log" 3 ;; esac
  total=$((total + n))
  # Web search is itself a Codex connector; its tools share this prefix.
  case "$line" in "tool=codex_apps/search_service."*) web=$((web + n)) ;; esac
done <<EOF
$tools
EOF

# What was sent, hashed byte for byte, and the commit under the reviewed tree. Either is
# unknown for a log kept on its own or read outside a repository.
prompt="${log%-codex.log}-prompt.md"
prompt_hash="unknown"
if [ -f "$prompt" ]; then
  prompt_hash="$(git hash-object --no-filters -- "$prompt" 2>/dev/null)" || prompt_hash="unknown"
fi
commit="$(git rev-parse --verify --quiet HEAD 2>/dev/null)" || commit="unknown"

printf 'log=%s\nprompt_hash=%s\ncommit=%s\n%s\n' "$(basename "$log")" "$prompt_hash" "$commit" "$facts"
printf 'tool_calls=%s\nweb_search_calls=%s\nother_tool_calls=%s\n' "$total" "$web" "$((total - web))"
[ -z "$tools" ] || printf '%s\n' "$tools"
