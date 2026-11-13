#!/usr/bin/env bash
# Regression test for plugins/codex-review-loop/skills/codex-loop/round-facts.sh.
# Run from anywhere: bash tests/round-facts.test.sh
# ROUND_FACTS=<script> runs the same cases against another implementation.
# Every log below is synthetic and is built at run time, so no line of this file has
# the shape of a log event.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rf="${ROUND_FACTS:-$here/../plugins/codex-review-loop/skills/codex-loop/round-facts.sh}"
fails=0

skips=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
skip() { echo "skip - $1"; skips=$((skips + 1)); }
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
# tool_lines <output>: the tool lines without the log line numbers at their end.
tool_lines() { printf '%s\n' "$1" | grep '^tool=' | sed 's/ lines=[0-9,]*$//'; }
# expect <name> <output> <line>...: every line must appear in the output, whole.
expect() {
  local name="$1" out="$2" missing=""; shift 2
  for want in "$@"; do has "$out" "$want" || missing="$missing [$want]"; done
  if [ -z "$missing" ]; then pass "$name"; else fail "$name: missing$missing"; fi
}

tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT
export GIT_CEILING_DIRECTORIES="$tmp"

rule="--------"
header() {
  printf 'OpenAI Codex v0.0.1\n%s\nworkdir: /work/repo\nmodel: test-model\nprovider: test\n' "$rule"
  printf 'approval: never\nsandbox: read-only\nreasoning effort: high\nreasoning summaries: none\n'
  printf 'session id: 00000000-0000-0000-0000-000000000001\n%s\n' "$rule"
}
prompt() { printf 'user\n<role>\nreview this\n</role>\n%s\n' "</grounding_rules>"; }
ran_ok() { printf '%s\n"sh" -c "git status" in /work/repo\n succeeded in 12ms:\n M a.txt\n\n' "exec"; }
ran_nonzero() { printf '%s\n"sh" -c "grep x y" in /work/repo\n exited 1 in 8ms:\n\n' "exec"; }
no_start() {
  printf '%s\n"sh" -c "git status" in /work/repo\n' "exec"
  printf '2026-01-01T00:00:00.000000Z ERROR codex_core::tools::router: error=%s\n' "exec_command failed: CreateProcess"
  printf ' exited -1 in 0ms:\nFailed to create unified exec process\n'
}
tool() { printf '%s %s started\n%s %s (completed)\n' "mcp:" "$1" "mcp:" "$1"; }
final() { printf 'codex\nNo findings.\n'; }

# A normal round: two shell commands ran, one of them with a non-zero exit, and the
# reviewer searched the web twice.
{ header; prompt; ran_ok; ran_nonzero; tool codex_apps/search_service.web_run
  tool codex_apps/search_service.web_run; final; } > "$tmp/normal.log"
out="$(bash "$rf" "$tmp/normal.log")"; rc=$?
[ $rc -eq 0 ] || fail "normal round: exit $rc"
expect "normal round: header values" "$out" "log=normal.log" "codex_cli=0.0.1" "model=test-model" \
  "effort=high" "sandbox=read-only" "approval=never" "session_id=00000000-0000-0000-0000-000000000001"
expect "normal round: a command with a non-zero exit still ran" "$out" \
  "shell_started=2" "shell_ran=2" "shell_start_failed=0" "shell_usable=yes"
expect "normal round: web searches are counted apart from other tools" "$out" \
  "tool_calls=2" "web_search_calls=2" "other_tool_calls=0"
expect "normal round: the tool is listed by name" "$(tool_lines "$out")" \
  "tool=codex_apps/search_service.web_run calls=2"
# The header is 11 lines, the prompt 5, the two commands 5 and 4: the two calls are
# lines 26 and 28.
expect "normal round: a tool called twice carries the line of each call" "$out" \
  "tool=codex_apps/search_service.web_run calls=2 lines=26,28"

# The sandboxed shell never started and the reviewer worked through another tool.
{ header; prompt; no_start; no_start; tool node_repl/js; tool node_repl/js; tool node_repl/js
  tool codex_apps/search_service.web_run; final; } > "$tmp/noshell.log"
out="$(bash "$rf" "$tmp/noshell.log")"
expect "every shell start failed: the shell is reported unusable" "$out" \
  "shell_started=2" "shell_ran=0" "shell_start_failed=2" "shell_usable=no"
expect "every shell start failed: the other tool is counted" "$out" \
  "tool_calls=4" "web_search_calls=1" "other_tool_calls=3"
expect "every shell start failed: the other tool is reported by name" "$(tool_lines "$out")" \
  "tool=node_repl/js calls=3"

# No shell command at all.
{ header; prompt; final; } > "$tmp/none.log"
out="$(bash "$rf" "$tmp/none.log")"
expect "no shell command: the shell is reported unusable" "$out" \
  "shell_started=0" "shell_ran=0" "shell_usable=no" "tool_calls=0" "other_tool_calls=0"

# Lines inside the echoed prompt that look like events are not events.
{ header; printf 'user\n%s\n succeeded in 1ms:\n%s a/b started\n%s\n' "exec" "mcp:" "</grounding_rules>"
  ran_ok; final; } > "$tmp/echo.log"
out="$(bash "$rf" "$tmp/echo.log")"
expect "event-shaped lines in the echoed prompt are not counted" "$out" \
  "shell_started=1" "shell_ran=1" "tool_calls=0"

# A hand-run review has no prompt end marker; events are then counted from the header.
{ header; printf 'user\nreview please\n'; ran_ok; tool x/y; final; } > "$tmp/bare.log"
out="$(bash "$rf" "$tmp/bare.log")"
expect "no prompt end marker: events are counted from the header" "$out" \
  "shell_started=1" "shell_ran=1" "tool_calls=1"
# The header is 11 lines, the prompt 2, the command and what it printed 5: line 19.
expect "a tool called once carries the log line of that call" "$out" "tool=x/y calls=1 lines=19"

# A command printed a line with the shape of a tool call, and the reviewer later made a
# real call to the same tool. Both lines are listed, so that each can be checked: with
# only the first, the real call would be dismissed together with the printed line.
{ header; prompt
  printf '%s\n"sh" -c "cat notes.txt" in /work/repo\n succeeded in 3ms:\n%s x/y started\n\n' "exec" "mcp:"
  ran_ok; tool x/y; final; } > "$tmp/mixed.log"
out="$(bash "$rf" "$tmp/mixed.log")"
# The header is 11 lines, the prompt 5: the printed line is line 20. The second command
# takes lines 22 to 26, so the real call is line 27.
expect "a printed look-alike and a real call of one tool: both lines are listed" "$out" \
  "tool=x/y calls=2 lines=20,27" "other_tool_calls=2"

# Windows line endings and a byte that is not valid text.
{ header; prompt; ran_ok; printf 'odd byte \377 here\n'; tool x/y; final; } | sed 's/$/\r/' > "$tmp/crlf.log"
out="$(bash "$rf" "$tmp/crlf.log")"; rc=$?
if [ $rc -eq 0 ]; then pass "CRLF log with a non-text byte: exits 0"; else fail "CRLF log: exit $rc"; fi
expect "CRLF log: same facts, no carriage return in the values" "$out" \
  "model=test-model" "sandbox=read-only" "shell_ran=1" "tool_calls=1"
# Some awk builds drop the carriage return themselves; there the case above cannot
# tell whether the script handles it.
if [ "$(printf 'ab\r\n' | LC_ALL=C awk '{ print length($0) }')" != 3 ]; then
  skip "the script's own carriage-return handling: this awk drops carriage returns itself"
fi

# Tool lines are sorted, so the output is the same on every run.
{ header; prompt; ran_ok; tool zeta/t; tool alpha/t; tool mid/t; final; } > "$tmp/sorted.log"
out="$(tool_lines "$(bash "$rf" "$tmp/sorted.log")")"
if [ "$out" = "tool=alpha/t calls=1
tool=mid/t calls=1
tool=zeta/t calls=1" ]; then pass "tool lines are sorted by name"; else fail "tool lines are not sorted: $out"; fi

# A tool count that could not be made must not read as "no tool was called". The
# stand-in for sort fails; the log holds calls to a tool that should be off.
mkdir -p "$tmp/failbin" || abort "mkdir failbin"
{ printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/failbin/sort" && chmod +x "$tmp/failbin/sort"; } || abort "failing sort"
out="$(PATH="$tmp/failbin:$PATH" bash "$rf" "$tmp/noshell.log" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "the tool count fails: exits non-zero and prints no facts"
else fail "the tool count fails: exit $rc, output: $out"; fi

# Not a Codex log: no facts at all.
printf 'just some text\n%s\nmodel: x\n' "exec" > "$tmp/other.txt"
out="$(bash "$rf" "$tmp/other.txt" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "a file without a Codex header: exits non-zero and prints nothing"
else fail "a file without a Codex header: exit $rc, output: $out"; fi

# A header that never closes is not a usable log either.
printf 'OpenAI Codex v0.0.1\n%s\nmodel: x\n' "$rule" > "$tmp/open.log"
out="$(bash "$rf" "$tmp/open.log" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "a header that never closes: exits non-zero and prints nothing"
else fail "a header that never closes: exit $rc, output: $out"; fi

out="$(bash "$rf" "$tmp/missing.log" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "a missing file: exits non-zero and prints nothing"
else fail "a missing file: exit $rc, output: $out"; fi

# Without an argument the newest round log of the current repository is read.
home="$tmp/home"; repo="$tmp/work/myrepo"; logs="$home/.claude/codex-reviews/myrepo"
mkdir -p "$repo/sub" "$logs" || abort "folders for the default-log case"
git -C "$repo" init -q . || abort "git init"
{ header; prompt; ran_ok; final; } > "$logs/20260101-000000-round1-codex.log"
{ header; prompt; ran_ok; ran_ok; ran_ok; final; } > "$logs/20260101-000000-round2-codex.log"
touch -t 202601010000 "$logs/20260101-000000-round1-codex.log" || abort "touch round 1"
touch -t 202601010005 "$logs/20260101-000000-round2-codex.log" || abort "touch round 2"
out="$(cd "$repo/sub" && HOME="$home" bash "$rf")"; rc=$?
[ $rc -eq 0 ] || fail "no argument: exit $rc"
expect "no argument: reads the newest round log of this repository" "$out" \
  "log=20260101-000000-round2-codex.log" "shell_ran=3"
# Two lines identify the round. Neither is known yet: no prompt file lies beside the
# log, and the repository has no commit.
expect "no prompt file and no commit: both are reported as unknown" "$out" \
  "prompt_hash=unknown" "commit=unknown"

# The prompt of a round lies beside its log. Its hash is that of its bytes: the first
# value below is git's hash of the six bytes "hello" and a line feed.
printf 'hello\n' > "$logs/20260101-000000-round2-prompt.md" || abort "write the prompt"
git -C "$repo" -c user.name=test -c user.email=test commit -q --allow-empty -m first || abort "commit"
out="$(cd "$repo/sub" && HOME="$home" bash "$rf")"
expect "a prompt file beside the log: its hash is reported" "$out" \
  "prompt_hash=ce013625030ba8dba906f756967f9e9ca394464a"
expect "a repository with a commit: the commit is reported" "$out" \
  "commit=$(git -C "$repo" rev-parse HEAD)"
# With Windows line endings the prompt is other bytes and must hash differently, also
# where git is set to convert line endings, which the three variables switch on.
printf 'hello\r\n' > "$logs/20260101-000000-round2-prompt.md" || abort "rewrite the prompt"
out="$(cd "$repo/sub" && HOME="$home" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf \
  GIT_CONFIG_VALUE_0=true bash "$rf")"
expect "a prompt with Windows line endings: hashed as it is, not converted" "$out" \
  "prompt_hash=ef0493b275aa2080237f676d2ef6559246f56636"
# The prompt belongs to its own round: an older round's prompt is not taken for it.
rm -f "$logs/20260101-000000-round2-prompt.md" || abort "remove the prompt"
printf 'hello\n' > "$logs/20260101-000000-round1-prompt.md" || abort "write round 1's prompt"
out="$(cd "$repo/sub" && HOME="$home" bash "$rf")"
expect "only another round has a prompt file: unknown" "$out" "prompt_hash=unknown"

rm -f "$logs"/*-codex.log || abort "remove logs"
out="$(cd "$repo" && HOME="$home" bash "$rf" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "no argument and no log: exits non-zero and prints nothing"
else fail "no argument and no log: exit $rc, output: $out"; fi

mkdir -p "$tmp/not-a-repo" || abort "mkdir not-a-repo"
out="$(cd "$tmp/not-a-repo" && HOME="$home" bash "$rf" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "no argument outside a git repository: exits non-zero"
else fail "no argument outside a git repository: exit $rc, output: $out"; fi

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
elif [ $skips -ne 0 ]; then
  echo "all passed, $skips skipped"
else
  echo "all passed"
fi
