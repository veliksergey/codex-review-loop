#!/usr/bin/env bash
# Regression test for plugins/codex-review-loop/skills/codex-loop/task-hash.sh.
# Run from anywhere: bash tests/task-hash.test.sh
# TASK_HASH=<script> runs the same cases against another implementation.
# The repository, the home folder, and every task file below are made in a temporary
# folder.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
th="${TASK_HASH:-$here/../plugins/codex-review-loop/skills/codex-loop/task-hash.sh}"
fails=0
skips=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
skip() { echo "skip - $1"; skips=$((skips + 1)); }

tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT
export GIT_CEILING_DIRECTORIES="$tmp"

home="$tmp/home dir"
repo="$tmp/work/myrepo"
task="$home/.claude/codex-reviews/myrepo/task.md"
mkdir -p "$repo/sub" "$(dirname "$task")" || abort "mkdir"
git -C "$repo" init -q . || abort "git init"

run() { out="$(cd "${1:-$repo}" && HOME="$home" bash "$th" 2>"$tmp/err")"; rc=$?; }
refused() {
  if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "$1: exits non-zero and prints nothing"
  else fail "$1: exit $rc, output: $out"; fi
}
hashed() {
  if [ $rc -eq 0 ] && [ "${#out}" -eq 40 ]; then pass "$1"; else fail "$1: exit $rc, output: $out"; fi
}
# same <name>, differs <name>: the hash is, or is not, the one kept in $first.
same() { if [ $rc -eq 0 ] && [ "$out" = "$first" ]; then pass "$1"; else fail "$1: exit $rc, $out, wanted $first"; fi; }
differs() {
  if [ $rc -eq 0 ] && [ "$out" != "$first" ] && [ "${#out}" -eq 40 ]; then pass "$1"
  else fail "$1: exit $rc, output: $out"; fi
}
# write <request line> <criterion line> <decision line>: a task file with all sections.
write() {
  printf '# Task: myrepo\n\n## Request (verbatim)\n\n> %s\n\n## Acceptance criteria\n\n1. %s\n2. The second criterion.\n\n## Out of scope\n\nnone stated\n\n## Decisions during implementation\n\n- [implementer] %s\n\n## Handoff\n\nFiles: a.txt\n' \
    "$1" "$2" "$3" > "$task" || abort "write the task file"
}
# lines <line...>: a task file made of the given lines and nothing else.
lines() { printf '%s\n' "$@" > "$task" || abort "write the task file"; }
# put <line> <lines...>: adds the given lines below that line of the task file.
put() {
  local at="$1"; shift
  printf '%s\n' "$@" > "$tmp/block" || abort "write the lines to add"
  awk -v at="$at" '
    NR == FNR { block[++n] = $0; next }
    { print }
    $0 == at { for (i = 1; i <= n; i++) print block[i]; hits++ }
    END { exit (hits == 1) ? 0 : 1 }' "$tmp/block" "$task" > "$tmp/t" && cp "$tmp/t" "$task" ||
    abort "add lines below: $at"
}
# reword <line> <new line>: replaces that line of the task file.
reword() {
  awk -v old="$1" -v new="$2" '
    $0 == old { print new; hits++; next }
    { print }
    END { exit (hits == 1) ? 0 : 1 }' "$task" > "$tmp/t" && cp "$tmp/t" "$task" || abort "reword: $1"
}

run
if [ $rc -eq 0 ] && [ "$out" = "none" ]; then pass "no task file: prints none"
else fail "no task file: exit $rc, output: $out"; fi

write "add a button" "The button exists." "used a link"
run
first="$out"
hashed "a task file with both sections: prints one hash"
# The hash is git's hash of the two sections' lines without the blank ones.
want="$(printf '## Request (verbatim)\n> add a button\n## Acceptance criteria\n1. The button exists.\n2. The second criterion.\n' | git hash-object --stdin)"
if [ "$first" = "$want" ]; then pass "the hash covers the two sections and nothing else"
else fail "the hash is $first, wanted $want"; fi

run "$repo/sub"
same "from a subfolder: the same hash"

# What does not change the meaning does not change the hash.
write "add a button" "The button exists." "decided something else entirely"
printf '\nRisks: more\n' >> "$task"
reword "none stated" "something else"
run
same "a change in the out-of-scope section, the decisions, and the handoff: the same hash"
sed 's/$/   /' "$task" > "$tmp/t" && cp "$tmp/t" "$task" || abort "trailing spaces"
run
same "spaces at the ends of lines: the same hash"
awk '/^## / { print ""; print "" } { print }' "$task" > "$tmp/t" && cp "$tmp/t" "$task" || abort "blank lines"
run
same "more blank lines: the same hash"
write "add a button" "The button exists." "used a link"
awk '{ printf "%s\r\n", $0 }' "$task" > "$tmp/t" && cp "$tmp/t" "$task" || abort "line endings"
run
same "Windows line endings: the same hash"

# What changes the request or a criterion changes the hash.
write "add a red button" "The button exists." "used a link"
run
differs "a word added to the request: another hash"
write "add a button" "The button exists or not." "used a link"
run
differs "a criterion reworded: another hash"
write "add a button" "The button exists." "used a link"
put "2. The second criterion." "3. A third criterion."
run
differs "a criterion added: another hash"
grep -v '^2\. The second criterion\.$' "$task" | grep -v '^3\. A third' > "$tmp/t" && cp "$tmp/t" "$task" || abort "remove a criterion"
run
differs "a criterion removed: another hash"

# The request is the user's own text. A fenced block in it, and headings of its own, do
# not end it: what follows them is still part of the hash.
fenced() { # fenced <mark> <a word in the block> <a word after the block>
  write "add a button" "The button exists." "used a link"
  put "> add a button" "" "$1md" "## Public API" "Authentication is $2." "$1" "Everything stays $3."
}
fenced '```' mandatory quiet
run
first="$out"
hashed "a request with a fenced block: prints one hash"
fenced '```' optional quiet
run
differs "a word changed inside the fenced block, below a line that looks like a heading: another hash"
fenced '```' mandatory loud
run
differs "a word changed after the fenced block: another hash"
fenced '~~~' mandatory quiet
run
differs "another fence mark is other text: another hash"
fenced '~~~' optional quiet
run
first="$out"
fenced '~~~' mandatory quiet
run
differs "a word changed inside a block fenced with tildes: another hash"
write "add a button" "The button exists." "used a link"
put "> add a button" "" "## Background" "The old button was blue." "" "## Request details" "It sits in the toolbar."
run
first="$out"
hashed "a request with headings of its own: prints one hash"
reword "The old button was blue." "The old button was red."
run
differs "a word changed below a heading inside the request: another hash"
first="$out"
reword "> add a button" "> add a link"
run
differs "a word changed above a second request heading: another hash"

# A pasted request can hold the template's own headings. The last acceptance criteria
# heading starts the criteria, and a heading above it ends nothing.
write "add a button" "The button exists." "used a link"
put "> add a button" "" "## Acceptance criteria" "- It is blue." "" "## Out of scope" "Ask the designer." "" "## Handoff" "Files: none"
run
first="$out"
reword "Ask the designer." "Ask nobody."
run
differs "a word changed in a request that holds the template's headings: another hash"
first="$out"
reword "1. The button exists." "1. The button is gone."
run
differs "a criterion changed below such a request: another hash"
first="$out"
reword "none stated" "something else"
run
same "the criteria below such a request end at the out-of-scope heading"
lines "## Request" "add a button" "## Acceptance criteria" "- It is blue." "## Out of scope" "Ask the designer." \
  "## Acceptance criteria" "1. The button exists." "## Decisions during implementation" "- none"
run
first="$out"
reword "1. The button exists." "1. The button is gone."
run
differs "an out-of-scope heading above the criteria does not end them when none follows: another hash"

# Where the criteria end. A line that looks like a heading ends them only when it is the
# last out-of-scope heading, so a look-alike above the real one changes nothing.
write "add a button" "The button exists." "used a link"
put "2. The second criterion." "<!--" "## implementation note" "-->" "3. A third criterion."
run
first="$out"
reword "3. A third criterion." "3. Another third criterion."
run
differs "a criterion changed below an HTML comment that holds a line like a heading: another hash"
write "add a button" "The button exists." "used a link"
put "2. The second criterion." "<pre>" "## Out of scope" "</pre>" "3. A third criterion."
run
first="$out"
reword "3. A third criterion." "3. Another third criterion."
run
differs "a criterion changed below a line that only looks like the out-of-scope heading: another hash"
# A file without the heading: the last decisions heading ends the hashed text, then the
# last handoff heading, then the end of the file. What stands above that point is hashed.
write "add a button" "The button exists." "used a link"
reword "## Out of scope" "## Notes"
run
first="$out"
reword "none stated" "something else"
run
differs "a section the template does not have is hashed with the criteria above it"
first="$out"
reword "- [implementer] used a link" "- [implementer] used a button"
run
same "without an out-of-scope heading the hashed text ends at the decisions heading"
reword "## Decisions during implementation" "## Log"
run
first="$out"
reword "- [implementer] used a button" "- [implementer] used a switch"
run
differs "without a decisions heading either, the text above the handoff heading is hashed"
first="$out"
reword "Files: a.txt" "Files: b.txt"
run
same "and the hashed text ends at the handoff heading"
lines "## Request" "" "add a button" "" "## Acceptance criteria" "" "1. The button exists."
run
want="$(printf '## Request\nadd a button\n## Acceptance criteria\n1. The button exists.\n' | git hash-object --stdin)"
if [ $rc -eq 0 ] && [ "$out" = "$want" ]; then pass "criteria that end the file are hashed to its last line"
else fail "criteria that end the file: exit $rc, $out, wanted $want"; fi

# A request heading below the criteria starts hashed text again, up to the next of the
# three headings that end it.
write "add a button" "The button exists." "used a link"
printf '\n## Request (follow-up)\n\n> make it red\n' >> "$task" || abort "a later request"
run
first="$out"
reword "> make it red" "> make it green"
run
differs "a word changed in a request section below the handoff: another hash"
write "add a button" "The button exists." "used a link"
put "none stated" "" "## Request (follow-up)" "" "> make it red"
run
first="$out"
reword "> make it red" "> make it green"
run
differs "a word changed in a request section below the out-of-scope section: another hash"
first="$out"
reword "- [implementer] used a link" "- [implementer] used a button"
run
same "a later request section ends at the next heading of the template"

# A template heading inside a fenced block or an HTML comment is text. Below the criteria
# it would otherwise move the end of the hashed text, or start a request.
below() { # below <name> <lines to add to the handoff>: a changed decision is not seen
  local name="$1"; shift
  write "add a button" "The button exists." "used a link"
  put "Files: a.txt" "$@"
  run
  first="$out"
  reword "- [implementer] used a link" "- [implementer] used a button"
  run
  same "$name"
}
below "an out-of-scope heading in a fenced block of the handoff ends nothing" '```' '## Out of scope' '```'
below "an out-of-scope heading in an HTML comment of the handoff ends nothing" '<!--' '## Out of scope' '-->'
below "a criteria heading in a fenced block of the handoff starts nothing" '```' '## Acceptance criteria' '```'
write "add a button" "The button exists." "used a link"
put "Files: a.txt" '```' '## Request' 'a sample line' '```'
run
first="$out"
reword "a sample line" "another sample line"
run
same "a request heading in a fenced block of the handoff starts nothing"

# What a block is. hides <name> <lines...>: the lines form one block and hold an acceptance
# criteria heading. Inside the block it is no heading, so the file has no criteria; below
# the block a heading is seen again.
hides() {
  local name="$1"; shift
  lines "## Request" "" "add a button" "" "$@"
  run
  refused "$name: a heading inside"
  lines "## Request" "" "add a button" "" "$@" "" "## Acceptance criteria" "" "1. The button exists."
  run
  hashed "$name: a heading below is seen"
}
hides "a block fenced with backticks" '```md' '## Acceptance criteria' '```'
hides "a block fenced with tildes" '~~~' '## Acceptance criteria' '~~~'
hides "a block that holds a shorter fence" '````' '```' '## Acceptance criteria' '```' '````'
hides "a block closed by a longer run" '```' '## Acceptance criteria' '`````'
hides "a run of the other mark inside a block" '```' '~~~' '## Acceptance criteria' '```'
hides "a run of both marks inside a block" '```' '```~~~' '## Acceptance criteria' '```'
hides "a run with text after it inside a block" '```text' '```js opens a block in Markdown' '## Acceptance criteria' '```'
hides "a run after four spaces inside a block" '```' '    ```' '## Acceptance criteria' '```'
hides "a block fenced after three spaces" '   ```' '## Acceptance criteria' '   ```'
hides "a tilde fence whose first line holds backticks" '~~~ `md`' '## Acceptance criteria' '~~~'
hides "an HTML comment" '<!--' '## Acceptance criteria' '-->'
hides "an HTML comment after three spaces that closes inside a line" '   <!-- a note' '## Acceptance criteria' 'the end --> of it'
hides "a fence mark inside an HTML comment" '<!--' '```' '## Acceptance criteria' '-->'
hides "an HTML comment mark inside a fenced block" '```' '<!--' '## Acceptance criteria' '```'
# shows <name> <line>: the line opens no block, so a heading right below it is seen.
shows() {
  lines "## Request" "" "add a button" "$2" "## Acceptance criteria" "" "1. The button exists."
  run
  hashed "$1"
}
shows "two backticks open no block" '`` opens a span.'
shows "two backticks around a word open no block" '``x`` stays as it is.'
shows "two tildes open no block" '~~struck~~ stays as well.'
shows "three backticks with a backtick after them open no block" '```value``` is literal code.'
shows "a run after four spaces opens no block" '    ```'
shows "an HTML comment that closes on its first line hides nothing below" '<!-- a note -->'
shows "an HTML comment that closes where it opens hides nothing below" '<!-->'
shows "an HTML comment mark inside a line opens no comment" 'See <!-- this.'
shows "an HTML comment mark after four spaces opens no comment" '    <!--'

# A heading without the word in brackets is still the request.
write "add a button" "The button exists." "used a link"
reword "## Request (verbatim)" "## Request"
run
hashed "a request heading without brackets is accepted"

# A file without one of the two headings, or with the criteria only above the request,
# cannot be hashed. A block that never closes hides the headings below it.
write "add a button" "The button exists." "used a link"
reword "## Acceptance criteria" "## Criteria"
run
refused "no acceptance criteria section"
write "add a button" "The button exists." "used a link"
reword "## Request (verbatim)" "## What was asked"
run
refused "no request section"
lines "## Acceptance criteria" "" "1. The button exists." "" "## Request" "" "add a button"
run
refused "the acceptance criteria above the request and none below it"
write "add a button" "The button exists." "used a link"
put "> add a button" "" '```'
run
refused "a fenced block in the request that never closes"
write "add a button" "The button exists." "used a link"
put "> add a button" "" '<!-- a note'
run
refused "an HTML comment in the request that never closes"
: > "$task" || abort "empty the task file"
run
refused "an empty task file"

mkdir -p "$tmp/plain" || abort "mkdir plain"
run "$tmp/plain"
refused "outside a git repository"

# No home folder. Some systems give a shell a home folder when HOME is empty; there
# the case would look into a real home, so it is not run.
if [ -z "$(HOME='' bash -c 'printf %s "$HOME"')" ]; then
  out="$(cd "$repo" && HOME='' bash "$th" 2>/dev/null)"; rc=$?
  refused "HOME is empty"
else
  skip "HOME is empty: this system sets a home folder for the shell itself"
fi

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
elif [ $skips -ne 0 ]; then
  echo "all passed, $skips skipped"
else
  echo "all passed"
fi
