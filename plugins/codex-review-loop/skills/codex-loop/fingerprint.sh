#!/usr/bin/env bash
# Prints four hashes of the working tree: file status, unstaged diff, staged diff,
# and the contents of untracked files (links by where they point). Exits non-zero if
# any step fails.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"

# record <field>...: the hash of the NUL-terminated fields, so no file name can make
# two different trees produce the same records.
record() { printf '%s\0' "$@" | git hash-object --stdin; }

# A link is recorded by its destination, never followed: hash-object would read the
# target, and git on Windows lists a junction's contents as if it were a folder.
# readlink's output is kept whole, trailing newlines included.
link_record() {
  local t
  t="$(readlink -- "$root/$1" && printf x)" || return 1
  record L "$1" "${t%x}"
}

# outer_link <path>: the outermost link among the path and its parent folders, if any.
outer_link() {
  local p="$1" link=""
  while :; do
    if [ -L "$root/$p" ]; then link="$p"; fi
    case "$p" in */*) p="${p%/*}" ;; *) break ;; esac
  done
  printf '%s' "$link"
}

# Untracked files. A file reached through a link stands for that link instead: git on
# Windows walks into a junction, even one that replaces a tracked folder.
untracked_files() {
  local last=""
  git -C "$root" -c core.quotePath=false ls-files -z --others --exclude-standard \
    | while IFS= read -r -d '' f; do
        link="$(outer_link "$f")"
        if [ -n "$link" ]; then
          # Files behind one link arrive together; the final sort -u removes any repeat.
          if [ "$link" != "$last" ]; then link_record "$link" || exit 1; fi
          last="$link"
        else
          h="$(git -C "$root" hash-object -- "$f")" || exit 1
          # The executable bit is part of what git commits; hash-object ignores it.
          mode=644; if [ -x "$root/$f" ]; then mode=755; fi
          record F "$f" "$mode" "$h" || exit 1
        fi
      done
}

# Links that replace a folder of tracked files: git on Windows reads through a junction
# as if it were the folder, so the files can look unchanged and no untracked path leads
# to it. Each folder is checked once; paths arrive sorted.
tracked_links() {
  local last_dir="" last_link=""
  git -C "$root" -c core.quotePath=false ls-files -z \
    | while IFS= read -r -d '' f; do
        case "$f" in */*) d="${f%/*}" ;; *) continue ;; esac
        if [ "$d" = "$last_dir" ]; then continue; fi
        last_dir="$d" p="$d" link=""
        while :; do
          if [ -L "$root/$p" ]; then link="$p"; fi
          case "$p" in */*) p="${p%/*}" ;; *) break ;; esac
        done
        if [ -n "$link" ] && [ "$link" != "$last_link" ]; then
          link_record "$link" || exit 1
          last_link="$link"
        fi
      done
}

# Reads NUL-terminated paths and writes back those git does not ignore: no matching
# pattern, or a negated one (!), which un-ignores. check-ignore exits 1 when nothing is
# ignored, which is not a failure.
not_ignored() {
  { git -C "$root" check-ignore -z --stdin --non-matching --verbose || [ $? -eq 1 ]; } \
    | while IFS= read -r -d '' src && IFS= read -r -d '' num && IFS= read -r -d '' pat \
        && IFS= read -r -d '' path; do
        case "$pat" in '' | '!'*) printf '%s\0' "$path" ;; esac
      done
}

# Untracked links, also those that lead to an empty folder: git lists no file behind
# them, but --directory lists them, and find looks inside untracked folders. Links in
# ignored folders are left out, like every ignored file.
untracked_links() {
  git -C "$root" -c core.quotePath=false ls-files -z --others --exclude-standard --directory \
    | while IFS= read -r -d '' e; do
        e="${e%/}"
        # An entry at or under a link stands for that link; its target is not searched.
        link="$(outer_link "$e")"
        if [ -n "$link" ]; then
          link_record "$link" || exit 1
        elif [ -d "$root/$e" ]; then
          # "./" keeps a folder named like a find action, such as -delete, a folder name.
          (cd "$root" && find "./$e" -type l -print0) \
            | while IFS= read -r -d '' l; do printf '%s\0' "${l#./}"; done \
            | not_ignored \
            | while IFS= read -r -d '' l; do link_record "$l" || exit 1; done || exit 1
        fi
      done
}

# Each hash is buffered, so a failing step exits before anything is printed.
status="$(git -C "$root" status --porcelain --untracked-files=all | git hash-object --stdin)"
# External diff and textconv drivers from the user's git config could print nothing
# for a real change; these flags make the diffs record exact content.
unstaged="$(git -C "$root" diff --no-ext-diff --no-textconv --binary --full-index | git hash-object --stdin)"
staged="$(git -C "$root" diff --cached --no-ext-diff --no-textconv --binary --full-index | git hash-object --stdin)"
# Paths are resolved from the root, so the cwd does not matter.
untracked="$({ untracked_files && untracked_links && tracked_links; } | LC_ALL=C sort -u | git hash-object --stdin)"

printf '%s\n' "$status" "$unstaged" "$staged" "$untracked"
