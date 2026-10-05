#!/usr/bin/env bash
# Prints four hashes of the working tree: file status, unstaged diff, staged diff,
# and the contents of untracked files. Exits non-zero if any step fails.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"

# Each hash is buffered, so a failing step exits before anything is printed.
status="$(git -C "$root" status --porcelain --untracked-files=all | git hash-object --stdin)"
unstaged="$(git -C "$root" diff | git hash-object --stdin)"
staged="$(git -C "$root" diff --cached | git hash-object --stdin)"
# ls-files and hash-object both resolve paths from the root, so the cwd does not matter.
untracked="$(git -C "$root" -c core.quotePath=false ls-files --others --exclude-standard \
  | git -C "$root" hash-object --stdin-paths \
  | git hash-object --stdin)"

printf '%s\n' "$status" "$unstaged" "$staged" "$untracked"
