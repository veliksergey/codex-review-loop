#!/usr/bin/env bash
# Lists the instruction files that the change under review edits: AGENTS.md,
# AGENTS.override.md, and CLAUDE.md in any folder, everything under a .codex folder, and
# docs/reviews/decisions.md. Prints "base: <commit>" and then one line per file,
# "<new|modified|deleted>: <path>", or the single word "none".
# Usage: instruction-changes.sh [<ref>]   compares the working tree with the merge base
# of <ref> and HEAD; without <ref>, with HEAD.
# Prints nothing and exits non-zero if the comparison cannot be made.
set -uo pipefail

fail() { echo "instruction-changes: $1" >&2; exit 1; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
# From the root, so that every path printed is relative to it.
cd "$root" || fail "cannot enter the repository's root"

if [ $# -ge 1 ]; then
  base="$(git merge-base "$1" HEAD 2>/dev/null)" || fail "no common commit with $1"
  shown="$base"
elif base="$(git rev-parse --verify --quiet HEAD 2>/dev/null)"; then
  shown="$base"
else
  # No commit yet: every file is new, compared with git's empty tree.
  base="$(git hash-object -t tree /dev/null)" || fail "cannot name the empty tree"
  shown="none, the repository has no commit yet"
fi

# The patterns match from the repository's root, in any folder below it.
specs=(':(top,glob)**/AGENTS.md' ':(top,glob)**/AGENTS.override.md' ':(top,glob)**/CLAUDE.md'
  ':(top,glob)**/.codex/**' ':(top,glob)docs/reviews/decisions.md')

# Tracked files against the base, then files git does not track yet. Git quotes a path
# that holds an unusual character, so every path stays on one line.
tracked="$(git diff --no-renames --name-status "$base" -- "${specs[@]}" 2>/dev/null)" ||
  fail "cannot compare the working tree with $shown"
untracked="$(git ls-files --others --exclude-standard -- "${specs[@]}" 2>/dev/null)" ||
  fail "cannot list the files git does not track"

# One line per path. A path named twice, as deleted and as an untracked file, exists
# and differs from the base: it is modified.
lines="$({ printf '%s\n' "$tracked"; printf '%s\n' "$untracked" | LC_ALL=C awk 'length($0) { print "?\t" $0 }'; } |
  LC_ALL=C awk -F '\t' '
  NF < 2 { next }
  {
    word = ($1 == "A" || $1 == "?") ? "new" : ($1 == "D") ? "deleted" : "modified"
    path = $0; sub(/^[^\t]*\t/, "", path)
    if (path in seen && seen[path] != word) word = "modified"
    seen[path] = word
  }
  END { for (path in seen) print path "\t" seen[path] }' | LC_ALL=C sort |
  LC_ALL=C awk -F '\t' '{ print $NF ": " substr($0, 1, length($0) - length($NF) - 1) }')" ||
  fail "cannot sort the list of instruction files"

if [ -z "$lines" ]; then
  echo "none"
else
  printf 'base: %s\n%s\n' "$shown" "$lines"
fi
