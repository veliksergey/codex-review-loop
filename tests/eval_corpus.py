#!/usr/bin/env python3
"""Builds and checks the evaluation corpus in tests/eval.

A case is a small git repository, its fixture, that a review can be run on. A defect
case holds one known defect, or several from one commit of this repository's history; a
control is the same fixture without it. What is wrong with a fixture is written on its
label, and a label is never part of a fixture: a reviewer must not be able to read it.

Usage:
  python tests/eval_corpus.py list
  python tests/eval_corpus.py build <case> <folder>   the fixture, outside this repository
  python tests/eval_corpus.py check [--slow]          proves every label on its fixture;
                                                      --slow, or EVAL_CORPUS_SLOW=1, also runs
                                                      the proofs by shell test on Windows
  python tests/eval_corpus.py sheet                   every label, for a person to read
  python tests/eval_corpus.py agree (--all | <case>...) [--date YYYY-MM-DD]
  python tests/eval_corpus.py status                  which cases a person agreed with

This script starts no review. Python 3.8 or newer, standard library only.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = ("defect", "control")
SOURCES = ("history", "derived", "written")
MODES = ("audit", "uncommitted")
SEVERITIES = ("P0", "P1", "P2", "P3")
TAG = re.compile(r"^(none|handoff|beyond request|criterion [1-9][0-9]*)$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
PROOFS = ("test", "python", "reading")
SYSTEMS = ("windows", "posix")
# What `git rev-parse --local-env-vars` lists: the variables that name a repository, a
# work tree, an index, or settings for one command.
REPOSITORY_VARIABLES = (
    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
    "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE",
    "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX", "GIT_SHALLOW_FILE",
    "GIT_COMMON_DIR", "GIT_NAMESPACE")
# How long a shell test may run as a proof before it counts as stuck.
TEST_SECONDS = 900
# The attributes of every file of a fixture: its bytes are kept as they are, and a
# change to it is shown as git shows any text. "-" turns an attribute off, "!" puts it
# back to what git does by itself.
OWN_ATTRIBUTES = "* -text -filter -ident -working-tree-encoding !eol !diff !merge\n"
# Who made the commits of a fixture. Nothing in a fixture names its case.
IDENTITY = {"GIT_AUTHOR_NAME": "fixture", "GIT_AUTHOR_EMAIL": "fixture@example.com",
            "GIT_COMMITTER_NAME": "fixture", "GIT_COMMITTER_EMAIL": "fixture@example.com",
            "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z"}


class Problem(Exception):
    """Something the user has to put right; the message says what."""


class Missing(Problem):
    """A commit that this clone of the repository does not hold."""


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        raise Problem(f"{path}: cannot be read as JSON: {error}")


def load(corpus):
    """Every case of the corpus, by name: its definition, its label, and its folder."""
    folder = os.path.join(corpus, "cases")
    if not os.path.isdir(folder):
        raise Problem(f"{corpus}: no cases folder")
    cases = {}
    for name in sorted(os.listdir(folder)):
        definition = os.path.join(folder, name, "case.json")
        if not os.path.isfile(definition):
            continue
        label = os.path.join(corpus, "labels", name + ".json")
        cases[name] = {"name": name, "case": read_json(definition),
                       "label": read_json(label) if os.path.isfile(label) else None}
    return cases


def inside(corpus, relative):
    """The path of a file of the corpus, which must stay inside it."""
    if not isinstance(relative, str) or not relative:
        raise Problem("a path of the corpus must be a text")
    path = os.path.realpath(os.path.join(corpus, relative))
    root = os.path.realpath(corpus)
    if not path.startswith(root + os.sep):
        raise Problem(f"{relative}: outside the corpus")
    return path


def text_field(holder, key, where, problems):
    if not isinstance(holder.get(key), str) or not holder[key].strip():
        problems.append(f"{where}: {key} must be a text")
        return False
    return True


def definition_problems(corpus, cases, name):
    """What is wrong with the definition and the label of one case, as messages."""
    entry, problems = cases[name], []
    case, label = entry["case"], entry["label"]
    if not NAME.match(name):
        problems.append(f"{name}: a case name is small letters, digits, and hyphens")
    if not isinstance(case, dict):
        return [f"{name}: the definition must be an object"]
    if case.get("kind") not in KINDS:
        problems.append(f"{name}: kind must be one of {', '.join(KINDS)}")
    if case.get("source") not in SOURCES:
        problems.append(f"{name}: source must be one of {', '.join(SOURCES)}")
    if case.get("mode") not in MODES:
        problems.append(f"{name}: mode must be one of {', '.join(MODES)}")
    fixture = case.get("fixture")
    if not isinstance(fixture, dict):
        return problems + [f"{name}: fixture must be an object"]
    from_commit = "commit" in fixture
    if from_commit == ("base" in fixture):
        problems.append(f"{name}: a fixture is made from a commit or from a base folder, one of the two")
    if from_commit:
        if not isinstance(fixture["commit"], str) or not COMMIT.match(fixture["commit"]):
            problems.append(f"{name}: commit must be a full commit id")
        subtree = fixture.get("subtree")
        if not isinstance(subtree, str) or not subtree or subtree.startswith(("/", "-")) or ".." in subtree:
            problems.append(f"{name}: subtree must name the folder of the commit that becomes the fixture")
    for key in ("edits", "change_edits"):
        edits = fixture.get(key, [])
        if not isinstance(edits, list) or not all(
                isinstance(e, dict) and all(isinstance(e.get(k), str) for k in ("file", "old", "new")) and e["old"]
                for e in edits):
            problems.append(f"{name}: every one of the {key} needs file, old, and new")
    for key in ("base", "change", "task"):
        if key in fixture:
            try:
                path = inside(corpus, fixture[key])
            except Problem as error:
                problems.append(f"{name}: {key}: {error}")
                continue
            if not (os.path.isfile(path) if key == "task" else os.path.isdir(path)):
                problems.append(f"{name}: {key}: {fixture[key]} is missing")
    if case.get("mode") == "audit":
        target = case.get("target")
        if not isinstance(target, list) or not target or not all(isinstance(t, str) and t for t in target):
            problems.append(f"{name}: an audit names its target paths")
        if "change" in fixture or "change_edits" in fixture or "task" in fixture:
            problems.append(f"{name}: an audit has no uncommitted change and no task file")
    if case.get("mode") == "uncommitted" and not (
            ("change" in fixture or fixture.get("change_edits")) and "task" in fixture):
        problems.append(f"{name}: a review of uncommitted changes needs a change and a task file")
    if case.get("kind") == "defect":
        control = case.get("control")
        other = cases[control]["case"] if isinstance(control, str) and control in cases else None
        if not isinstance(other, dict) or other.get("kind") != "control":
            problems.append(f"{name}: control must name a control case")
        elif (other.get("mode"), other.get("target")) != (case.get("mode"), case.get("target")):
            problems.append(f"{name}: a control is reviewed in the same mode, on the same target")
        if case.get("source") != "history":
            differs = case.get("differs")
            if not isinstance(differs, list) or not differs or not all(isinstance(d, str) for d in differs):
                problems.append(f"{name}: differs must name the files that set it apart from its control")
    elif "control" in case:
        problems.append(f"{name}: a control names no control")
    if label is None:
        return problems + [f"{name}: no label"]
    if not isinstance(label, dict):
        return problems + [f"{name}: the label must be an object"]
    # Defects that are known to stand in the fixture besides the labeled ones. A finding
    # about one of them is no false alarm.
    known = label.get("known_defects", [])
    if not isinstance(known, list) or not all(isinstance(k, str) and k.strip() for k in known):
        problems.append(f"{name}: known_defects must be a list of texts")
    if case.get("kind") == "control":
        if label.get("expect") != "no must-fix finding":
            problems.append(f"{name}: a control's label expects \"no must-fix finding\"")
        return problems
    if label.get("expect") != "finding":
        problems.append(f"{name}: a defect's label expects \"finding\"")
    mechanisms = label.get("mechanisms")
    if not isinstance(mechanisms, list) or not mechanisms:
        return problems + [f"{name}: a defect's label names at least one mechanism"]
    for number, item in enumerate(mechanisms, start=1):
        where = f"{name}: mechanism {number}"
        if not isinstance(item, dict):
            problems.append(f"{where}: must be an object")
            continue
        for key in ("mechanism", "trigger", "why_severity"):
            text_field(item, key, where, problems)
        if item.get("severity") not in SEVERITIES:
            problems.append(f"{where}: severity must be one of {', '.join(SEVERITIES)}")
        if not isinstance(item.get("tag"), str) or not TAG.match(item["tag"]):
            problems.append(f"{where}: tag must be none, handoff, beyond request, or criterion N")
        place = item.get("place")
        lines = place.get("lines") if isinstance(place, dict) else None
        if not (isinstance(place, dict) and text_field(place, "file", where + ": place", problems)
                and text_field(place, "holds", where + ": place", problems)):
            problems.append(f"{where}: place needs file, lines, and holds")
        elif not (isinstance(lines, list) and len(lines) == 2 and all(type(n) is int for n in lines)
                  and 1 <= lines[0] <= lines[1]):
            problems.append(f"{where}: place: lines must be a first and a last line number")
        elif place.get("in", "fixture") not in ("fixture", "task"):
            problems.append(f"{where}: place: in must be fixture or task")
        proof = item.get("proof")
        if isinstance(proof, dict) and "systems" in proof:
            named = proof["systems"]
            if not isinstance(named, list) or not named or not all(s in SYSTEMS for s in named):
                problems.append(f"{where}: proof: systems must name one or more of {', '.join(SYSTEMS)}")
        if not isinstance(proof, dict) or proof.get("kind") not in PROOFS:
            problems.append(f"{where}: proof needs a kind, one of {', '.join(PROOFS)}")
        elif proof["kind"] == "reading":
            text_field(proof, "why", where + ": proof", problems)
        elif proof["kind"] == "python":
            if text_field(proof, "file", where + ": proof", problems):
                try:
                    if not os.path.isfile(inside(corpus, proof["file"])):
                        problems.append(f"{where}: proof: {proof['file']} is missing")
                except Problem as error:
                    problems.append(f"{where}: proof: {error}")
        else:
            for key in ("file", "env", "script"):
                text_field(proof, key, where + ": proof", problems)
            named = proof.get("cases")
            if not isinstance(named, list) or not named or not all(isinstance(c, str) and c.strip() for c in named):
                problems.append(f"{where}: proof: cases must name the cases of the test")
    return problems


def own_environment(more=None):
    """The environment without the variables that send git to a set repository. A hook,
    or a command that git itself runs, hands them down, and with them git would work in
    that repository whatever folder it is started in."""
    env = {key: value for key, value in os.environ.items()
           if key not in REPOSITORY_VARIABLES and not key.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"))}
    env.update(more or {})
    return env


def git(folder, *arguments, data=None, env=None):
    """Runs git in a folder. Returns the finished process; the caller reads its code."""
    return subprocess.run(["git", "-C", folder] + list(arguments), input=data, env=own_environment(env),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def must(process, what):
    if process.returncode != 0:
        raise Problem(f"{what}: {process.stderr.decode('utf-8', 'replace').strip()}")
    return process.stdout


def export(repository, commit, subtree, folder):
    """Writes one folder of a commit of this repository into a folder, as its root."""
    # A commit counts as missing only where git can read the repository and then says,
    # without a message, that it has no such object. Anything else git reports, such as a
    # folder it refuses for its owner, is a problem and is said in git's words.
    must(git(repository, "rev-parse", "--git-dir"), f"cannot read the repository at {repository}")
    found = git(repository, "cat-file", "-e", commit)
    if found.returncode != 0 and not found.stderr.strip():
        raise Missing(f"commit {commit[:12]} is not in this clone of the repository")
    must(found, f"cannot read commit {commit[:12]} of the repository at {repository}")
    kind = must(git(repository, "cat-file", "-t", commit), f"cannot read commit {commit[:12]}").decode().strip()
    if kind != "commit":
        raise Problem(f"{commit[:12]} is a {kind} of this repository, not a commit")
    # Every file of the folder as the commit holds it, with the commit's mode. The list
    # and the contents are read from git's store, not from a checkout or an archive, so
    # that no setting and no attribute of the person's git can change a file, take its
    # executable bit, or leave it out.
    listed = must(git(repository, "ls-tree", "-r", "-z", f"{commit}:{subtree}"),
                  f"cannot list {subtree} of commit {commit[:12]}").decode("utf-8", "surrogateescape")
    entries = []
    for entry in listed.split("\0"):
        if not entry:
            continue
        details, _, path = entry.partition("\t")
        mode, kind, name = (details.split(" ") + ["", ""])[:3]
        if kind != "blob" or mode not in ("100644", "100755"):
            raise Problem(f"{path} of commit {commit[:12]} is no plain file, and a fixture holds plain files only")
        entries.append((mode, name, path))
    if not entries:
        raise Problem(f"{subtree} of commit {commit[:12]} holds no file")
    data = must(git(repository, "cat-file", "--batch", data="".join(name + "\n" for _, name, _ in entries).encode()),
                f"cannot read the files of {subtree} of commit {commit[:12]}")
    runnable, at = [], 0
    for mode, name, path in entries:
        # One object: a line with its name, its kind, and its size, then its bytes.
        end = data.find(b"\n", at)
        header = data[at:end].decode("ascii", "replace").split(" ") if end >= 0 else []
        if len(header) != 3 or header[:2] != [name, "blob"] or not header[2].isdigit():
            raise Problem(f"cannot read {path} of commit {commit[:12]}")
        size = int(header[2])
        target = below(folder, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as handle:
            handle.write(data[end + 1:end + 1 + size])
        at = end + 1 + size + 1
        try:
            os.chmod(target, 0o755 if mode == "100755" else 0o644)
        except OSError:
            pass
        if mode == "100755":
            runnable.append(path)
    # The files git holds as executable. Not every file system keeps that bit.
    return runnable


def below(folder, relative):
    """The path of a file of a fixture, which must stay inside the fixture."""
    path = os.path.join(folder, relative)
    if not within(path, folder) or os.path.normcase(os.path.realpath(path)) == os.path.normcase(os.path.realpath(folder)):
        raise Problem(f"{relative}: outside the fixture")
    return path


def edit(folder, change):
    path = below(folder, change["file"])
    try:
        with open(path, encoding="utf-8", newline="") as handle:
            text = handle.read()
    except OSError:
        raise Problem(f"edit: {change['file']} is not in the fixture")
    if text.count(change["old"]) != 1:
        raise Problem(f"edit: the old text stands {text.count(change['old'])} times in {change['file']}, not once")
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text.replace(change["old"], change["new"]))


def overlay(source, folder):
    """Copies the files of a folder of the corpus into a fixture. A link is refused: it
    could bring a file from outside that folder, a label among them, into the fixture."""
    source = os.path.realpath(source)
    for root, folders, names in os.walk(source):
        target = os.path.join(folder, os.path.relpath(root, source))
        os.makedirs(target, exist_ok=True)
        for name in folders + names:
            path = os.path.join(root, name)
            # A link of any kind leads to another path than its own: a symbolic link, and
            # a junction of Windows, which is no symbolic link and which a walk would enter.
            if os.path.islink(path) or os.path.normcase(os.path.realpath(path)) != os.path.normcase(path):
                raise Problem(f"{path}: a link cannot be part of a fixture")
        for name in names:
            shutil.copyfile(os.path.join(root, name), os.path.join(target, name))


def within(path, folder):
    path, folder = os.path.normcase(os.path.realpath(path)), os.path.normcase(os.path.realpath(folder))
    return path == folder or path.startswith(folder + os.sep)


def marked(path):
    """Whether the folder, or one above it, holds a .git: the sign of a checkout. The
    walk stops where git's own would, below a folder of GIT_CEILING_DIRECTORIES."""
    ceilings = {os.path.normcase(os.path.realpath(part))
                for part in os.environ.get("GIT_CEILING_DIRECTORIES", "").split(os.pathsep) if part}
    current = os.path.realpath(path)
    while True:
        if os.path.lexists(os.path.join(current, ".git")):
            return True
        parent = os.path.dirname(current)
        if parent == current or os.path.normcase(parent) in ceilings:
            return False
        current = parent


def checkout(path):
    """The root of the git checkout that holds a folder, or the folder itself where it
    lies in none. Where a checkout is there and git will not name it, for example one
    it refuses for its owner, that is a problem: to go on with the folder alone would
    leave the rest of the checkout unguarded."""
    if not os.path.isdir(path):
        return path
    found = git(path, "rev-parse", "--show-toplevel")
    root = found.stdout.decode("utf-8", "replace").strip()
    if found.returncode == 0 and root:
        return root
    if marked(path):
        raise Problem(f"git cannot tell which checkout holds {path}: "
                      + found.stderr.decode("utf-8", "replace").strip())
    return path


def build(corpus, repository, cases, name, folder):
    """Writes the fixture of a case: <folder>/repo, and <folder>/task.md where the case
    is reviewed against a request. Returns the two paths; the second may be None."""
    if name not in cases:
        raise Problem(f"{name}: no such case")
    # Outside the whole checkout that holds the corpus, and the one the history is read
    # from: the repository named on the command line may be a folder inside one of them,
    # or another clone.
    for place in (repository, corpus, checkout(repository), checkout(corpus)):
        if within(folder, place):
            raise Problem(f"{folder}: a fixture is built outside this repository, where no label can be read")
    if os.path.exists(folder) and (not os.path.isdir(folder) or os.listdir(folder)):
        raise Problem(f"{folder}: not an empty folder")
    work, task = os.path.join(folder, "repo"), os.path.join(folder, "task.md")
    os.makedirs(work)
    try:
        # From the root of the checkout: git reads a folder of a commit otherwise when
        # it is started in a folder below the root.
        return fill(corpus, checkout(repository), cases[name]["case"]["fixture"], work, task)
    except (Problem, OSError) as error:
        # Half a fixture is not left behind: the folder can be used again. Git makes
        # some of its files read-only, and those are made writable first.
        for root, folders, names in os.walk(work):
            for entry in folders + names:
                try:
                    os.chmod(os.path.join(root, entry), 0o700)
                except OSError:
                    pass
        shutil.rmtree(work, ignore_errors=True)
        if os.path.exists(task):
            os.remove(task)
        if isinstance(error, Problem):
            raise
        raise Problem(f"{folder}: {error}")


def fill(corpus, repository, fixture, work, task):
    """Makes the repository of a fixture in the folder work, and its task file."""
    # No template: a person's template folder can bring ignore rules and hooks with it.
    must(git(work, "init", "-q", "--template=", "."), "git init")
    must(git(work, "symbolic-ref", "HEAD", "refs/heads/main"), "git symbolic-ref")
    # Neither the line endings, nor the ignore rules, nor the hooks of the person who
    # builds it shape a fixture.
    ignore = os.path.join(work, ".git", "info", "no-ignore")
    os.makedirs(os.path.dirname(ignore), exist_ok=True)
    open(ignore, "w").close()
    for key, value in (("core.autocrlf", "false"), ("core.excludesFile", ignore), ("commit.gpgsign", "false"),
                       ("core.hooksPath", os.path.join(work, ".git", "no-hooks"))):
        must(git(work, "config", key, value), "git config")
    # Nor do that person's attributes: a filter, a line-ending rule, or a keyword of
    # theirs would change a file as it is committed, and how a change to it is shown.
    # This file goes before every other attributes file, the person's and the system's.
    with open(os.path.join(work, ".git", "info", "attributes"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(OWN_ATTRIBUTES)
    runnable = []
    if "commit" in fixture:
        runnable = export(repository, fixture["commit"], fixture["subtree"], work)
    else:
        overlay(inside(corpus, fixture["base"]), work)
    for change in fixture.get("edits", []):
        edit(work, change)
    # Every file, also one that an ignore rule names: the commit is the whole fixture.
    must(git(work, "add", "-A", "-f"), "git add")
    if runnable:
        must(git(work, "update-index", "--chmod=+x", "--", *runnable), "git update-index")
    must(git(work, "commit", "-q", "--no-verify", "-m", "fixture", env=IDENTITY), "git commit")
    left = must(git(work, "status", "--porcelain", "--ignored"), "git status").decode("utf-8", "replace").strip()
    if left:
        raise Problem("the commit of the fixture does not hold every file: " + left.split("\n")[0])
    # What follows the commit is the change under review, left uncommitted.
    if "change" in fixture:
        overlay(inside(corpus, fixture["change"]), work)
    for change in fixture.get("change_edits", []):
        edit(work, change)
    if "task" not in fixture:
        return work, None
    shutil.copyfile(inside(corpus, fixture["task"]), task)
    return work, task


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def tree(folder, skip=(".git",)):
    """Every file below a folder, by its path with forward slashes, with a hash."""
    found = {}
    for root, folders, names in os.walk(folder):
        folders[:] = sorted(f for f in folders if not (root == folder and f in skip))
        for name in names:
            path = os.path.join(root, name)
            found[os.path.relpath(path, folder).replace(os.sep, "/")] = digest(path)
    return found


def built_files(built):
    """The files of a built fixture, the task file beside it included as task.md."""
    work, task = built
    files = {"repo/" + path: value for path, value in tree(work).items()}
    if task:
        files["task.md"] = digest(task)
    return files


def place_problem(built, place):
    """Why the place of a label does not hold in a built fixture, or None."""
    work, task = built
    if place.get("in", "fixture") == "task":
        path = task
        if path is None or place["file"] != "task.md":
            return "a place in the task file names task.md, and the case needs a task file"
    else:
        try:
            path = below(work, place["file"])
        except Problem as error:
            return str(error)
    try:
        with open(path, encoding="utf-8", newline="") as handle:
            lines = handle.read().split("\n")
    except (OSError, ValueError):
        return f"{place['file']} cannot be read in the fixture"
    first, last = place["lines"]
    if last > len(lines):
        return f"{place['file']} has {len(lines)} lines, fewer than {last}"
    if place["holds"] not in "\n".join(lines[first - 1:last]):
        return f"{place['file']}:{first}-{last} does not hold the text the label quotes"
    return None


def on_windows():
    return os.name == "nt" or sys.platform in ("cygwin", "msys")


def system():
    """The kind of system, as a proof names it when not every system shows its defect."""
    return "windows" if on_windows() else "posix"


def slow_asked():
    """Whether the environment asks for the proofs that take minutes on Windows, as the
    workflow does: there every proof that a system can run is run."""
    return bool(os.environ.get("EVAL_CORPUS_SLOW"))


class Proofs:
    """Runs the proofs of labels on built fixtures, each test file once for a fixture."""

    def __init__(self, corpus, repository, slow):
        self.corpus, self.repository, self.slow = corpus, repository, slow
        self.outputs = {}

    def run(self, proof, built):
        """holds, violated, skipped, or reading, with a word on why, and the named cases
        that a shell test skipped itself while it ran others."""
        if proof["kind"] == "reading":
            return "reading", proof["why"], []
        systems = proof.get("systems")
        if systems and system() not in systems:
            return "skipped", f"only {' and '.join(systems)} can show this defect; this system is {system()}", []
        if proof["kind"] == "python":
            process = subprocess.run([sys.executable, "-B", "-I", inside(self.corpus, proof["file"]), built[0]],
                                     env=own_environment(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            said = process.stdout.decode("utf-8", "replace").strip()
            # 0 and 10, not 0 and 1: a program that stops on an error of its own exits 1,
            # and that must not read as a defect that was shown.
            if process.returncode in (0, 10):
                return ("holds" if process.returncode == 0 else "violated"), said, []
            if process.returncode == 77:
                return "skipped", said or "this system cannot run " + proof["file"], []
            raise Problem(f"proof {proof['file']} ended with exit code {process.returncode}: "
                          + process.stderr.decode("utf-8", "replace").strip()[-400:])
        if on_windows() and not self.slow:
            return "skipped", "a proof by a shell test takes minutes on Windows; check --slow runs it", []
        bash = shutil.which("bash")
        if bash is None or (on_windows() and "system32" in bash.lower()):
            return "skipped", "no bash that can run the shell tests of this repository", []
        script = below(built[0], proof["script"])
        if not os.path.isfile(script):
            raise Problem(f"proof: {proof['script']} is not in the fixture")
        test = os.path.join(self.repository, proof["file"])
        if not within(test, self.repository) or not os.path.isfile(test):
            raise Problem(f"proof: {proof['file']} is not a test of this repository")
        key = (proof["file"], proof["env"], script)
        if key not in self.outputs:
            env = own_environment({proof["env"]: script.replace(os.sep, "/")})
            try:
                process = subprocess.run([bash, test], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, timeout=TEST_SECONDS)
            except subprocess.TimeoutExpired:
                raise Problem(f"proof: {proof['file']} did not end within {TEST_SECONDS} seconds")
            self.outputs[key] = process.stdout.decode("utf-8", "replace").replace("\r", "").split("\n")
        results, missed = set(), []
        for case in proof["cases"]:
            marks = {line[:7] for line in self.outputs[key] if line[7:].startswith(case)}
            if "FAIL - " in marks:
                results.add("violated")
            elif "ok   - " in marks:
                results.add("holds")
            elif "skip - " in marks:
                missed.append(case)
            else:
                raise Problem(f"proof: {proof['file']} reported no case that starts with \"{case}\"")
        if not results:
            return "skipped", "this system cannot run the named cases of " + proof["file"], []
        if len(results) > 1:
            return "mixed", "some of the named cases failed and some passed", missed
        # A case the test skipped proves nothing, also beside one that ran.
        return results.pop(), "", missed


def check(corpus, repository, slow=False):
    """Proves the corpus. Returns the problems; what did not run, each as the place, the
    reason, and one of the words reading, skipped, and unbuilt; and a count of the proofs
    that ran."""
    # The tests that prove a label are named from the root of the checkout.
    try:
        repository = checkout(repository)
    except Problem as error:
        return [str(error)], [], 0
    cases = load(corpus)
    problems, not_run, ran = [], [], 0
    for name in cases:
        problems.extend(definition_problems(corpus, cases, name))
    # A label that belongs to no case would be read by nobody.
    labels = os.path.join(corpus, "labels")
    for file in sorted(os.listdir(labels)) if os.path.isdir(labels) else []:
        if not (file.endswith(".json") and file[:-len(".json")] in cases):
            problems.append(f"labels/{file}: no case of that name")
    if problems:
        return problems, not_run, ran
    proofs = Proofs(corpus, repository, slow)
    with tempfile.TemporaryDirectory() as scratch:
        built = {}
        for name in cases:
            try:
                built[name] = build(corpus, repository, cases, name, os.path.join(scratch, str(len(built))))
            except Missing as error:
                not_run.append((name, f"not built: {error}", "unbuilt"))
                built[name] = None
            except Problem as error:
                problems.append(f"{name}: {error}")
                built[name] = None
        for name, entry in cases.items():
            case, label = entry["case"], entry["label"]
            if case["kind"] != "defect" or built[name] is None:
                continue
            control = built.get(case["control"])
            if control is None:
                not_run.append((name, f"not compared: its control {case['control']} was not built", "unbuilt"))
            if control is not None and case["source"] != "history":
                mine, other = built_files(built[name]), built_files(control)
                apart = sorted(path for path in set(mine) | set(other) if mine.get(path) != other.get(path))
                named = {"task.md" if path == "task.md" else "repo/" + path for path in case["differs"]}
                if not apart:
                    problems.append(f"{name}: the fixture is the same as its control")
                elif set(apart) - named:
                    problems.append(f"{name}: differs from its control in files its definition does not name: "
                                    + ", ".join(sorted(set(apart) - named)))
            for number, item in enumerate(label["mechanisms"], start=1):
                where = f"{name}: mechanism {number}"
                wrong = place_problem(built[name], item["place"])
                if wrong:
                    problems.append(f"{where}: {wrong}")
                try:
                    result, detail, missed = proofs.run(item["proof"], built[name])
                    if result in ("skipped", "reading"):
                        not_run.append((where, "proved by reading only" if result == "reading" else detail, result))
                        continue
                    if result != "violated":
                        problems.append(f"{where}: the proof does not fail on the defect fixture ({result})")
                    if control is not None:
                        result, detail, more = proofs.run(item["proof"], control)
                        if result == "skipped":
                            not_run.append((where, f"on the control: {detail}", "skipped"))
                            continue
                        if result != "holds":
                            problems.append(f"{where}: the proof does not pass on the control ({result})")
                        missed = missed + [case for case in more if case not in missed]
                    # The proof ran, but not all of it: what it skipped stays unproved here.
                    for case in missed:
                        not_run.append((where, f"the case \"{case}\" of the proof did not run on this system", "skipped"))
                    ran += 1
                except Problem as error:
                    problems.append(f"{where}: {error}")
    return problems, not_run, ran


def request_of(path):
    """The request of a task file: the text under its first heading."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    start = next((n for n, line in enumerate(lines) if line.startswith("## Request")), None)
    if start is None:
        return ""
    body = []
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        body.append(line)
    return " ".join(" ".join(body).split())


def parts(entry):
    """The definition and the label of a case as objects, empty where they are none."""
    case, label = entry["case"], entry["label"]
    return (case if isinstance(case, dict) else {}), (label if isinstance(label, dict) else {})


def sheet(corpus):
    """Every label of the corpus as one text in Markdown."""
    cases = load(corpus)
    for name in cases:
        wrong = definition_problems(corpus, cases, name)
        if wrong:
            raise Problem("the sheet is for a corpus that check finds no problem in: " + wrong[0])
    out = ["# Labels of the evaluation corpus", "",
           "Read each label against its fixture. A label you agree with is recorded with",
           "`python tests/eval_corpus.py agree <case>`; `--all` records every case. No review of a",
           "case runs before its label is agreed with.", ""]
    for name, entry in cases.items():
        case, label = entry["case"], entry["label"] or {}
        fixture = case.get("fixture", {})
        out.append(f"## {name}")
        out.append("")
        out.append(f"- Kind: {case.get('kind')}" + (f", control: `{case['control']}`" if "control" in case else ""))
        made = (f"`{fixture.get('subtree')}` of commit `{fixture['commit'][:12]}` of this repository"
                if "commit" in fixture else f"the made-up project in `{fixture.get('base')}`")
        for key, what in (("edits", "edit(s) before the commit"), ("change_edits", "edit(s) left uncommitted")):
            if fixture.get(key):
                made += f"; {len(fixture[key])} {what}, in " + ", ".join(sorted({e["file"] for e in fixture[key]}))
        out.append(f"- Source: {case.get('source')}. Fixture: {made}")
        if case.get("mode") == "audit":
            out.append("- Review: an audit without a task file, of " + ", ".join(f"`{t}`" for t in case.get("target", [])))
        else:
            out.append("- Review: the uncommitted change against its task file. Request: "
                       + request_of(inside(corpus, fixture["task"])))
        if case.get("kind") == "control":
            out.append(f"- Expected: {label.get('expect')}.")
        for known in label.get("known_defects", []):
            out.append(f"- Also known to stand in this fixture, and no false alarm when found: {known}")
        if label.get("note"):
            out.append(f"- Note: {label['note']}")
        for number, item in enumerate(label.get("mechanisms", []), start=1):
            place, proof = item.get("place", {}), item.get("proof", {})
            lines = place.get("lines", ["?", "?"])
            out.append(f"- Mechanism {number}: {item.get('mechanism')}")
            out.append(f"  - Trigger: {item.get('trigger')}")
            span = str(lines[0]) if lines[0] == lines[1] else f"{lines[0]}-{lines[1]}"
            out.append(f"  - Place: `{place.get('file')}:{span}`"
                       + (" of the task file" if place.get("in") == "task" else "")
                       + f", which holds `{place.get('holds')}`")
            out.append(f"  - A correct finding: {item.get('severity')}, tag {item.get('tag')}. {item.get('why_severity')}")
            only = f" Only {' and '.join(proof['systems'])} can show it." if proof.get("systems") else ""
            if proof.get("kind") == "test":
                out.append(f"  - Proof: `{proof.get('file')}` fails on this fixture and passes on the control, in: "
                           + "; ".join(proof.get("cases", [])) + "." + only)
            elif proof.get("kind") == "python":
                out.append(f"  - Proof: `tests/eval/{proof.get('file')}` fails on this fixture and passes on the "
                           f"control.{only}")
            else:
                out.append(f"  - Proof: by reading only. {proof.get('why')}")
        out.append("")
    return "\n".join(out)


def case_hash(corpus, repository, entry):
    """One hash of everything a label was agreed with: the definition, the label, the
    files of the corpus that the two name, and the test or the program that proves it."""
    case, label = parts(entry)
    files = {}
    fixture = case.get("fixture") if isinstance(case.get("fixture"), dict) else {}
    try:
        for key in ("base", "change"):
            if key in fixture:
                folder = inside(corpus, fixture[key])
                files.update({f"{key}/{path}": value for path, value in tree(folder, skip=()).items()})
        if "task" in fixture:
            files["task"] = digest(inside(corpus, fixture["task"]))
        mechanisms = label.get("mechanisms") if isinstance(label.get("mechanisms"), list) else []
        for item in mechanisms:
            proof = item.get("proof") if isinstance(item, dict) and isinstance(item.get("proof"), dict) else {}
            if proof.get("kind") == "python":
                files["proof/" + str(proof.get("file"))] = digest(inside(corpus, proof.get("file")))
            elif proof.get("kind") == "test":
                # The whole test file: a change to it can change what its cases prove.
                test = os.path.join(repository, str(proof.get("file")))
                if not within(test, repository):
                    raise Problem(f"{proof.get('file')}: not a test of this repository")
                files["test/" + str(proof.get("file"))] = digest(test)
    except (OSError, Problem) as error:
        # A file the case names is gone or is no file of the corpus: whatever was agreed
        # with, it is not this.
        files["missing"] = str(error)
    whole = json.dumps({"case": entry["case"], "label": entry["label"], "files": files},
                       sort_keys=True, ensure_ascii=True)
    return hashlib.sha256(whole.encode("utf-8")).hexdigest()


def agreed_path(corpus):
    return os.path.join(corpus, "agreed.json")


def read_agreed(corpus):
    path = agreed_path(corpus)
    if not os.path.isfile(path):
        return {}
    whole = read_json(path)
    record = whole.get("agreed", {}) if isinstance(whole, dict) else None
    if not isinstance(record, dict):
        raise Problem(f"{path}: must be an object that holds the object agreed")
    return record


def state(corpus, repository, cases, name, record=None):
    """agreed, changed since it was agreed with, or not agreed."""
    record = read_agreed(corpus) if record is None else record
    entry = record.get(name)
    if not isinstance(entry, dict) or "hash" not in entry:
        return "not agreed"
    same = entry["hash"] == case_hash(corpus, repository, cases[name])
    return "agreed" if same else "changed since it was agreed with"


def agree(corpus, repository, names, date):
    repository = checkout(repository)
    cases = load(corpus)
    for name in names:
        if name not in cases:
            raise Problem(f"{name}: no such case")
        wrong = definition_problems(corpus, cases, name)
        if wrong:
            raise Problem("a case with a problem cannot be agreed with: " + wrong[0])
    record = read_agreed(corpus)
    for name in names:
        record[name] = {"hash": case_hash(corpus, repository, cases[name]), "date": date}
    with open(agreed_path(corpus), "w", encoding="utf-8", newline="\n") as handle:
        json.dump({"agreed": {name: record[name] for name in sorted(record)}}, handle, indent=2)
        handle.write("\n")
    return len(names)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Builds and checks the evaluation corpus. Starts no review.")
    parser.add_argument("--corpus", default=os.path.join(HERE, "eval"), help="the corpus folder")
    parser.add_argument("--repository", default=os.path.dirname(HERE), help="the repository whose history is read")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list")
    one = commands.add_parser("build")
    one.add_argument("case")
    one.add_argument("folder")
    proving = commands.add_parser("check")
    proving.add_argument("--slow", action="store_true", help="on Windows, also run the proofs by shell tests")
    commands.add_parser("sheet")
    agreeing = commands.add_parser("agree")
    agreeing.add_argument("cases", nargs="*")
    agreeing.add_argument("--all", action="store_true")
    agreeing.add_argument("--date", default=None)
    commands.add_parser("status")
    options = parser.parse_args(argv)
    try:
        # The repository may be named by a folder inside it; everything works from its root.
        corpus, repository = os.path.abspath(options.corpus), checkout(os.path.abspath(options.repository))
        if options.command == "list":
            for name, entry in load(corpus).items():
                case = parts(entry)[0]
                print(f"{name}\t{case.get('kind')}\t{case.get('source')}\t{case.get('mode')}\t{case.get('control', '')}")
        elif options.command == "build":
            work, task = build(corpus, repository, load(corpus), options.case, options.folder)
            print(f"repository: {work}")
            print(f"task file: {task or 'none'}")
        elif options.command == "check":
            problems, not_run, ran = check(corpus, repository, options.slow or slow_asked())
            cases = load(corpus)
            defects = sum(1 for entry in cases.values() if parts(entry)[0].get("kind") == "defect")
            print(f"{len(cases)} cases: {defects} defect, {len(cases) - defects} control. Proofs run: {ran}.")
            for where, why, _ in not_run:
                print(f"not run - {where}: {why}")
            for line in problems:
                print(f"problem - {line}")
            if problems:
                print(f"{len(problems)} problem(s)")
                return 1
            print("the corpus holds" + (f"; {len(not_run)} proof(s) or comparison(s) not run" if not_run else ""))
        elif options.command == "sheet":
            print(sheet(corpus))
        elif options.command == "agree":
            if options.all == bool(options.cases):
                raise Problem("name the cases, or pass --all")
            if options.date is not None:
                datetime.date.fromisoformat(options.date)
            names = sorted(load(corpus)) if options.all else options.cases
            count = agree(corpus, repository, names, options.date or datetime.date.today().isoformat())
            print(f"agreed with {count} case(s)")
        else:
            cases, record = load(corpus), read_agreed(corpus)
            states = {name: state(corpus, repository, cases, name, record) for name in cases}
            for name, value in states.items():
                print(f"{name}\t{value}")
            print(f"{sum(1 for value in states.values() if value == 'agreed')} of {len(states)} agreed")
    except (Problem, ValueError, OSError) as error:
        # Also a file that cannot be written, and a git that is not installed.
        print(f"eval-corpus: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
