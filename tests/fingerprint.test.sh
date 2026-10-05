#!/usr/bin/env bash
# Regression test for plugins/codex-review-loop/skills/codex-loop/fingerprint.sh.
# Run from anywhere: bash tests/fingerprint.test.sh
# FINGERPRINT=<script> runs the same cases against another implementation.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fp="${FINGERPRINT:-$here/../plugins/codex-review-loop/skills/codex-loop/fingerprint.sh}"
fails=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
line() { printf '%s\n' "$1" | sed -n "${2}p"; }
g() { git -c user.name=test -c user.email=test@example.com "$@"; }

# Every write below happens inside this folder, so stop before writing if it is missing.
tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT
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
# before writing: it once committed into the repository it was started from.
victim="$tmp/victim"
mkdir -p "$victim" || abort "mkdir $victim"
( cd "$victim" && g init -q . && g config core.autocrlf false &&
  echo original > .gitignore && g add .gitignore && g commit -q -m victim ) || abort "victim repository"
head_before="$(git -C "$victim" rev-parse HEAD)"
( cd "$victim" && TMPDIR="$tmp/missing" bash "$here/fingerprint.test.sh" ) >/dev/null 2>&1; rc=$?
head_after="$(git -C "$victim" rev-parse HEAD)"
if [ $rc -ne 0 ] && [ "$head_before" = "$head_after" ] && [ "$(cat "$victim/.gitignore")" = original ]; then
  pass "no temp folder: stops without touching the current repository"
else
  fail "no temp folder: exit $rc, the current repository was changed"
fi

if [ $fails -eq 0 ]; then
  echo "all passed"
else
  echo "$fails failed"
  exit 1
fi
