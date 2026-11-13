#!/usr/bin/env bash
# Regression test for plugins/codex-review-loop/skills/codex-loop/log-dir.sh.
# Run from anywhere: bash tests/log-dir.test.sh
# LOG_DIR_SCRIPT=<script> runs the same cases against another implementation.
# Every repository and every home folder below is made in a temporary folder.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ld="${LOG_DIR_SCRIPT:-$here/../plugins/codex-review-loop/skills/codex-loop/log-dir.sh}"
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

# The home folder has a space in its path, as a real one can.
home="$tmp/home dir"
mkdir -p "$home" || abort "mkdir home"
logs="$home/.claude/codex-reviews"
# repo <folder>: makes an empty git repository there.
repo() { { mkdir -p "$1" && git -C "$1" init -q .; } || abort "git init $1"; }
# root_of <folder>: the repository's root as git reports it, which is what the marker holds.
root_of() { git -C "$1" rev-parse --show-toplevel; }
# run <folder>: runs the script from that folder with the temporary home.
run() { out="$(cd "$1" && HOME="$home" bash "$ld" 2>"$tmp/err")"; rc=$?; }
prints() {
  if [ $rc -eq 0 ] && [ "$out" = "$2" ]; then pass "$1"
  else fail "$1: exit $rc, output: $out, message: $(cat "$tmp/err")"; fi
}
# refused <name> [<text>]: non-zero exit, nothing printed, and the message holds the text.
refused() {
  if [ $rc -eq 0 ] || [ -n "$out" ]; then fail "$1: exit $rc, output: $out"
  elif [ -n "${2:-}" ] && ! grep -qF -- "$2" "$tmp/err"; then
    fail "$1: the message does not hold '$2': $(cat "$tmp/err")"
  else pass "$1: exits non-zero and prints nothing"; fi
}
# marker_is <name> <folder name> <repository>: the marker of that log folder names that repository.
marker_is() {
  if [ "$(cat "$logs/$2/repository-root.txt" 2>/dev/null)" = "$(root_of "$3")" ]; then pass "$1"
  else fail "$1: the marker holds: $(cat "$logs/$2/repository-root.txt" 2>&1)"; fi
}

repo "$tmp/one/myrepo"
run "$tmp/one/myrepo"
prints "first run: prints the log folder" "$logs/myrepo"
if [ -d "$logs/myrepo" ]; then pass "first run: the log folder exists"; else fail "first run: no log folder"; fi
marker_is "first run: the marker holds the repository's root" myrepo "$tmp/one/myrepo"

run "$tmp/one/myrepo"
prints "second run in the same repository: prints the same folder" "$logs/myrepo"
mkdir -p "$tmp/one/myrepo/sub/deeper" || abort "mkdir sub"
run "$tmp/one/myrepo/sub/deeper"
prints "a run from a subfolder: prints the same folder" "$logs/myrepo"

# A second repository whose root folder has the same name, in another place. Its task
# file and logs would mix with the first one's.
repo "$tmp/two/myrepo"
run "$tmp/two/myrepo"
refused "a second repository with the same folder name" "another repository"
if grep -qF -- "$(root_of "$tmp/one/myrepo")" "$tmp/err"; then pass "the message names the repository that owns the folder"
else fail "the message does not name the owner: $(cat "$tmp/err")"; fi
marker_is "the marker still names the first repository" myrepo "$tmp/one/myrepo"
mkdir -p "$tmp/two/myrepo/sub" || abort "mkdir sub"
run "$tmp/two/myrepo/sub"
refused "the second repository, from a subfolder"
run "$tmp/one/myrepo"
prints "the first repository still gets its folder afterwards" "$logs/myrepo"

# Another folder name is another log folder.
repo "$tmp/two/other"
run "$tmp/two/other"
prints "a repository with another name: its own folder" "$logs/other"
marker_is "a repository with another name: its own marker" other "$tmp/two/other"

# A log folder made by an earlier version has no marker. The repository that runs
# first takes it.
mkdir -p "$logs/older" || abort "mkdir older"
printf 'an earlier task\n' > "$logs/older/task.md" || abort "write task.md"
repo "$tmp/one/older"
run "$tmp/one/older"
prints "a log folder without a marker: taken by the repository that runs" "$logs/older"
marker_is "a log folder without a marker: the marker is written" older "$tmp/one/older"
if [ "$(cat "$logs/older/task.md")" = "an earlier task" ]; then pass "a log folder without a marker: its files are left alone"
else fail "a log folder without a marker: task.md changed"; fi

# An empty marker names no owner. Taking it over would be a second way to claim a
# folder, so the run stops and the user deletes the file.
repo "$tmp/one/blank"
mkdir -p "$logs/blank" || abort "mkdir blank"
: > "$logs/blank/repository-root.txt" || abort "empty marker"
run "$tmp/one/blank"
refused "an empty marker" "is empty"
if [ -f "$logs/blank/repository-root.txt" ] && [ ! -s "$logs/blank/repository-root.txt" ]; then
  pass "an empty marker: left as it is"
else fail "an empty marker: it was changed"; fi
rm -f "$logs/blank/repository-root.txt" || abort "delete the empty marker"
run "$tmp/one/blank"
prints "an empty marker, after it was deleted: the folder is claimed" "$logs/blank"

# A marker that cannot be read names no owner either. It must not be replaced. Here
# reading fails because a stand-in for cat fails.
mkdir -p "$tmp/nocat" || abort "mkdir nocat"
{ printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/nocat/cat" && chmod +x "$tmp/nocat/cat"; } || abort "failing cat"
before="$(cat "$logs/myrepo/repository-root.txt")"
out="$(cd "$tmp/one/myrepo" && HOME="$home" PATH="$tmp/nocat:$PATH" bash "$ld" 2>"$tmp/err")"; rc=$?
refused "a marker that cannot be read" "cannot read"
if [ "$(cat "$logs/myrepo/repository-root.txt")" = "$before" ]; then pass "a marker that cannot be read: left as it is"
else fail "a marker that cannot be read: it was changed"; fi
# The same with a real file that denies reading and allows writing, where the system
# has such files: another repository must not take the folder by replacing the marker.
repo "$tmp/one/locked"
run "$tmp/one/locked"
repo "$tmp/two/locked"
chmod 200 "$logs/locked/repository-root.txt" 2>/dev/null
if cat "$logs/locked/repository-root.txt" >/dev/null 2>&1; then
  skip "a marker whose permissions deny reading: this system lets the file be read anyway"
else
  run "$tmp/two/locked"
  refused "a marker whose permissions deny reading" "cannot read"
  chmod 600 "$logs/locked/repository-root.txt" || abort "restore the marker's permissions"
  marker_is "a marker whose permissions deny reading: still the first repository's" locked "$tmp/one/locked"
fi
chmod 600 "$logs/locked/repository-root.txt" 2>/dev/null

# Where the file system has no links, the marker is still made without replacing one.
# Here a stand-in for ln fails.
mkdir -p "$tmp/noln" || abort "mkdir noln"
{ printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/noln/ln" && chmod +x "$tmp/noln/ln"; } || abort "failing ln"
repo "$tmp/one/nolinks"
out="$(cd "$tmp/one/nolinks" && HOME="$home" PATH="$tmp/noln:$PATH" bash "$ld" 2>"$tmp/err")"; rc=$?
prints "no links on the file system: the folder is still claimed" "$logs/nolinks"
marker_is "no links on the file system: the marker holds the root" nolinks "$tmp/one/nolinks"
repo "$tmp/two/nolinks"
out="$(cd "$tmp/two/nolinks" && HOME="$home" PATH="$tmp/noln:$PATH" bash "$ld" 2>"$tmp/err")"; rc=$?
refused "no links on the file system: a second repository is still stopped" "another repository"
marker_is "no links on the file system: the marker is not replaced" nolinks "$tmp/one/nolinks"

# The log folder exists but nothing can be written in it. Here a stand-in for mktemp
# fails.
mkdir -p "$tmp/nomktemp" || abort "mkdir nomktemp"
{ printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/nomktemp/mktemp" && chmod +x "$tmp/nomktemp/mktemp"; } || abort "failing mktemp"
repo "$tmp/one/full"
out="$(cd "$tmp/one/full" && HOME="$home" PATH="$tmp/nomktemp:$PATH" bash "$ld" 2>"$tmp/err")"; rc=$?
refused "nothing can be written in the log folder" "cannot write in the log folder"
if [ -e "$logs/full/repository-root.txt" ]; then fail "nothing can be written: a marker was made anyway"
else pass "nothing can be written in the log folder: no marker is made"; fi
# The working file gets a name but cannot be written: the stand-in for mktemp names a
# file in a folder that does not exist. No marker may be made from it.
mkdir -p "$tmp/baddraft" || abort "mkdir baddraft"
{ printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$tmp/no-such-folder/draft" > "$tmp/baddraft/mktemp" &&
  chmod +x "$tmp/baddraft/mktemp"; } || abort "mktemp that names an unwritable file"
repo "$tmp/one/halfway"
out="$(cd "$tmp/one/halfway" && HOME="$home" PATH="$tmp/baddraft:$PATH" bash "$ld" 2>"$tmp/err")"; rc=$?
refused "the working file cannot be written" "cannot write in the log folder"
if [ -e "$logs/halfway/repository-root.txt" ]; then fail "the working file cannot be written: a marker was made anyway"
else pass "the working file cannot be written: no marker is made"; fi
# A folder that is already claimed needs no writing at all.
out="$(cd "$tmp/one/myrepo" && HOME="$home" PATH="$tmp/nomktemp:$PATH" bash "$ld" 2>"$tmp/err")"; rc=$?
prints "a claimed folder is found without writing anything" "$logs/myrepo"

# Another repository claims the folder between this run's look at it and its own claim.
# The stand-in for mktemp, which the script calls in that gap, writes the other marker
# and then does mktemp's work. The claim must fail, not replace the marker.
real_mktemp="$(command -v mktemp)" || abort "no mktemp"
late_claim() { # late_claim <stand-in folder> <folder name>
  mkdir -p "$1" || abort "mkdir $1"
  cat > "$1/mktemp" <<EOF || abort "write the stand-in"
#!/usr/bin/env bash
printf '%s\n' "/somewhere/else/$2" > "$logs/$2/repository-root.txt"
exec "$real_mktemp" "\$@"
EOF
  chmod +x "$1/mktemp" || abort "chmod the stand-in"
}
late_claim "$tmp/late" late
repo "$tmp/one/late"
out="$(cd "$tmp/one/late" && HOME="$home" PATH="$tmp/late:$PATH" bash "$ld" 2>"$tmp/err")"; rc=$?
refused "another repository claims the folder a moment earlier" "another repository"
if [ "$(cat "$logs/late/repository-root.txt")" = "/somewhere/else/late" ]; then pass "the earlier claim is not replaced"
else fail "the earlier claim was replaced: $(cat "$logs/late/repository-root.txt")"; fi
# The same where the file system has no links.
late_claim "$tmp/late-noln" late2
cp "$tmp/noln/ln" "$tmp/late-noln/ln" || abort "copy the failing ln"
repo "$tmp/one/late2"
out="$(cd "$tmp/one/late2" && HOME="$home" PATH="$tmp/late-noln:$PATH" bash "$ld" 2>"$tmp/err")"; rc=$?
refused "another repository claims the folder a moment earlier, without links" "another repository"
if [ "$(cat "$logs/late2/repository-root.txt")" = "/somewhere/else/late2" ]; then pass "without links, the earlier claim is not replaced"
else fail "without links, the earlier claim was replaced: $(cat "$logs/late2/repository-root.txt")"; fi

# Only the first line of the marker names the owner; a note below it changes nothing.
printf '%s\nkept for the review loop\n' "$(root_of "$tmp/one/myrepo")" > "$logs/myrepo/repository-root.txt" || abort "add a line"
run "$tmp/one/myrepo"
prints "a marker with a second line: the first line decides" "$logs/myrepo"
printf '%s\n' "$(root_of "$tmp/one/myrepo")" > "$logs/myrepo/repository-root.txt" || abort "restore the marker"

# Claiming leaves nothing behind but the marker, whether the claim succeeded or not.
left="$(ls -A "$logs/myrepo" "$logs/nolinks" "$logs/blank" "$logs/late" "$logs/late2" | grep -c 'repository-root\.[^t]')"
if [ "$left" = 0 ]; then pass "no working file is left beside the marker"
else fail "working files were left: $(ls -A "$logs/myrepo" "$logs/nolinks" "$logs/blank" "$logs/late" "$logs/late2")"; fi

# Several repositories with one folder name run for the first time at the same moment.
# One of them gets the folder, whichever it is, and the marker names that one.
race_bad=""
for trial in 1 2 3 4; do
  name="shared$trial"
  for i in 1 2 3 4 5 6; do repo "$tmp/race$trial/$i/$name"; done
  for i in 1 2 3 4 5 6; do
    ( cd "$tmp/race$trial/$i/$name" && HOME="$home" bash "$ld" > "$tmp/race$trial/$i.out" 2>/dev/null
      echo $? > "$tmp/race$trial/$i.rc" ) &
  done
  wait
  winners=""
  for i in 1 2 3 4 5 6; do
    if [ "$(cat "$tmp/race$trial/$i.rc" 2>/dev/null)" = 0 ]; then winners="$winners $i"; fi
  done
  # shellcheck disable=SC2086
  set -- $winners
  if [ $# -ne 1 ]; then race_bad="$race_bad trial $trial: $# of 6 got the folder;"
  elif [ "$(cat "$logs/$name/repository-root.txt")" != "$(root_of "$tmp/race$trial/$1/$name")" ]; then
    race_bad="$race_bad trial $trial: the marker does not name the one that got the folder;"
  elif [ "$(cat "$tmp/race$trial/$1.out")" != "$logs/$name" ]; then
    race_bad="$race_bad trial $trial: the one that got the folder printed something else;"
  fi
done
if [ -z "$race_bad" ]; then pass "simultaneous first runs of six same-named repositories: exactly one gets the folder, in each of four trials"
else fail "simultaneous first runs:$race_bad"; fi

# A marker saved with Windows line endings still names the same repository.
repo "$tmp/one/edited"
run "$tmp/one/edited"
printf '%s\r\n' "$(root_of "$tmp/one/edited")" > "$logs/edited/repository-root.txt" || abort "rewrite marker"
run "$tmp/one/edited"
prints "a marker with a Windows line ending: still the same repository" "$logs/edited"
# Some shells drop the carriage return themselves when they capture a command's
# output; there the case above cannot tell whether the script handles it.
probe="$(printf 'a\r\n')"
if [ "${#probe}" -ne 2 ]; then
  skip "the script's own carriage-return handling: this shell drops carriage returns itself"
fi

# A repository that was moved keeps its folder name and has a new root. The run stops
# until the user deletes the marker.
mkdir -p "$tmp/three" || abort "mkdir three"
mv "$tmp/one/edited" "$tmp/three/edited" || abort "move the repository"
run "$tmp/three/edited"
refused "a moved repository"
if grep -qF -- "repository-root.txt" "$tmp/err"; then pass "the message names the marker file to delete"
else fail "the message does not name the marker: $(cat "$tmp/err")"; fi
rm -f "$logs/edited/repository-root.txt" || abort "delete marker"
run "$tmp/three/edited"
prints "a moved repository, after the marker was deleted" "$logs/edited"
marker_is "a moved repository: the marker names the new place" edited "$tmp/three/edited"

# Not a repository: no log folder to name.
mkdir -p "$tmp/plain" || abort "mkdir plain"
run "$tmp/plain"
refused "outside a git repository" "not inside a git repository"
if [ -e "$logs/plain" ]; then fail "outside a git repository: a log folder was made"
else pass "outside a git repository: no log folder is made"; fi

# The log folder cannot be made: the home path is a file. The message says so, and
# does not blame the marker.
: > "$tmp/homefile" || abort "homefile"
out="$(cd "$tmp/one/myrepo" && HOME="$tmp/homefile" bash "$ld" 2>"$tmp/err")"; rc=$?
refused "the log folder cannot be created" "cannot create the log folder"

# A folder stands in the marker's place: it names no owner and cannot be read as a file.
repo "$tmp/one/blocked"
mkdir -p "$logs/blocked/repository-root.txt" || abort "mkdir in place of the marker"
run "$tmp/one/blocked"
refused "a folder in the marker's place" "cannot read"

# No home folder at all. Some systems give a shell a home folder when HOME is empty;
# there the case would write into a real home, so it is not run.
if [ -z "$(HOME='' bash -c 'printf %s "$HOME"')" ]; then
  out="$(cd "$tmp/one/myrepo" && HOME='' bash "$ld" 2>"$tmp/err")"; rc=$?
  refused "HOME is empty" "HOME is not set"
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
