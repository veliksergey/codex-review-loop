#!/usr/bin/env bash
# Regression test for how the review loop reads the facts of a rebuttal with
# plugins/codex-review-loop/skills/codex-loop/round-facts.sh. A rebuttal's log and prompt
# are <run>-round<N>-rebuttal-codex.log and -rebuttal-prompt.md, and the loop checks the
# log= line to know whose facts it read. Kept apart from round-facts.test.sh, which a
# case of the evaluation corpus takes as its proof. Run from anywhere:
# bash tests/rebuttal-facts.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rf="$here/../plugins/codex-review-loop/skills/codex-loop/round-facts.sh"
fails=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
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

# Synthetic logs, built at run time so that no line of this file has the shape of a log
# event: a header, the echoed prompt, shell commands that ran, and the answer.
rule="--------"
header() {
  printf 'OpenAI Codex v0.0.1\n%s\nworkdir: /work/repo\nmodel: test-model\nprovider: test\n' "$rule"
  printf 'approval: never\nsandbox: read-only\nreasoning effort: high\nreasoning summaries: none\n'
  printf 'session id: 00000000-0000-0000-0000-000000000001\n%s\n' "$rule"
}
prompt() { printf 'user\n<role>\nreview this\n</role>\n%s\n' "</grounding_rules>"; }
ran_ok() { printf '%s\n"sh" -c "git status" in /work/repo\n succeeded in 12ms:\n M a.txt\n\n' "exec"; }
final() { printf 'codex\nNo findings.\n'; }

home="$tmp/home"; repo="$tmp/work/myrepo"; logs="$home/.claude/codex-reviews/myrepo"
mkdir -p "$repo" "$logs" || abort "folders"
git -C "$repo" init -q . || abort "git init"
{ header; prompt; ran_ok; final; } > "$logs/20260101-000000-round1-codex.log"
touch -t 202601010000 "$logs/20260101-000000-round1-codex.log" || abort "touch round 1"
printf 'round\n' > "$logs/20260101-000000-round1-prompt.md" || abort "write round 1's prompt"

# A round's rebuttal writes its log after the round's. Its log is then the newest one,
# and the prompt beside it is the rebuttal's, not the round's. Its hash is git's hash of
# the six bytes "hello" and a line feed, in the repository's own object format.
hello="$(printf 'hello\n' | git -C "$repo" hash-object --stdin)" || abort "hash the prompt"
{ header; prompt; ran_ok; ran_ok; final; } > "$logs/20260101-000000-round1-rebuttal-codex.log"
touch -t 202601010010 "$logs/20260101-000000-round1-rebuttal-codex.log" || abort "touch the rebuttal"
printf 'hello\n' > "$logs/20260101-000000-round1-rebuttal-prompt.md" || abort "write the rebuttal's prompt"
out="$(cd "$repo" && HOME="$home" bash "$rf")"
expect "a rebuttal after its round: its own log and prompt are read" "$out" \
  "log=20260101-000000-round1-rebuttal-codex.log" "shell_ran=2" \
  "prompt_hash=$hello"

# A later log of another run is the newest one then, and is read instead. Its log= line
# names it: the loop checks that line to know whose facts it has.
{ header; prompt; final; } > "$logs/20260101-000100-round1-codex.log"
touch -t 202601010015 "$logs/20260101-000100-round1-codex.log" || abort "touch the later log"
out="$(cd "$repo" && HOME="$home" bash "$rf")"
expect "a later log of another run is read instead, and its log= line names it" "$out" \
  "log=20260101-000100-round1-codex.log" "shell_ran=0"

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
else
  echo "all passed"
fi
