"""Proof for the first pair from history. Usage: subfolder.py <fixture repository>
Runs the fixture's check of the working tree from a subfolder of a small repository,
before and after an edit to an untracked file outside that subfolder.
Exit 0: the result changes. Exit 10: it does not. Exit 77: this system cannot run it.

The check is skills/codex-loop/fingerprint.sh where the fixture has one. Before that
script existed, the skill gave the commands in its text; they are read from there.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

fixture = sys.argv[1]
bash = shutil.which("bash")
if bash is None or (os.name == "nt" and "system32" in bash.lower()) or shutil.which("git") is None:
    print("no bash or no git to run the check with")
    sys.exit(77)

script = os.path.join(fixture, "skills", "codex-loop", "fingerprint.sh")
if os.path.isfile(script):
    commands = [[bash, script.replace(os.sep, "/")]]
else:
    with open(os.path.join(fixture, "skills", "codex-loop", "SKILL.md"), encoding="utf-8") as handle:
        text = " ".join(handle.read().split())
    found = re.findall(r"`(git [^`]*\| git hash-object --stdin)`", text)
    if len(found) != 4:
        print(f"the skill names {len(found)} commands that end in a hash, not four")
        sys.exit(2)
    commands = [[bash, "-c", command] for command in found]


# Git works in the folder it is started in only without the variables that name another
# repository; a hook hands those down. Git itself lists them.
named = subprocess.run(["git", "rev-parse", "--local-env-vars"], stdout=subprocess.PIPE).stdout.decode().split()
environment = {key: value for key, value in os.environ.items() if key not in named}


def run(arguments, folder):
    done = subprocess.run(arguments, cwd=folder, stdin=subprocess.DEVNULL, env=environment,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if done.returncode != 0:
        print(done.stderr.decode("utf-8", "replace").strip())
        sys.exit(2)
    return done.stdout


with tempfile.TemporaryDirectory() as folder:
    work = os.path.join(folder, "work")
    os.makedirs(os.path.join(work, "sub"))
    # No template: a person's template folder can bring ignore rules that hide the file.
    run(["git", "init", "-q", "--template=", "."], work)
    # The ignore rules of the person who runs this do not hide the file below.
    open(os.path.join(folder, "no-ignore"), "w").close()
    run(["git", "config", "core.excludesFile", os.path.join(folder, "no-ignore")], work)
    outside = os.path.join(work, "new.txt")
    with open(outside, "w") as handle:
        handle.write("first\n")
    before = [run(command, os.path.join(work, "sub")) for command in commands]
    with open(outside, "a") as handle:
        handle.write("second\n")
    after = [run(command, os.path.join(work, "sub")) for command in commands]

print("an edit to an untracked file outside the current folder "
      + ("changes the result" if before != after else "is not seen"))
sys.exit(0 if before != after else 10)
