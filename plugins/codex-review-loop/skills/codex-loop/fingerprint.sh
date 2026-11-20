#!/usr/bin/env bash
# Prints four hashes of the working tree: the commit with the file status, the unstaged
# diff, the staged diff, and the files as they are on disk (tracked and untracked files
# by their bytes, links by where they point, a repository inside this one by its own
# four hashes). Exits non-zero if any step fails.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
# This script, to run it in a repository that lies inside this one.
self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

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

# inner <letter> <path>: a repository that lies inside this one, recorded by its own
# four hashes. Git shows it as one entry, and not what changes in it. A folder that git
# takes for such a repository and that is none would lead back here, so it is refused.
inner() {
  local top hashes
  top="$(git -C "$root/$2" rev-parse --show-toplevel)" || return 1
  [ "$top" != "$root" ] || return 1
  hashes="$(cd "$root/$2" && bash "$self")" || return 1
  record "$1" "$2" "$hashes"
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
        elif [ "${f%/}" != "$f" ]; then
          # Git lists a folder, not its files, where the folder is a repository of its own.
          inner R "${f%/}" || exit 1
        else
          # --no-filters: the bytes on disk, not what a clean filter or a line-ending
          # setting would make of them.
          h="$(git -C "$root" hash-object --no-filters -- "$f")" || exit 1
          # The executable bit is part of what git commits; hash-object ignores it.
          mode=644; if [ -x "$root/$f" ]; then mode=755; fi
          record F "$f" "$mode" "$h" || exit 1
        fi
      done
}

# Tracked paths as they are on disk, a file by its bytes and a link by where it points:
# git's status and diffs compare what git would store, and pass over a path marked as
# unchanged. A path that holds neither is left out, and the list of names shows that.
tracked_files() {
  git -C "$root" ls-files -z \
    | {
        plain="" dir="" behind=""
        while IFS= read -r -d '' f; do
          # Nothing behind a link is read: a link in the place of a folder stands for the
          # files below it. Each folder is checked once; paths arrive sorted.
          case "$f" in */*) d="${f%/*}" ;; *) d="" ;; esac
          if [ "$d" != "$dir" ]; then
            dir="$d" behind="" p="$d"
            while [ -n "$p" ]; do
              if [ -L "$root/$p" ]; then behind=1; break; fi
              case "$p" in */*) p="${p%/*}" ;; *) p="" ;; esac
            done
          fi
          if [ -n "$behind" ]; then continue; fi
          if [ -L "$root/$f" ]; then link_record "$f" || exit 1; continue; fi
          if [ ! -f "$root/$f" ]; then continue; fi
          case "$f" in
            # hash-object reads one name on a line, and takes a quote at the start of a
            # line for the start of a quoted name. Such a name is hashed by itself.
            '"'* | *$'\n'* | *$'\r')
              h="$(git -C "$root" hash-object --no-filters -- "$f")" || exit 1
              record T "$f" "$h" || exit 1 ;;
            *) plain+="$f"$'\n' ;;
          esac
        done
        if [ -n "$plain" ]; then
          # One git for all the files: the names, and the hashes in the order of the names.
          names="$(printf '%s' "$plain" | git hash-object --stdin)" || exit 1
          bytes="$(printf '%s' "$plain" | git -C "$root" hash-object --no-filters --stdin-paths \
            | git hash-object --stdin)" || exit 1
          record TS "$names" "$bytes" || exit 1
        fi
      }
}

# Submodules that are checked out. Git's status and diffs say that one is changed, and
# not what changed in it; one that is not checked out has no .git and nothing to record.
# A link in the place of a submodule, or of a folder above it, stands for itself.
submodules() {
  git -C "$root" ls-files -s -z \
    | while IFS= read -r -d '' entry; do
        # An entry reads: mode, object, stage, a tab, and the path. 160000 is a submodule.
        if [ "${entry%% *}" != 160000 ]; then continue; fi
        path="${entry#*$'\t'}"
        link="$(outer_link "$path")"
        if [ -n "$link" ]; then
          link_record "$link" || exit 1
        elif [ -e "$root/$path/.git" ]; then
          inner S "$path" || exit 1
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

# links_in <folder>: every link below an untracked folder, NUL-terminated. A folder that
# git ignores is not entered: nothing in it counts, and one that cannot be read would
# stop find. Nor is a repository of its own: its own fingerprint holds its links, by its
# own ignore rules. Git lists both kinds with a slash at the end, the first among the
# ignored paths and the second among the untracked ones.
# "./" keeps a folder named like a find action, such as -delete, a folder name, and
# --literal-pathspecs keeps one named like a pathspec, such as :new or a*, a folder name.
links_in() {
  { git --literal-pathspecs -C "$root" -c core.quotePath=false ls-files -z --others --ignored --exclude-standard --directory -- "$1" &&
    git --literal-pathspecs -C "$root" -c core.quotePath=false ls-files -z --others --exclude-standard -- "$1"; } \
    | {
        skip=()
        while IFS= read -r -d '' i; do
          if [ "${i%/}" = "$i" ]; then continue; fi
          # -path takes a pattern, in which these four characters do not stand for
          # themselves. Each gets a backslash, one character at a time.
          rest="${i%/}" i=""
          while [ -n "$rest" ]; do
            c="${rest:0:1}" rest="${rest:1}"
            case "$c" in '\' | '*' | '?' | '[') i="$i\\$c" ;; *) i="$i$c" ;; esac
          done
          skip+=(-o -path "./$i")
        done
        cd "$root" || exit 1
        if [ "${#skip[@]}" -eq 0 ]; then
          find "./$1" -type l -print0
        else
          # Without its first -o the list reads: -path a -o -path b.
          find "./$1" \( "${skip[@]:1}" \) -prune -o -type l -print0
        fi
      } \
    | while IFS= read -r -d '' l; do printf '%s\0' "${l#./}"; done
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
          links_in "$e" \
            | not_ignored \
            | while IFS= read -r -d '' l; do link_record "$l" || exit 1; done || exit 1
        fi
      done
}

# The commit under the tree, or a word where the repository has none yet: a clean tree
# at another commit would otherwise print the same four hashes. Exit code 1 says that
# there is no commit; any other failure stops the script.
if head="$(git -C "$root" rev-parse --verify --quiet HEAD)"; then :
elif [ $? -eq 1 ]; then head="none"
else exit 1
fi
# Each hash is buffered, so a failing step exits before anything is printed.
status="$({ printf '%s\n' "$head" && git -C "$root" status --porcelain --untracked-files=all; } | git hash-object --stdin)"
# External diff and textconv drivers from the user's git config could print nothing
# for a real change; these flags make the diffs record exact content.
unstaged="$(git -C "$root" diff --no-ext-diff --no-textconv --binary --full-index | git hash-object --stdin)"
staged="$(git -C "$root" diff --cached --no-ext-diff --no-textconv --binary --full-index | git hash-object --stdin)"
# Paths are resolved from the root, so the cwd does not matter.
untracked="$({ untracked_files && untracked_links && tracked_links && tracked_files && submodules; } | LC_ALL=C sort -u | git hash-object --stdin)"

printf '%s\n' "$status" "$unstaged" "$staged" "$untracked"
