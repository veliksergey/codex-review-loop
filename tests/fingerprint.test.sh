#!/usr/bin/env bash
# Regression test for plugins/codex-review-loop/skills/codex-loop/fingerprint.sh.
# Run from anywhere: bash tests/fingerprint.test.sh
# FINGERPRINT=<script> runs the same cases against another implementation.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fp="${FINGERPRINT:-$here/../plugins/codex-review-loop/skills/codex-loop/fingerprint.sh}"
fails=0
skips=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
skip() { echo "skip - $1"; skips=$((skips + 1)); }
line() { printf '%s\n' "$1" | sed -n "${2}p"; }
g() { git -c user.name=test -c user.email=test@example.com "$@"; }
# make_symlink <target> <link>: a relative symbolic link. On Windows this needs
# Developer Mode or admin rights; it fails otherwise.
make_symlink() { MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null && [ -L "$2" ]; }
# make_link <link> <target>: a junction on Windows, a symbolic link elsewhere.
make_link() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$(cygpath -w "$1")" "$(cygpath -w "$2")" > /dev/null ;;
    *) ln -s "$2" "$1" ;;
  esac
}

# Every write below happens inside this folder, so stop before writing if it is missing.
tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT
# The last case starts this test once more with a mktemp that fails, and that run stops
# above. If it comes here it ends, so that no run ever starts a third.
if [ -n "${FINGERPRINT_TEST_NESTED:-}" ]; then
  echo "setup failed: a temporary folder was made although mktemp should fail" >&2
  exit 3
fi
# Keeps git from finding a repository above the temp folder.
export GIT_CEILING_DIRECTORIES="$tmp"

repo="$tmp/repo"
mkdir -p "$repo/sub" || abort "mkdir $repo/sub"
cd "$repo" || abort "cd $repo"
{ g init -q . &&
  g config core.autocrlf false &&
  echo tracked > tracked.txt &&
  echo ".env" > .gitignore &&
  g add tracked.txt .gitignore &&
  g commit -q -m base &&
  echo a > outside.txt &&
  echo b > sub/inside.txt &&
  echo SECRET=1 > .env; } || abort "test repository"

# Every case runs from a subfolder, where the old inline command was blind.
cd "$repo/sub" || abort "cd $repo/sub"

out="$(bash "$fp")"; rc=$?
if [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -cE '^[0-9a-f]{40}([0-9a-f]{24})?$')" -eq 4 ]; then
  pass "prints four hashes and exits 0"
else
  fail "prints four hashes and exits 0 (exit $rc, output: $out)"
fi

before="$(bash "$fp")"; echo more >> "$repo/outside.txt"; after="$(bash "$fp")"
if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "untracked file outside the current subfolder: content change detected"
else
  fail "untracked file outside the current subfolder: content change missed"
fi

before="$(bash "$fp")"; echo more >> "$repo/sub/inside.txt"; after="$(bash "$fp")"
if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "untracked file inside the current subfolder: content change detected"
else
  fail "untracked file inside the current subfolder: content change missed"
fi

before="$(bash "$fp")"; echo c > "$repo/added.txt"; after="$(bash "$fp")"
if [ "$(line "$before" 1)" != "$(line "$after" 1)" ]; then
  pass "new file: status hash changes"
else
  fail "new file: status hash unchanged"
fi

before="$(bash "$fp")"; echo edit >> "$repo/tracked.txt"; after="$(bash "$fp")"
if [ "$(line "$before" 2)" != "$(line "$after" 2)" ]; then
  pass "edit to a tracked file: unstaged diff hash changes"
else
  fail "edit to a tracked file: unstaged diff hash unchanged"
fi

before="$(bash "$fp")"; g -C "$repo" add tracked.txt; after="$(bash "$fp")"
if [ "$(line "$before" 3)" != "$(line "$after" 3)" ]; then
  pass "staging a change: staged diff hash changes"
else
  fail "staging a change: staged diff hash unchanged"
fi

before="$(bash "$fp")"; echo SECRET=2 >> "$repo/.env"; after="$(bash "$fp")"
if [ "$before" = "$after" ]; then
  pass "ignored file: not covered, as documented"
else
  fail "ignored file: hashes changed, so the documented limit is out of date"
fi

# Diff drivers from git config must not hide a content change. The file is already
# modified, so its status line stays the same and only the diff hashes can see the edit.
printf '#!/bin/sh\nexit 0\n' > "$tmp/silent-diff.sh" && chmod +x "$tmp/silent-diff.sh" || abort "silent diff driver"
g -C "$repo" config diff.external "$tmp/silent-diff.sh" || abort "diff.external"
echo first >> "$repo/tracked.txt"
before="$(bash "$fp")"; echo second >> "$repo/tracked.txt"; after="$(bash "$fp")"
if [ "$(line "$before" 2)" != "$(line "$after" 2)" ]; then
  pass "external diff driver: a second unstaged edit still changes the unstaged diff hash"
else
  fail "external diff driver: a second unstaged edit was hidden from the unstaged diff hash"
fi
g -C "$repo" add tracked.txt || abort "stage tracked.txt"
before="$(bash "$fp")"; echo third >> "$repo/tracked.txt"; g -C "$repo" add tracked.txt; after="$(bash "$fp")"
if [ "$(line "$before" 3)" != "$(line "$after" 3)" ]; then
  pass "external diff driver: a second staged edit still changes the staged diff hash"
else
  fail "external diff driver: a second staged edit was hidden from the staged diff hash"
fi
g -C "$repo" config --unset diff.external || abort "unset diff.external"

printf '#!/bin/sh\necho same\n' > "$tmp/same-text.sh" && chmod +x "$tmp/same-text.sh" || abort "textconv driver"
printf 'tracked.txt diff=same\n' > "$repo/.git/info/attributes" || abort "attributes"
g -C "$repo" config diff.same.textconv "$tmp/same-text.sh" || abort "diff.same.textconv"
echo fourth >> "$repo/tracked.txt"
before="$(bash "$fp")"; echo fifth >> "$repo/tracked.txt"; after="$(bash "$fp")"
if [ "$(line "$before" 2)" != "$(line "$after" 2)" ]; then
  pass "textconv driver: an edit still changes the unstaged diff hash"
else
  fail "textconv driver: an edit was hidden from the unstaged diff hash"
fi
rm -f "$repo/.git/info/attributes" && g -C "$repo" config --unset diff.same.textconv || abort "textconv teardown"

# An executable-bit change to an untracked file changes what git would commit.
echo 'echo run' > "$repo/run.sh" && chmod -x "$repo/run.sh" || abort "untracked script"
before="$(bash "$fp")"
chmod +x "$repo/run.sh"
if [ -x "$repo/run.sh" ]; then
  after="$(bash "$fp")"
  if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
    pass "making an untracked file executable: untracked hash changes"
  else
    fail "making an untracked file executable: untracked hash unchanged"
  fi
else
  skip "making an untracked file executable: this system has no executable bit to change"
fi
rm -f "$repo/run.sh" || abort "remove script"

# Untracked links are recorded by where they point, never followed: hash-object would
# read the target, and git on Windows lists a junction's contents as if it were a folder.
mkdir -p "$tmp/target1" "$tmp/target2" || abort "link targets"
{ echo same > "$tmp/target1/f.txt" && echo same > "$tmp/target2/f.txt"; } || abort "link target files"
make_link "$repo/lnk" "$tmp/target1" || abort "link to target1"
out="$(bash "$fp")"; rc=$?
if [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -cE '^[0-9a-f]{40}([0-9a-f]{24})?$')" -eq 4 ]; then
  pass "untracked link to a folder: prints four hashes and exits 0"
else
  fail "untracked link to a folder: exit $rc, output: $out"
fi
before="$out"
{ rm -f "$repo/lnk" && make_link "$repo/lnk" "$tmp/target2"; } || abort "link to target2"
after="$(bash "$fp")"
if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "untracked link retargeted to identical contents: untracked hash changes"
else
  fail "untracked link retargeted to identical contents: untracked hash unchanged"
fi
rm -f "$repo/lnk" || abort "remove link"
make_link "$repo/lnk" "$tmp/no-such-folder" 2>/dev/null
if [ -L "$repo/lnk" ]; then
  if bash "$fp" >/dev/null 2>&1; then
    pass "dangling untracked link: exits 0"
  else
    fail "dangling untracked link: exits non-zero"
  fi
  rm -f "$repo/lnk" || abort "remove dangling link"
else
  skip "dangling untracked link: this system cannot create one"
fi

# A link to an empty folder has no untracked file behind it, at the top level or
# inside a new untracked folder.
mkdir -p "$tmp/empty1" "$tmp/empty2" "$repo/newdir" || abort "empty targets"
make_link "$repo/lnk" "$tmp/empty1" || abort "link to empty1"
before="$(bash "$fp")"
{ rm -f "$repo/lnk" && make_link "$repo/lnk" "$tmp/empty2"; } || abort "link to empty2"
after="$(bash "$fp")"
if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "untracked link to an empty folder retargeted: untracked hash changes"
else
  fail "untracked link to an empty folder retargeted: untracked hash unchanged"
fi
rm -f "$repo/lnk" || abort "remove empty-folder link"
make_link "$repo/newdir/inner" "$tmp/empty1" || abort "inner link to empty1"
before="$(bash "$fp")"
{ rm -f "$repo/newdir/inner" && make_link "$repo/newdir/inner" "$tmp/empty2"; } || abort "inner link to empty2"
after="$(bash "$fp")"
if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "link inside a new untracked folder retargeted: untracked hash changes"
else
  fail "link inside a new untracked folder retargeted: untracked hash unchanged"
fi
rm -f "$repo/newdir/inner" && rmdir "$repo/newdir" || abort "remove inner link"

# Names and targets with spaces must not collide: with records joined by spaces,
# a -> "b c d", "a b" -> "c d", "a b c" -> e looked the same after a -> "b c e".
if (cd "$repo" && make_symlink "b c d" a && make_symlink "c d" "a b" && make_symlink e "a b c"); then
  before="$(bash "$fp")"
  (cd "$repo" && rm -f a && make_symlink "b c e" a) || abort "retarget a"
  after="$(bash "$fp")"
  if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
    pass "links with spaces in names and targets: a retarget is not hidden by a collision"
  else
    fail "links with spaces in names and targets: a retarget collided with another record"
  fi
else
  skip "links with spaces in names and targets: this system cannot create relative symlinks"
fi
(cd "$repo" && rm -f a "a b" "a b c") || abort "remove spaced links"

# An untracked folder named like a find action must stay a folder name.
mkdir -p "$repo/-delete" && echo keep > "$repo/-delete/keep.txt" || abort "folder named -delete"
out="$(bash "$fp" 2>/dev/null)"; rc=$?
if [ $rc -eq 0 ] && [ -f "$repo/-delete/keep.txt" ] && [ -f "$repo/tracked.txt" ] && [ -d "$repo/.git" ]; then
  pass "untracked folder named -delete: nothing is deleted"
else
  fail "untracked folder named -delete: exit $rc, files were deleted"
fi
[ -d "$repo/.git" ] || abort "the repository was deleted; later cases cannot run"
rm -rf -- "${repo:?}/-delete" || abort "remove -delete folder"

# A link that replaces a tracked folder: git walks through it, so its untracked files
# appear under a tracked prefix instead of as one untracked entry.
mkdir -p "$repo/vendor" && echo keep > "$repo/vendor/keep.txt" &&
  g -C "$repo" add vendor/keep.txt && g -C "$repo" commit -q -m vendor -- vendor/keep.txt || abort "tracked vendor folder"
mkdir -p "$tmp/vendor1" "$tmp/vendor2" || abort "vendor targets"
for v in vendor1 vendor2; do
  { echo keep > "$tmp/$v/keep.txt" && echo new > "$tmp/$v/new.txt"; } || abort "vendor target files"
done
{ rm -rf -- "${repo:?}/vendor" && make_link "$repo/vendor" "$tmp/vendor1"; } || abort "vendor link 1"
before="$(bash "$fp")"
{ rm -f "$repo/vendor" && make_link "$repo/vendor" "$tmp/vendor2"; } || abort "vendor link 2"
after="$(bash "$fp")"
if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "link replacing a tracked folder retargeted: untracked hash changes"
else
  fail "link replacing a tracked folder retargeted: untracked hash unchanged"
fi
{ rm -f "$repo/vendor" && g -C "$repo" checkout -q -- vendor/keep.txt; } || abort "restore vendor folder"

# The same with only tracked, unchanged files behind the link: no untracked path leads to it.
mkdir -p "$tmp/vendor4" "$tmp/vendor5" && echo keep > "$tmp/vendor4/keep.txt" && echo keep > "$tmp/vendor5/keep.txt" ||
  abort "tracked-only targets"
{ rm -rf -- "${repo:?}/vendor" && make_link "$repo/vendor" "$tmp/vendor4"; } || abort "vendor link 4"
before="$(bash "$fp")"
{ rm -f "$repo/vendor" && make_link "$repo/vendor" "$tmp/vendor5"; } || abort "vendor link 5"
after="$(bash "$fp")"
if [ "$before" != "$after" ]; then
  pass "link over tracked, unchanged files retargeted: the fingerprint changes"
else
  fail "link over tracked, unchanged files retargeted: the fingerprint is unchanged"
fi
{ rm -f "$repo/vendor" && g -C "$repo" checkout -q -- vendor/keep.txt; } || abort "restore vendor folder"

# A link inside an ignored folder of a new untracked folder is ignored: not covered.
printf 'node_modules/\n' >> "$repo/.git/info/exclude" || abort "exclude node_modules"
mkdir -p "$repo/pkg/node_modules" "$tmp/mod1" "$tmp/mod2" && echo src > "$repo/pkg/src.txt" &&
  echo one > "$tmp/mod1/i.js" && echo two > "$tmp/mod2/i.js" || abort "untracked pkg"
make_link "$repo/pkg/node_modules/dep" "$tmp/mod1" || abort "ignored link 1"
before="$(bash "$fp")"
{ rm -f "$repo/pkg/node_modules/dep" && make_link "$repo/pkg/node_modules/dep" "$tmp/mod2"; } || abort "ignored link 2"
after="$(bash "$fp")"
if [ "$before" = "$after" ]; then
  pass "link in an ignored folder inside an untracked folder: not covered, as documented"
else
  fail "link in an ignored folder inside an untracked folder: hashes changed"
fi
{ rm -f "$repo/pkg/node_modules/dep" && rm -rf -- "${repo:?}/pkg"; } || abort "remove pkg"

# A negated ignore rule (!) un-ignores: such a link to an empty folder is covered.
printf 'pkg/*/\n!pkg/keep/\n' >> "$repo/.git/info/exclude" || abort "negated exclude"
mkdir -p "$repo/pkg" && echo src > "$repo/pkg/src.txt" || abort "pkg for negation"
make_link "$repo/pkg/keep" "$tmp/empty1" || abort "negated link 1"
before="$(bash "$fp")"
{ rm -f "$repo/pkg/keep" && make_link "$repo/pkg/keep" "$tmp/empty2"; } || abort "negated link 2"
after="$(bash "$fp")"
if [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "link un-ignored by a negated rule, retargeted: untracked hash changes"
else
  fail "link un-ignored by a negated rule, retargeted: untracked hash unchanged"
fi
{ rm -f "$repo/pkg/keep" && rm -rf -- "${repo:?}/pkg"; } || abort "remove negation pkg"

# Behind a link, nothing is followed: a link inside the target of a link that replaces
# a tracked folder is not part of the fingerprint.
mkdir -p "$tmp/vendor3/new" && echo keep > "$tmp/vendor3/keep.txt" && echo f > "$tmp/vendor3/new/file.txt" ||
  abort "nested vendor target"
make_link "$tmp/vendor3/new/inner" "$tmp/empty1" || abort "inner link in target"
{ rm -rf -- "${repo:?}/vendor" && make_link "$repo/vendor" "$tmp/vendor3"; } || abort "vendor link 3"
before="$(bash "$fp")"
{ rm -f "$tmp/vendor3/new/inner" && make_link "$tmp/vendor3/new/inner" "$tmp/empty2"; } || abort "retarget inner link"
after="$(bash "$fp")"
if [ "$before" = "$after" ]; then
  pass "link inside a linked folder's target: not followed, hashes unchanged"
else
  fail "link inside a linked folder's target: hashes changed, so the link was followed"
fi
{ rm -f "$repo/vendor" "$tmp/vendor3/new/inner" && g -C "$repo" checkout -q -- vendor/keep.txt; } || abort "restore vendor folder"

# The cases below each work in a small repository of their own.
# new_repo <folder>: a repository with one commit. fp_in <folder>: its fingerprint.
new_repo() {
  mkdir -p "$1" && g -C "$1" init -q . && g -C "$1" config core.autocrlf false &&
    echo kept > "$1/kept.txt" && g -C "$1" add kept.txt && g -C "$1" commit -q -m first
}
fp_in() { (cd "$1" && bash "$fp" 2>/dev/null); }
four() { [ "$(printf '%s\n' "$1" | grep -cE '^[0-9a-f]{40}([0-9a-f]{24})?$')" -eq 4 ]; }

# An untracked file is hashed by its bytes on disk. With core.autocrlf, git's clean
# filter makes the same text of LF and CRLF, and the fingerprint must not.
{ new_repo "$tmp/eol" && g -C "$tmp/eol" config core.autocrlf true &&
  printf 'one\ntwo\n' > "$tmp/eol/new.txt"; } || abort "repository for line endings"
before="$(fp_in "$tmp/eol")"
printf 'one\r\ntwo\r\n' > "$tmp/eol/new.txt" || abort "CRLF file"
after="$(fp_in "$tmp/eol")"
if four "$before" && four "$after" && [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "untracked file changed from LF to CRLF under core.autocrlf: untracked hash changes"
else
  fail "untracked file changed from LF to CRLF under core.autocrlf: untracked hash unchanged"
fi

# The commit under the tree is part of the fingerprint: a clean tree at another commit
# has the same status, the same diffs, and the same untracked files.
{ new_repo "$tmp/commits" && echo two > "$tmp/commits/kept.txt" &&
  g -C "$tmp/commits" commit -q -am second; } || abort "repository with two commits"
before="$(fp_in "$tmp/commits")"
g -C "$tmp/commits" checkout -q HEAD~1 || abort "checkout the first commit"
after="$(fp_in "$tmp/commits")"
if four "$before" && four "$after" && [ "$before" != "$after" ]; then
  pass "clean tree at another commit: hashes change"
else
  fail "clean tree at another commit: hashes unchanged"
fi
{ mkdir -p "$tmp/unborn" && g -C "$tmp/unborn" init -q . && echo new > "$tmp/unborn/new.txt"; } ||
  abort "repository without a commit"
out="$(fp_in "$tmp/unborn")"; rc=$?
if [ $rc -eq 0 ] && four "$out"; then
  pass "repository without a commit: prints four hashes"
else
  fail "repository without a commit: exit $rc, output: $out"
fi
# Only "no commit" may stand for the commit. A git that fails to name it in another way
# fails the fingerprint.
mkdir -p "$tmp/bin-head" || abort "mkdir $tmp/bin-head"
real_git="$(command -v git)" || abort "git not found"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = --verify ] && exit 42; done\nexec "%s" "$@"\n' \
  "$real_git" > "$tmp/bin-head/git" || abort "git stand-in for the commit"
chmod +x "$tmp/bin-head/git" || abort "chmod git stand-in for the commit"
out="$(cd "$tmp/commits" && PATH="$tmp/bin-head:$PATH" bash "$fp" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then
  pass "a git that cannot name the commit: exits non-zero and prints no hash"
else
  fail "a git that cannot name the commit: exit $rc, printed $(printf '%s' "$out" | grep -c .) line(s)"
fi

# An untracked folder that is a repository of its own: git lists the folder and not its
# files. It is recorded by its own fingerprint.
{ new_repo "$tmp/outer" && new_repo "$tmp/outer/nested"; } || abort "repository inside a repository"
out="$(fp_in "$tmp/outer")"; rc=$?
if [ $rc -eq 0 ] && four "$out"; then
  pass "untracked folder that is a repository of its own: prints four hashes"
else
  fail "untracked folder that is a repository of its own: exit $rc, output: $out"
fi
echo more >> "$tmp/outer/nested/kept.txt" || abort "edit in the inner repository"
after="$(fp_in "$tmp/outer")"
if four "$after" && [ "$(line "$out" 4)" != "$(line "$after" 4)" ]; then
  pass "edit inside an untracked repository: untracked hash changes"
else
  fail "edit inside an untracked repository: untracked hash unchanged"
fi
# A step that fails in the inner repository fails the whole fingerprint.
mkdir -p "$tmp/bin-inner" || abort "mkdir $tmp/bin-inner"
real_git="$(command -v git)" || abort "git not found"
printf '#!/usr/bin/env bash\nn=0; l=0\nfor a in "$@"; do case "$a" in */nested) n=1 ;; ls-files) l=1 ;; esac; done\n[ "$n$l" = 11 ] && exit 42\nexec "%s" "$@"\n' \
  "$real_git" > "$tmp/bin-inner/git" || abort "git stand-in for the inner repository"
chmod +x "$tmp/bin-inner/git" || abort "chmod git stand-in for the inner repository"
out="$(cd "$tmp/outer" && PATH="$tmp/bin-inner:$PATH" bash "$fp" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then
  pass "a failing step inside an untracked repository: exits non-zero and prints no hash"
else
  fail "a failing step inside an untracked repository: exit $rc, printed $(printf '%s' "$out" | grep -c .) line(s)"
fi

# A submodule: git's status and diff say that it is changed, not what changed in it.
{ new_repo "$tmp/lib" && new_repo "$tmp/super"; } || abort "repositories for a submodule"
if g -C "$tmp/super" -c protocol.file.allow=always submodule add -q "$tmp/lib" lib >/dev/null 2>&1 &&
  g -C "$tmp/super" commit -q -m lib; then
  echo two > "$tmp/super/lib/kept.txt" || abort "first edit in the submodule"
  before="$(fp_in "$tmp/super")"
  echo three > "$tmp/super/lib/kept.txt" || abort "second edit in the submodule"
  after="$(fp_in "$tmp/super")"
  if four "$before" && four "$after" && [ "$before" != "$after" ]; then
    pass "submodule that is dirty already, edited again: hashes change"
  else
    fail "submodule that is dirty already, edited again: hashes unchanged"
  fi
  echo new > "$tmp/super/lib/new.txt" || abort "untracked file in the submodule"
  before="$after"; after="$(fp_in "$tmp/super")"
  if four "$after" && [ "$before" != "$after" ]; then
    pass "untracked file in a submodule: hashes change"
  else
    fail "untracked file in a submodule: hashes unchanged"
  fi
  # A clone has the submodule's folder and nothing in it.
  g clone -q "$tmp/super" "$tmp/super-clone" 2>/dev/null || abort "clone without its submodule"
  out="$(fp_in "$tmp/super-clone")"; rc=$?
  if [ $rc -eq 0 ] && four "$out"; then
    pass "submodule that is not checked out: prints four hashes"
  else
    fail "submodule that is not checked out: exit $rc, output: $out"
  fi
  # A link in the place of the submodule is recorded by where it points. What stands
  # behind it is another checkout, and nothing in that one counts.
  { g clone -q "$tmp/lib" "$tmp/lib-one" 2>/dev/null && g clone -q "$tmp/lib" "$tmp/lib-two" 2>/dev/null &&
    rm -rf -- "${tmp:?}/super/lib" && make_link "$tmp/super/lib" "$tmp/lib-one"; } ||
    abort "link in the place of the submodule"
  if g -C "$tmp/super" status --porcelain >/dev/null 2>&1; then
    before="$(fp_in "$tmp/super")"
    echo elsewhere > "$tmp/lib-one/elsewhere.txt" || abort "file behind the link"
    after="$(fp_in "$tmp/super")"
    if four "$before" && four "$after" && [ "$(line "$before" 4)" = "$(line "$after" 4)" ]; then
      pass "link in the place of a submodule: not followed, untracked hash unchanged"
    else
      fail "link in the place of a submodule: untracked hash changed, so the link was followed"
    fi
    { rm -f "$tmp/super/lib" && make_link "$tmp/super/lib" "$tmp/lib-two"; } || abort "retarget the submodule link"
    before="$after"; after="$(fp_in "$tmp/super")"
    if four "$after" && [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
      pass "link in the place of a submodule, retargeted: untracked hash changes"
    else
      fail "link in the place of a submodule, retargeted: untracked hash unchanged"
    fi
    skip "link in the place of a submodule, where git gives no status: git on this system gives one"
  else
    # Git stops on a symbolic link in the place of a submodule, as on Linux and macOS.
    # Without its status there is no fingerprint, and none must be printed.
    out="$(fp_in "$tmp/super")"; rc=$?
    if [ $rc -ne 0 ] && [ -z "$out" ]; then
      pass "link in the place of a submodule, where git gives no status: exits non-zero and prints no hash"
    else
      fail "link in the place of a submodule, where git gives no status: exit $rc, printed $(printf '%s' "$out" | grep -c .) line(s)"
    fi
    skip "link in the place of a submodule, not followed and retargeted: git on this system gives no status for such a tree"
  fi
  rm -f "$tmp/super/lib" || abort "remove the submodule link"
else
  skip "a submodule: this git could not add one from a local folder"
fi

# A folder that git ignores is not searched for links. One that cannot be read would
# stop the search, and with it the fingerprint.
# closed <folder> <on|off>: takes away the right to list a folder, or gives it back. On
# Windows that is a rule for the current user; the mode of a folder means nothing there.
closed() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
      if [ "$2" = on ]; then set -- "$1" /deny "${USERNAME:-}:(RD)"; else set -- "$1" /remove:d "${USERNAME:-}"; fi
      MSYS2_ARG_CONV_EXCL='*' icacls "$(cygpath -w "$1")" "$2" "$3" > /dev/null 2>&1 ;;
    *) if [ "$2" = on ]; then chmod 000 "$1"; else chmod 755 "$1"; fi ;;
  esac
}
{ new_repo "$tmp/closed" && printf 'cache/\n' > "$tmp/closed/.git/info/exclude" &&
  mkdir -p "$tmp/closed/new/cache" && echo x > "$tmp/closed/new/cache/x.txt" &&
  echo y > "$tmp/closed/new/y.txt"; } || abort "ignored folder inside an untracked folder"
closed "$tmp/closed/new/cache" on
if ls "$tmp/closed/new/cache" >/dev/null 2>&1; then
  skip "an unreadable ignored folder inside an untracked folder: this system lets the folder be read anyway"
else
  out="$(fp_in "$tmp/closed")"; rc=$?
  if [ $rc -eq 0 ] && four "$out"; then
    pass "an unreadable ignored folder inside an untracked folder: prints four hashes"
  else
    fail "an unreadable ignored folder inside an untracked folder: exit $rc, output: $out"
  fi
fi
# Readable again, so that the temporary folder can be removed.
closed "$tmp/closed/new/cache" off
ls "$tmp/closed/new/cache" >/dev/null 2>&1 || abort "make the folder readable again"

# The name of an untracked folder is no pathspec. Git reads ":new" as the path new with
# nothing special asked, and would then name no ignored folder below the real one.
if mkdir -p "$tmp/closed/:new/cache" 2>/dev/null && [ -d "$tmp/closed/:new/cache" ]; then
  { echo x > "$tmp/closed/:new/cache/x.txt" && echo y > "$tmp/closed/:new/y.txt"; } ||
    abort "folder named like a pathspec"
  closed "$tmp/closed/:new/cache" on
  if ls "$tmp/closed/:new/cache" >/dev/null 2>&1; then
    skip "an unreadable ignored folder in a folder named like a pathspec: this system lets the folder be read anyway"
  else
    out="$(fp_in "$tmp/closed")"; rc=$?
    if [ $rc -eq 0 ] && four "$out"; then
      pass "an unreadable ignored folder in a folder named like a pathspec: prints four hashes"
    else
      fail "an unreadable ignored folder in a folder named like a pathspec: exit $rc, output: $out"
    fi
  fi
  closed "$tmp/closed/:new/cache" off
  ls "$tmp/closed/:new/cache" >/dev/null 2>&1 || abort "make the folder named like a pathspec readable again"
else
  skip "an unreadable ignored folder in a folder named like a pathspec: this system allows no name that begins with a colon"
fi

# A repository inside this one is left to its own fingerprint, with its own ignore
# rules: the search for links of the outer one does not enter it. Here an inner
# repository ignores a folder that cannot be read, at the top and below a new folder.
{ new_repo "$tmp/both" && new_repo "$tmp/both/top" && new_repo "$tmp/both/new/deep" &&
  echo y > "$tmp/both/new/y.txt"; } || abort "repositories inside a repository"
for inner in "$tmp/both/top" "$tmp/both/new/deep"; do
  { printf 'cache/\n' > "$inner/.git/info/exclude" && mkdir -p "$inner/cache" &&
    echo x > "$inner/cache/x.txt"; } || abort "ignored folder in an inner repository"
  closed "$inner/cache" on
done
if ls "$tmp/both/top/cache" >/dev/null 2>&1 || ls "$tmp/both/new/deep/cache" >/dev/null 2>&1; then
  skip "an unreadable folder that an inner repository ignores: this system lets the folder be read anyway"
else
  out="$(fp_in "$tmp/both")"; rc=$?
  if [ $rc -eq 0 ] && four "$out"; then
    pass "an unreadable folder that an inner repository ignores: prints four hashes"
  else
    fail "an unreadable folder that an inner repository ignores: exit $rc, output: $out"
  fi
fi
for inner in "$tmp/both/top" "$tmp/both/new/deep"; do
  closed "$inner/cache" off
  ls "$inner/cache" >/dev/null 2>&1 || abort "make the folder of an inner repository readable again"
done

# The name of an ignored folder is no pattern: beside the ignored folder c[a]che, a
# link in the folder cache, which that name would match as a pattern, is still recorded.
{ new_repo "$tmp/names" && printf 'c\\[a\\]che/\n' > "$tmp/names/.git/info/exclude" &&
  mkdir -p "$tmp/names/new/c[a]che" "$tmp/names/new/cache" "$tmp/names-one" "$tmp/names-two" &&
  echo x > "$tmp/names/new/c[a]che/x.txt" && echo y > "$tmp/names/new/y.txt"; } ||
  abort "ignored folder with a pattern in its name"
{ g -C "$tmp/names" check-ignore -q 'new/c[a]che/x.txt' &&
  ! g -C "$tmp/names" check-ignore -q new/cache/any.txt; } || abort "only the folder c[a]che should be ignored"
make_link "$tmp/names/new/cache/lnk" "$tmp/names-one" || abort "link beside the ignored folder"
before="$(fp_in "$tmp/names")"
{ rm -f "$tmp/names/new/cache/lnk" && make_link "$tmp/names/new/cache/lnk" "$tmp/names-two"; } ||
  abort "retarget the link beside the ignored folder"
after="$(fp_in "$tmp/names")"
if four "$before" && four "$after" && [ "$(line "$before" 4)" != "$(line "$after" 4)" ]; then
  pass "link beside an ignored folder whose name holds pattern characters, retargeted: untracked hash changes"
else
  fail "link beside an ignored folder whose name holds pattern characters, retargeted: untracked hash unchanged"
fi
rm -f "$tmp/names/new/cache/lnk" || abort "remove the link beside the ignored folder"

# A git that fails on ls-files: the script must fail without printing any hash.
mkdir -p "$tmp/bin" || abort "mkdir $tmp/bin"
real_git="$(command -v git)" || abort "git not found"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = ls-files ] && exit 42; done\nexec "%s" "$@"\n' \
  "$real_git" > "$tmp/bin/git" || abort "git stand-in"
chmod +x "$tmp/bin/git" || abort "chmod git stand-in"
out="$(PATH="$tmp/bin:$PATH" bash "$fp" 2>/dev/null)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then
  pass "a failing step: exits non-zero and prints no hash"
else
  fail "a failing step: exit $rc, printed $(printf '%s' "$out" | grep -c .) line(s)"
fi

mkdir -p "$tmp/not-a-repo" || abort "mkdir $tmp/not-a-repo"
cd "$tmp/not-a-repo" || abort "cd $tmp/not-a-repo"
if bash "$fp" >/dev/null 2>&1; then
  fail "outside a git repository: exited 0"
else
  pass "outside a git repository: exits non-zero"
fi

# This test run from inside another repository, with no usable temp folder, must stop
# before writing: it once committed into the repository it was started from. A mktemp
# that fails stands first on the path, because not every mktemp reads TMPDIR. Exit code
# 2 is the stop at the temp folder; any other code means the run went on.
victim="$tmp/victim"
mkdir -p "$victim" "$tmp/no-mktemp" || abort "mkdir $victim"
printf '#!/bin/sh\nexit 1\n' > "$tmp/no-mktemp/mktemp" && chmod +x "$tmp/no-mktemp/mktemp" || abort "mktemp stand-in"
( cd "$victim" && g init -q . && g config core.autocrlf false &&
  echo original > .gitignore && g add .gitignore && g commit -q -m victim ) || abort "victim repository"
head_before="$(git -C "$victim" rev-parse HEAD)"
( cd "$victim" && FINGERPRINT_TEST_NESTED=1 PATH="$tmp/no-mktemp:$PATH" bash "$here/fingerprint.test.sh" ) >/dev/null 2>&1; rc=$?
head_after="$(git -C "$victim" rev-parse HEAD)"
if [ $rc -eq 2 ] && [ "$head_before" = "$head_after" ] && [ "$(cat "$victim/.gitignore")" = original ]; then
  pass "no temp folder: stops without touching the current repository"
else
  fail "no temp folder: exit $rc, the current repository was changed"
fi

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
elif [ $skips -ne 0 ]; then
  echo "all passed, $skips skipped"
else
  echo "all passed"
fi
