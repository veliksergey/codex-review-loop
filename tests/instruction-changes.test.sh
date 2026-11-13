#!/usr/bin/env bash
# Regression test for plugins/codex-review-loop/skills/codex-loop/instruction-changes.sh.
# Run from anywhere: bash tests/instruction-changes.test.sh
# INSTRUCTION_CHANGES=<script> runs the same cases against another implementation.
# Every repository below is made in a temporary folder.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ic="${INSTRUCTION_CHANGES:-$here/../plugins/codex-review-loop/skills/codex-loop/instruction-changes.sh}"
fails=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT
export GIT_CEILING_DIRECTORIES="$tmp"

g() { git -c user.name=test -c user.email=test -c core.autocrlf=false "$@"; }
# put <file> <text>: writes the file, making its folder.
put() { { mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" > "$1"; } || abort "write $1"; }
# run [<ref>]: runs the script in the current repository.
run() { out="$(bash "$ic" "$@" 2>"$tmp/err")"; rc=$?; }
# lists <name> <line>...: exit 0, and the output after its first line is exactly these lines.
lists() {
  local name="$1" want; shift
  want="$(printf '%s\n' "$@")"
  if [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | sed 1d)" = "$want" ]; then pass "$name"
  else fail "$name: exit $rc, output: $(printf '%s' "$out" | tr '\n' '|')"; fi
}
none() {
  if [ $rc -eq 0 ] && [ "$out" = "none" ]; then pass "$1"
  else fail "$1: exit $rc, output: $(printf '%s' "$out" | tr '\n' '|')"; fi
}
refused() {
  if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "$1: exits non-zero and prints nothing"
  else fail "$1: exit $rc, output: $out"; fi
}

repo="$tmp/work/repo"
mkdir -p "$repo" || abort "mkdir repo"
cd "$repo" || abort "cd repo"
g init -q . || abort "git init"

# No commit yet: there is nothing to compare with, so every instruction file is new.
run
none "a repository without a commit and without files: none"
put AGENTS.md "rules"
put src/app.py "code"
run
lists "a repository without a commit: an instruction file is new" "new: AGENTS.md"
if [ "$(printf '%s\n' "$out" | sed -n 1p)" = "base: none, the repository has no commit yet" ]; then
  pass "a repository without a commit: the first line says so"
else fail "a repository without a commit: first line: $(printf '%s\n' "$out" | sed -n 1p)"; fi

put CLAUDE.md "claude rules"
put sub/AGENTS.md "rules for sub"
put .codex/config.toml 'model = "x"'
put docs/reviews/decisions.md "| row 1 |"
put .gitignore "ignored/"
g add -A && g commit -q -m first || abort "first commit"
first="$(g rev-parse HEAD)"

run
none "a clean tree: none"
put src/app.py "other code"
put README.md "about"
run
none "changes to other files only: none"

# Every kind of instruction file, changed in every way git can hold a change.
put AGENTS.md "looser rules"
put sub/AGENTS.md "looser rules for sub"; g add sub/AGENTS.md
put deep/er/AGENTS.override.md "override"
put pkg/CLAUDE.md "more claude rules"; g add pkg/CLAUDE.md
put .codex/config.toml 'model = "y"'
put .codex/prompts/review.md "a prompt"
put pkg/.codex/config.toml 'model = "z"'
put docs/reviews/decisions.md "| row 1 |
| row 2 |"
rm CLAUDE.md || abort "rm CLAUDE.md"
run
lists "modified, staged, untracked, and deleted instruction files are all listed, sorted by path" \
  "modified: .codex/config.toml" "new: .codex/prompts/review.md" "modified: AGENTS.md" \
  "deleted: CLAUDE.md" "new: deep/er/AGENTS.override.md" "modified: docs/reviews/decisions.md" \
  "new: pkg/.codex/config.toml" "new: pkg/CLAUDE.md" "modified: sub/AGENTS.md"
if [ "$(printf '%s\n' "$out" | sed -n 1p)" = "base: $first" ]; then pass "the first line names the commit compared with"
else fail "first line: $(printf '%s\n' "$out" | sed -n 1p)"; fi

mkdir -p src/inner && cd src/inner || abort "cd src/inner"
run
lists "from a subfolder: the same list, with paths from the root" \
  "modified: .codex/config.toml" "new: .codex/prompts/review.md" "modified: AGENTS.md" \
  "deleted: CLAUDE.md" "new: deep/er/AGENTS.override.md" "modified: docs/reviews/decisions.md" \
  "new: pkg/.codex/config.toml" "new: pkg/CLAUDE.md" "modified: sub/AGENTS.md"
cd "$repo" || abort "cd repo"

# Names that only resemble an instruction file are not listed, and neither is one that
# git ignores.
g add -A && g commit -q -m second || abort "second commit"
put MY_AGENTS.md "not one"
put docs/AGENTS.md.bak "not one"
put agents.md.txt "not one"
put xcodex/config.toml "not one"
put docs/reviews/other.md "not one"
put docs/decisions.md "not one"
put pkg/docs/reviews/decisions.md "not the repository's own"
put ignored/AGENTS.md "ignored by git"
run
none "look-alike names and an ignored file: none"
g add -A && g commit -q -m third || abort "third commit"

# A file taken out of git's index and left on disk shows up twice, as deleted and as
# untracked. It exists and may differ: one line, modified.
g rm -q --cached AGENTS.md || abort "rm --cached"
run
lists "a file removed from the index and still on disk: one line, modified" "modified: AGENTS.md"
g add AGENTS.md || abort "re-add"

# A renamed instruction file is one deleted and one new.
g mv sub/AGENTS.md sub/AGENTS.override.md || abort "git mv"
run
lists "a renamed instruction file: the old name deleted, the new name new" \
  "deleted: sub/AGENTS.md" "new: sub/AGENTS.override.md"
g mv sub/AGENTS.override.md sub/AGENTS.md || abort "git mv back"

# A path with a space stays on one line.
put "my docs/AGENTS.md" "rules"
run
lists "a path with a space" "new: my docs/AGENTS.md"
rm -rf "my docs" || abort "rm my docs"

# With a ref: everything the branch changed since it left that ref, committed or not.
g branch -q base-point || abort "branch"
put AGENTS.md "rules changed on the branch"
g add -A && g commit -q -m "on the branch" || abort "branch commit"
put docs/reviews/decisions.md "| row 1 |
| row 2 |
| row 3 |"
run
lists "without a ref: only what is not committed" "modified: docs/reviews/decisions.md"
run base-point
lists "with a ref: committed and uncommitted changes since the common commit" \
  "modified: AGENTS.md" "modified: docs/reviews/decisions.md"
if [ "$(printf '%s\n' "$out" | sed -n 1p)" = "base: $(g rev-parse base-point)" ]; then pass "with a ref: the first line names the common commit"
else fail "with a ref: first line: $(printf '%s\n' "$out" | sed -n 1p)"; fi
# The ref has moved on since the branch left it: the common commit is still the base.
g checkout -q base-point && put src/app.py "work on the ref" && g add -A && g commit -q -m "on the ref" || abort "commit on the ref"
moved="$(g rev-parse HEAD)"
g checkout -q - || abort "checkout back"
run base-point
if [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" != "base: $moved" ]; then pass "with a ref that has moved on: the common commit is used, not the ref's tip"
else fail "with a ref that has moved on: exit $rc, first line: $(printf '%s\n' "$out" | sed -n 1p)"; fi

run no-such-ref
refused "a ref that does not exist"

mkdir -p "$tmp/plain" && cd "$tmp/plain" || abort "cd plain"
run
refused "outside a git repository"

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
else
  echo "all passed"
fi
