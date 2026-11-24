#!/usr/bin/env bash
# Regression test for the agent the review loop asks for a second look,
# plugins/codex-review-loop/agents/finding-checker.md, and for the name the loop's skill
# calls it by. The agent may only read, so its front matter must list Read, Grep, and
# Glob and nothing else. Run from anywhere: bash tests/finding-checker.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$here/../plugins/codex-review-loop"
agent="$plugin/agents/finding-checker.md"
skill="$plugin/skills/codex-loop/SKILL.md"
fails=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT

# front <file>: the lines of its front matter, which opens with "---" on the first line
# and closes at the next "---". Fails when the file has none, or when it never closes.
front() {
  awk '{ sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { closed = 1; exit }
    { lines[++n] = $0 }
    END { if (!closed) exit 1; for (i = 1; i <= n; i++) print lines[i] }' "$1"
}

# read_only <agent file>: why it is not the read-only agent the loop relies on; nothing
# when it is. Its front matter is exactly four lines of one key each: another key, a
# continuation line of YAML, or a comment could change what the agent may do or see.
read_only() {
  local matter keys
  # A shell variable drops a NUL byte, which YAML does not accept: look in the file.
  [ "$(tr -d '\000' < "$1" | wc -c | tr -d ' ')" = "$(wc -c < "$1" | tr -d ' ')" ] ||
    { echo "the file holds a NUL byte"; return; }
  matter="$(front "$1")" || { echo "no front matter"; return; }
  keys="$(printf '%s\n' "$matter" | sed -n 's/^\([A-Za-z][A-Za-z0-9_-]*\): .*/\1/p' |
    LC_ALL=C sort | tr '\n' ' ')"
  [ "$keys" = "description name omitClaudeMd tools " ] || echo "front matter keys: $keys"
  [ "$(printf '%s\n' "$matter" | wc -l | tr -d ' ')" = 4 ] ||
    echo "front matter is not four lines of one key each"
  printf '%s\n' "$matter" | grep -qx 'name: finding-checker' || echo "name is not finding-checker"
  printf '%s\n' "$matter" | grep -qx 'tools: Read, Grep, Glob' ||
    echo "tools are not exactly Read, Grep, Glob"
  # Without it the agent starts with the CLAUDE.md files, which a change can rewrite.
  printf '%s\n' "$matter" | grep -qx 'omitClaudeMd: true' || echo "omitClaudeMd is not true"
  # The documentation says a plugin's agent whose front matter does not parse still
  # loads, under its file name, so without the lines above: the description must parse.
  printf '%s\n' "$matter" | sed -n 's/^description: //p' | plain ||
    echo "description is not one line of plain YAML text"
}

# plain: whether YAML reads the one line on stdin, the value of a "key: value" line, as
# plain text: no character YAML gives a meaning to comes first, and the line holds no
# ": ", " #", or control character, such as a carriage return, and does not end with ":".
plain() {
  LC_ALL=C awk -v first='-?:,[]{}#&*!|>%@`"'"'"' ' '
    BEGIN { control = sprintf("[%c-%c%c]|%c[%c-%c]", 1, 31, 127, 194, 128, 159) }
    NR == 1 { line = $0 }
    END {
      if (NR != 1 || line == "" || index(first, substr(line, 1, 1))) exit 1
      if (index(line, ": ") || index(line, " #") || line ~ control) exit 1
      if (substr(line, length(line)) == ":") exit 1
    }'
}

# called <skill file>: the value the skill sets subagent_type to at each call, one per
# line. The text is joined into one line first, since a call can wrap.
called() {
  tr '\n' ' ' < "$1" | grep -o -E '`subagent_type` set to +`[^`]*`' | sed 's/.*`\([^`]*\)`$/\1/'
}

# The plugin's name: the first "name" in plugin.json, before the author's.
prefix="$(sed -n 's/^[[:space:]]*"name":[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$plugin/.claude-plugin/plugin.json" | head -n 1)"
[ -n "$prefix" ] || abort "cannot read the plugin's name"

# The name in the front matter of each agent of the plugin, between spaces.
agents=" "
for file in "$plugin"/agents/*.md; do
  [ -f "$file" ] || continue
  agents="$agents$(front "$file" | sed -n 's/^name: *//p' | head -n 1) "
done

# names <skill file>: each name of the form <plugin>:<name> that the skill uses and that
# is neither a skill nor an agent of the plugin.
names() {
  local name
  for name in $(grep -o -E "$prefix:[a-z0-9-]+" "$1" | sed "s/^$prefix://" | LC_ALL=C sort -u); do
    [ -d "$plugin/skills/$name" ] && continue
    case "$agents" in *" $name "*) continue ;; esac
    echo "$prefix:$name"
  done
}

why="$(read_only "$agent")"
if [ -z "$why" ]; then
  pass "the agent: named finding-checker, with only Read, Grep, and Glob, and no CLAUDE.md files"
else fail "the agent: $why"; fi

# The same check catches each way the agent could gain a tool or its CLAUDE.md files.
# Each variant differs from a valid front matter in one way only.
caught() {
  if [ -n "$(read_only "$2")" ]; then pass "caught: $1"; else fail "not caught: $1"; fi
}
variant() { printf -- '---\n%s\n---\nx\n' "$2" > "$tmp/$1.md" || abort "write a variant"; }
n='name: finding-checker'; d='description: x'; t='tools: Read, Grep, Glob'; o='omitClaudeMd: true'
variant valid "$n
$d
$t
$o"
if [ -z "$(read_only "$tmp/valid.md")" ]; then pass "a valid variant passes, so each one below fails for its own reason"
else fail "the valid variant: $(read_only "$tmp/valid.md")"; fi
variant a "$n
$d
tools: Read, Grep, Glob, Bash
$o"
caught "a fourth tool" "$tmp/a.md"
variant b "$n
$d
$o"
caught "no tools line, which gives the agent every tool" "$tmp/b.md"
variant c "$n
$d
$t
$o
model: x"
caught "a key besides name, description, tools, and omitClaudeMd" "$tmp/c.md"
variant d "$n
$d
tools:
  - Read
  - Bash
$o"
caught "tools written as a list" "$tmp/d.md"
variant e "$n
$d
$t
  , Bash
$o"
caught "a continuation line that adds a tool to the tools line" "$tmp/e.md"
variant f "$n
$d
$t
# a comment
$o"
caught "a comment line" "$tmp/f.md"
variant g "$n
$d
$t"
caught "no omitClaudeMd, which gives the agent the CLAUDE.md files" "$tmp/g.md"
variant h "$n
$d
$t
omitClaudeMd: false"
caught "omitClaudeMd set to false" "$tmp/h.md"
printf -- '%s\n%s\n' "$n" "$t" > "$tmp/i.md" || abort "write a variant"
caught "no front matter" "$tmp/i.md"
printf -- '---\n%s\n%s\n%s\n%s\n' "$n" "$d" "$t" "$o" > "$tmp/j.md" || abort "write a variant"
caught "front matter that never closes" "$tmp/j.md"
printf -- '---\n%s\ndescription: a\000b\n%s\n%s\n---\nx\n' "$n" "$t" "$o" > "$tmp/nul.md" ||
  abort "write a variant"
caught "a NUL byte in the description, which a shell variable would drop" "$tmp/nul.md"
printf -- '---\r\n%s\r\n%s\r\n%s\r\n%s\r\n---\r\nx\r\n' "$n" "$d" "$t" "$o" > "$tmp/k.md" ||
  abort "write a variant"
if [ -z "$(read_only "$tmp/k.md")" ]; then pass "an agent file with Windows line endings is read"
else fail "an agent file with Windows line endings: $(read_only "$tmp/k.md")"; fi

# A description that YAML does not read as plain text: the front matter would not
# parse, or the description would end early.
tab="$(printf '\t')"
cr="$(printf '\r')"
count=0
missed=""
for text in '[unfinished' '{a: b}' '"quoted"' "'quoted'" '&anchor x' '*alias' '!tag x' \
  '| block' '> folded' '- item' '? key' '% x' '@ x' '`x`' ', x' 'one: two' \
  'text # comment' 'ends with:' "a${tab}tab" '' "First sentence.${cr}Second sentence." \
  "a$(printf '\001')b" "a$(printf '\177')b" "a$(printf '\302\205')b"; do
  variant l "$n
description: $text
$t
$o"
  if [ -n "$(read_only "$tmp/l.md")" ]; then count=$((count + 1)); else missed="$missed [$text]"; fi
done
if [ -z "$missed" ]; then pass "each of $count descriptions that YAML does not read as plain text is caught"
else fail "descriptions that YAML does not read as plain text, not caught:$missed"; fi
variant m "$n
description: Read-only check, for the codex-loop skill's second look (P0-P3). Use it only when asked.
$t
$o"
if [ -z "$(read_only "$tmp/m.md")" ]; then
  pass "a description of plain prose, with commas, an apostrophe, and parentheses, passes"
else fail "a description of plain prose: $(read_only "$tmp/m.md")"; fi

missing="$(names "$skill")"
if [ -z "$missing" ] && grep -qF "$prefix:finding-checker" "$skill"; then
  pass "the skill calls the agent as $prefix:finding-checker, and each such name it uses exists"
else
  fail "the skill: names that are neither a skill nor an agent: ${missing:-none}, or it never names $prefix:finding-checker"
fi
sed "s/$prefix:finding-checker/$prefix:finding-checkr/" "$skill" > "$tmp/SKILL.md" ||
  abort "write a variant of the skill"
if [ "$(names "$tmp/SKILL.md")" = "$prefix:finding-checkr" ]; then
  pass "a misspelled agent name in the skill is caught"
else
  fail "a misspelled agent name in the skill is not caught"
fi

# The call itself names the agent: a mention elsewhere in the skill does not count.
# The public name, written out: a name read from the manifest would follow a rename.
got="$(called "$skill")"
if [ "$got" = "codex-review-loop:finding-checker" ]; then
  pass "the skill has one call of an agent, and it sets subagent_type to codex-review-loop:finding-checker"
else
  fail "the calls in the skill set subagent_type to: ${got:-nothing}"
fi
tr '\n' ' ' < "$skill" | sed 's/\(`subagent_type` set to *\)`[^`]*`/\1`general-purpose`/' \
  > "$tmp/swapped.md" || abort "write a variant of the skill"
if [ "$(called "$tmp/swapped.md")" = "general-purpose" ] &&
  grep -qF "$prefix:finding-checker" "$tmp/swapped.md"; then
  pass "a call swapped to another agent is caught, though the skill still names the agent elsewhere"
else
  fail "a call swapped to another agent is not caught"
fi

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
else
  echo "all passed"
fi
