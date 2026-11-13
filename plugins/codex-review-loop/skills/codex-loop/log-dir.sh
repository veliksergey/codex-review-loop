#!/usr/bin/env bash
# Prints the folder that holds the task file and the review logs of the current
# repository: ~/.claude/codex-reviews/<name of the repository's root folder>.
# Repositories whose root folders share a name would share that folder, so the first to
# use it leaves its root path in a marker file there. Prints nothing and exits non-zero
# when the marker names another root, is empty, or cannot be read.
set -uo pipefail

fail() { echo "log-dir: $1" >&2; exit 1; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
[ -n "${HOME:-}" ] || fail "HOME is not set, so the log folder is unknown"
dir="$HOME/.claude/codex-reviews/$(basename "$root")"
marker="$dir/repository-root.txt"
mkdir -p "$dir" 2>/dev/null || fail "cannot create the log folder $dir"

if [ ! -e "$marker" ]; then
  # Claiming is one step that cannot half-happen: a link to a file that already holds
  # the root. It fails when a marker exists, so of several first runs only one claims.
  draft="$(mktemp "$dir/repository-root.XXXXXX" 2>/dev/null)"
  trap 'rm -f -- "$draft"' EXIT
  # When mktemp failed, the name is empty and this write fails with it.
  printf '%s\n' "$root" 2>/dev/null > "$draft" || fail "cannot write in the log folder $dir"
  # Without links on the file system, the nearest single step is to create the marker
  # in a way that never replaces one.
  ln -- "$draft" "$marker" 2>/dev/null || (set -o noclobber; printf '%s\n' "$root" > "$marker") 2>/dev/null || true
fi

# Whoever made the marker, its first line names the owner. A carriage return can end
# that line when the file was edited by hand on Windows. A marker that could not be
# made cannot be read either.
known="$(cat -- "$marker" 2>/dev/null)" ||
  fail "cannot read $marker, so the owner of the log folder $dir is unknown"
known="${known%%$'\n'*}"
known="${known%$'\r'}"
[ -n "$known" ] ||
  fail "$marker is empty, so the owner of the log folder $dir is unknown. Delete that file and run again."
[ "$known" = "$root" ] ||
  fail "the log folder $dir belongs to another repository with the same folder name: $known. Rename one of the two folders. If this repository was moved, delete $marker and run again."

printf '%s\n' "$dir"
