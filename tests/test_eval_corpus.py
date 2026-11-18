#!/usr/bin/env python3
"""Tests for tests/eval_corpus.py. Run through: bash tests/eval-corpus.test.sh

The first class works on a small corpus that it builds in a temporary folder, beside a
small repository to take a commit from. The second proves the corpus in tests/eval.
No test starts a review. Python 3, standard library only.
"""
import contextlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import unittest.mock

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("eval_corpus", os.path.join(HERE, "eval_corpus.py"))
eval_corpus = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(eval_corpus)

REAL = os.path.join(HERE, "eval")
ROOT = os.path.dirname(HERE)
# Git looks no higher than the folder for temporary files. Should a checkout hold that
# folder, it is not the one the small corpus of these tests lies in.
os.environ["GIT_CEILING_DIRECTORIES"] = os.pathsep.join(
    part for part in (tempfile.gettempdir(), os.environ.get("GIT_CEILING_DIRECTORIES")) if part)
PROOF = """import sys
with open(sys.argv[1] + "/{file}", encoding="utf-8") as handle:
    sys.exit(0 if "{good}" in handle.read() else 10)
"""
SHELL_TEST = """#!/usr/bin/env bash
if [ "$(bash "$TOOL")" = good ]; then echo "ok   - says good"; else echo "FAIL - says good: it says something else"; fi
echo "skip - needs a clock: this system has none"
"""
TASK = "# Task: a number\n\n## Request (verbatim)\n\nReturn one.\n\n## Acceptance criteria\n\n1. `answer()` returns 1.\n"


def run_git(folder, *arguments):
    # Without the variables that name a repository: where a hook hands them down, git
    # would work in that repository, and these tests would write to it.
    done = subprocess.run(["git", "-C", folder] + list(arguments), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          env=eval_corpus.own_environment(eval_corpus.IDENTITY))
    if done.returncode != 0:
        raise AssertionError(done.stderr.decode("utf-8", "replace"))
    return done.stdout.decode("utf-8", "replace")


def make_repository(folder):
    """A repository with one commit: a folder that becomes a fixture, and a shell test.
    Returns the id of the commit."""
    write(os.path.join(folder, "plugin", "tool.sh"), "#!/bin/sh\necho good\n")
    write(os.path.join(folder, "plugin", "notes.txt"), "notes\n")
    write(os.path.join(folder, "tests", "tool.test.sh"), SHELL_TEST)
    run_git(folder, "init", "-q", "--template=", ".")
    run_git(folder, "config", "core.autocrlf", "false")
    run_git(folder, "add", "-A", "-f")
    run_git(folder, "update-index", "--chmod=+x", "plugin/tool.sh")
    run_git(folder, "commit", "-q", "-m", "first")
    return run_git(folder, "rev-parse", "HEAD").strip()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def mechanism(file, lines, holds, proof, **more):
    item = {"mechanism": "It says the wrong word.", "trigger": "Run it.", "tag": "none", "severity": "P1",
            "why_severity": "It is always wrong.", "place": {"file": file, "lines": lines, "holds": holds},
            "proof": proof}
    item.update(more)
    return item


def put(corpus, name, case=None, label=None):
    if case is not None:
        write(os.path.join(corpus, "cases", name, "case.json"), json.dumps(case))
    if label is not None:
        write(os.path.join(corpus, "labels", name + ".json"), json.dumps(label))


def small_corpus(corpus, commit):
    """Writes a corpus of two pairs: one from that commit, one written."""
    write(os.path.join(corpus, "shared", "app", "app.py"), "def answer():\n    return 1\n")
    write(os.path.join(corpus, "proofs", "says_good.py"), PROOF.format(file="tool.sh", good="echo good"))
    write(os.path.join(corpus, "proofs", "returns_one.py"), PROOF.format(file="app.py", good="return 1"))
    from_commit = {"commit": commit, "subtree": "plugin"}
    put(corpus, "d-control", {"kind": "control", "source": "derived", "mode": "audit", "target": ["tool.sh"],
                              "fixture": dict(from_commit)},
        {"expect": "no must-fix finding", "known_defects": ["An old one that is known."]})
    put(corpus, "d-broken", {"kind": "defect", "control": "d-control", "source": "derived", "mode": "audit",
                             "target": ["tool.sh"], "differs": ["tool.sh"],
                             "fixture": dict(from_commit, edits=[{"file": "tool.sh", "old": "good", "new": "bad"}])},
        {"expect": "finding", "mechanisms": [mechanism(
            "tool.sh", [2, 2], "echo bad", {"kind": "python", "file": "proofs/says_good.py"})]})
    written = {"base": "shared/app", "task": "cases/w-control/task.md"}
    write(os.path.join(corpus, "cases", "w-control", "task.md"), TASK)
    write(os.path.join(corpus, "cases", "w-broken", "task.md"), TASK + "\nAll done.\n")
    put(corpus, "w-control", {"kind": "control", "source": "written", "mode": "uncommitted",
                              "fixture": dict(written, change_edits=[
                                  {"file": "app.py", "old": "def answer", "new": "# The answer.\ndef answer"}])},
        {"expect": "no must-fix finding"})
    put(corpus, "w-broken", {"kind": "defect", "control": "w-control", "source": "written", "mode": "uncommitted",
                             "differs": ["app.py", "task.md"],
                             "fixture": {"base": "shared/app", "task": "cases/w-broken/task.md", "change_edits": [
                                 {"file": "app.py", "old": "def answer", "new": "# The answer.\ndef answer"},
                                 {"file": "app.py", "old": "return 1", "new": "return 2"}]}},
        {"expect": "finding", "mechanisms": [mechanism(
            "app.py", [3, 3], "return 2", {"kind": "python", "file": "proofs/returns_one.py"},
            tag="criterion 1")]})


class SmallCorpusTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        outer = tempfile.TemporaryDirectory()
        cls.addClassCleanup(outer.cleanup)
        cls.repository = os.path.join(outer.name, "repository")
        cls.commit = make_repository(cls.repository)

    def setUp(self):
        # Also called inside a test, for a corpus that is whole again.
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.folder = holder.name
        self.corpus = os.path.join(self.folder, "corpus")
        small_corpus(self.corpus, self.commit)

    def put(self, name, case=None, label=None):
        put(self.corpus, name, case, label)

    def change(self, name, what, edit):
        """Rewrites the definition (case) or the label of a case with a function."""
        path = (os.path.join(self.corpus, "cases", name, "case.json") if what == "case"
                else os.path.join(self.corpus, "labels", name + ".json"))
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        edit(data)
        write(path, json.dumps(data))

    def build(self, name):
        self.builds = getattr(self, "builds", 0) + 1
        target = os.path.join(self.folder, "built", str(self.builds))
        return eval_corpus.build(self.corpus, self.repository, eval_corpus.load(self.corpus), name, target)

    def check(self, slow=False):
        return eval_corpus.check(self.corpus, self.repository, slow)

    def command(self, *arguments):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = eval_corpus.main(["--corpus", self.corpus, "--repository", self.repository] + list(arguments))
        return code, out.getvalue(), err.getvalue()

    def test_a_written_case_is_built_with_its_change_left_uncommitted_and_its_task_file_beside(self):
        work, task = self.build("w-broken")
        self.assertEqual(run_git(work, "log", "--format=%s|%an|%ae").strip(), "fixture|fixture|fixture@example.com")
        self.assertEqual(run_git(work, "status", "--porcelain").strip(), "M app.py")
        with open(os.path.join(work, "app.py"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "# The answer.\ndef answer():\n    return 2\n")
        self.assertEqual(run_git(work, "show", "HEAD:app.py"), "def answer():\n    return 1\n")
        self.assertEqual(os.path.dirname(task), os.path.dirname(work))
        self.assertFalse(eval_corpus.within(task, work))
        with open(task, encoding="utf-8") as handle:
            self.assertTrue(handle.read().endswith("All done.\n"))

    def test_a_case_from_a_commit_is_built_as_one_commit_with_its_edits_in_it(self):
        work, task = self.build("d-broken")
        self.assertIsNone(task)
        self.assertEqual(run_git(work, "status", "--porcelain").strip(), "")
        self.assertEqual(run_git(work, "rev-list", "--count", "HEAD").strip(), "1")
        self.assertEqual(run_git(work, "show", "HEAD:tool.sh"), "#!/bin/sh\necho bad\n")
        self.assertEqual(sorted(run_git(work, "ls-files").split()), ["notes.txt", "tool.sh"])
        # The executable bit of the commit is kept, also where the file system has none.
        self.assertTrue(run_git(work, "ls-files", "-s", "tool.sh").startswith("100755 "))
        self.assertTrue(run_git(work, "ls-files", "-s", "notes.txt").startswith("100644 "))

    def test_a_fixture_from_a_commit_holds_every_file_of_it_whatever_the_attributes_say(self):
        # Attributes of the checkout the commit is read from: one that leaves a file out
        # of an archive, one that rewrites a file in it, and one that turns line endings.
        # A fixture is read from the commit itself and holds each file byte for byte.
        attributes = os.path.join(self.repository, ".git", "info", "attributes")
        write(attributes, "notes.txt export-ignore\ntool.sh export-subst\n* text eol=crlf\n")
        try:
            work, _ = self.build("d-control")
        finally:
            os.remove(attributes)
        self.assertEqual(sorted(run_git(work, "ls-files").split()), ["notes.txt", "tool.sh"])
        for name, content in (("notes.txt", b"notes\n"), ("tool.sh", b"#!/bin/sh\necho good\n")):
            with open(os.path.join(work, name), "rb") as handle:
                self.assertEqual(handle.read(), content, name)
        self.assertEqual(run_git(work, "status", "--porcelain", "--ignored").strip(), "")
        # A commit that holds something else than plain files is refused, not thinned out.
        linked = os.path.join(self.folder, "linked")
        make_repository(linked)
        blob = run_git(linked, "rev-parse", "HEAD:plugin/notes.txt").strip()
        run_git(linked, "update-index", "--add", "--cacheinfo", f"120000,{blob},plugin/link")
        run_git(linked, "commit", "-q", "-m", "a link")
        self.change("d-control", "case", lambda d: d["fixture"].update(commit=run_git(linked, "rev-parse", "HEAD").strip()))
        with self.assertRaises(eval_corpus.Problem) as raised:
            eval_corpus.build(self.corpus, linked, eval_corpus.load(self.corpus), "d-control",
                              os.path.join(self.folder, "with-link"))
        self.assertIn("link of commit", str(raised.exception))
        self.assertIn("is no plain file", str(raised.exception))
        # A folder that the commit does not have.
        self.setUp()
        self.change("d-control", "case", lambda d: d["fixture"].update(subtree="absent"))
        self.assertIn("cannot list absent of commit", self.check()[0][0])

    def test_a_fixture_holds_nothing_of_the_corpus(self):
        for name in ("d-broken", "w-broken"):
            work, _ = self.build(name)
            top = os.path.dirname(work)
            self.assertEqual(sorted(os.listdir(top)), ["repo", "task.md"] if name == "w-broken" else ["repo"])
            for root, _, names in os.walk(top):
                for file in names:
                    self.assertNotIn("label", file)
                    with open(os.path.join(root, file), "rb") as handle:
                        data = handle.read()
                    for secret in (name.encode(), b"It says the wrong word", b"Run it.", b"always wrong"):
                        self.assertNotIn(secret, data, os.path.join(root, file))

    def test_a_fixture_is_built_only_in_an_empty_folder_outside_the_repository_and_the_corpus(self):
        cases = eval_corpus.load(self.corpus)
        taken = os.path.join(self.folder, "taken")
        write(os.path.join(taken, "file.txt"), "here\n")
        for folder, word in ((os.path.join(self.repository, "out"), "outside this repository"),
                             (os.path.join(self.corpus, "out"), "outside this repository"),
                             (self.repository, "outside this repository"), (taken, "not an empty folder"),
                             (os.path.join(taken, "file.txt"), "not an empty folder")):
            with self.assertRaises(eval_corpus.Problem) as raised:
                eval_corpus.build(self.corpus, self.repository, cases, "d-broken", folder)
            self.assertIn(word, str(raised.exception))
        self.assertFalse(os.path.exists(os.path.join(self.repository, "out")))
        with self.assertRaises(eval_corpus.Problem) as raised:
            eval_corpus.build(self.corpus, self.repository, cases, "no-such", os.path.join(self.folder, "x"))
        self.assertIn("no such case", str(raised.exception))
        # The repository may be named by a folder inside it. The whole checkout is still
        # out of bounds, not only that folder.
        inner = os.path.join(self.repository, "plugin")
        for folder in (os.path.join(self.repository, "beside"), os.path.join(self.repository, "tests", "out")):
            with self.assertRaises(eval_corpus.Problem) as raised:
                eval_corpus.build(self.corpus, inner, cases, "d-broken", folder)
            self.assertIn("outside this repository", str(raised.exception))
            self.assertFalse(os.path.exists(folder))
        # And the checkout that holds the corpus is out of bounds whatever repository the
        # history is read from: a corpus in a checkout of its own, beside the other one.
        holder = os.path.join(self.folder, "holder")
        shutil.copytree(self.corpus, os.path.join(holder, "eval"))
        run_git(holder, "init", "-q", "--template=", ".")
        moved = eval_corpus.load(os.path.join(holder, "eval"))
        with self.assertRaises(eval_corpus.Problem) as raised:
            eval_corpus.build(os.path.join(holder, "eval"), self.repository, moved, "d-broken",
                              os.path.join(holder, "scratch"))
        self.assertIn("outside this repository", str(raised.exception))
        self.assertFalse(os.path.exists(os.path.join(holder, "scratch")))
        # A folder outside both is taken, with the repository named by its inner folder:
        # the fixture, its proofs, and an agreement are the same as from the root.
        work, _ = eval_corpus.build(self.corpus, inner, cases, "d-broken", os.path.join(self.folder, "fine"))
        self.assertEqual(run_git(work, "show", "HEAD:tool.sh"), "#!/bin/sh\necho bad\n")
        self.assertEqual(sorted(run_git(work, "ls-files").split()), ["notes.txt", "tool.sh"])
        self.assertEqual(eval_corpus.check(self.corpus, inner), ([], [], 2))
        self.assertEqual(self.command("--repository", inner, "agree", "d-broken", "--date", "2026-01-02")[0], 0)
        self.assertEqual(eval_corpus.state(self.corpus, self.repository, cases, "d-broken"), "agreed")
        code, _, err = self.command("--repository", inner, "build", "d-broken", os.path.join(self.repository, "by-command"))
        self.assertEqual((code, "outside this repository" in err), (2, True))

    def test_an_edit_whose_text_is_missing_or_stands_twice_is_refused(self):
        for old, count in (("absent", 0), ("o", 3)):
            self.change("d-broken", "case", lambda data: data["fixture"]["edits"][0].update(old=old))
            problems, _, _ = self.check()
            self.assertEqual(problems, [f"d-broken: edit: the old text stands {count} times in tool.sh, not once"])

    def test_nothing_is_written_or_read_outside_a_fixture_and_no_link_is_copied_into_one(self):
        outside = os.path.join(self.folder, "outside.txt")
        write(outside, "good\n")
        # An edit, a place, and the script of a proof that name a file above the fixture.
        self.change("d-broken", "case", lambda d: d["fixture"]["edits"][0].update(file="../../outside.txt"))
        self.assertEqual(self.check()[0], ["d-broken: ../../outside.txt: outside the fixture"])
        with open(outside, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "good\n")
        self.setUp()
        self.change("d-broken", "label", lambda d: d["mechanisms"][0]["place"].update(file="../task.md"))
        self.assertEqual(self.check()[0], ["d-broken: mechanism 1: ../task.md: outside the fixture"])
        self.setUp()
        self.change("d-broken", "label", lambda d: d["mechanisms"][0].update(proof={
            "kind": "test", "file": "tests/tool.test.sh", "env": "TOOL", "script": "../../x.sh", "cases": ["says good"]}))
        if shutil.which("bash") and not (eval_corpus.on_windows() and "system32" in shutil.which("bash").lower()):
            self.assertEqual(self.check(slow=True)[0], ["d-broken: mechanism 1: ../../x.sh: outside the fixture"])

    def test_a_link_in_the_folder_a_fixture_is_copied_from_is_refused(self):
        try:
            os.symlink(os.path.join(self.corpus, "labels", "w-broken.json"),
                       os.path.join(self.corpus, "shared", "app", "notes.json"))
        except (OSError, NotImplementedError):
            self.skipTest("a link in the base of a fixture: this system cannot create a link")
        problems = self.check()[0]
        self.assertEqual(len(problems), 2, problems)
        self.assertIn("a link cannot be part of a fixture", problems[0])

    def test_a_repository_that_the_environment_names_is_left_alone(self):
        # A hook, or a command that git runs, hands down GIT_DIR and its like. They name
        # a repository, and git works in that one whatever folder it is started in.
        other = os.path.join(self.folder, "other")
        write(os.path.join(other, "kept.txt"), "kept\n")
        run_git(other, "init", "-q", ".")
        run_git(other, "symbolic-ref", "HEAD", "refs/heads/trunk")
        run_git(other, "add", "-A")
        run_git(other, "commit", "-q", "-m", "kept")

        def facts():
            with open(os.path.join(other, ".git", "config"), encoding="utf-8") as handle:
                settings = handle.read()
            return (settings, run_git(other, "symbolic-ref", "HEAD"), run_git(other, "rev-parse", "HEAD"),
                    run_git(other, "ls-files", "-s"), run_git(other, "status", "--porcelain"),
                    sorted(os.listdir(other)))

        before = facts()
        handed = {"GIT_DIR": os.path.join(other, ".git"), "GIT_WORK_TREE": other,
                  "GIT_INDEX_FILE": os.path.join(other, ".git", "index"), "GIT_PREFIX": ""}
        saved = {key: os.environ.get(key) for key in handed}
        os.environ.update(handed)
        try:
            built = self.build("d-broken")
            result = self.check()
            # The repository these tests start from is made the same way, and so is every
            # git command they run to look at a result.
            second = os.path.join(self.folder, "second")
            commit = make_repository(second)
            seen = run_git(second, "rev-parse", "HEAD").strip()
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        self.assertEqual(facts(), before)
        self.assertEqual((commit, seen), (self.commit, self.commit))
        self.assertTrue(os.path.isdir(os.path.join(second, ".git")))
        self.assertEqual(run_git(built[0], "rev-list", "--count", "HEAD").strip(), "1")
        self.assertEqual(sorted(run_git(built[0], "ls-files").split()), ["notes.txt", "tool.sh"])
        self.assertEqual(result, ([], [], 2))
        # The variables that only choose a person's settings stay: a build reads them.
        kept = eval_corpus.own_environment({"GIT_AUTHOR_NAME": "fixture"})
        self.assertEqual(kept["GIT_AUTHOR_NAME"], "fixture")
        self.assertNotIn("GIT_DIR", eval_corpus.own_environment())

    def test_a_junction_in_the_folder_a_fixture_is_copied_from_is_refused(self):
        if os.name != "nt":
            self.skipTest("a junction in the base of a fixture: only Windows has junctions")
        # A junction is no symbolic link, and a walk of the folder would enter it.
        made = subprocess.run(["cmd", "/c", "mklink", "/J", os.path.join(self.corpus, "shared", "app", "more"),
                               os.path.join(self.corpus, "labels")], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if made.returncode != 0:
            self.skipTest("a junction in the base of a fixture: this system could not make one")
        problems = self.check()[0]
        self.assertEqual(len(problems), 2, problems)
        self.assertIn("a link cannot be part of a fixture", problems[0])

    def test_a_build_that_fails_leaves_the_folder_empty_and_usable(self):
        cases = eval_corpus.load(self.corpus)
        target = os.path.join(self.folder, "again")
        cases["d-broken"]["case"]["fixture"]["edits"][0]["old"] = "absent"
        with self.assertRaises(eval_corpus.Problem):
            eval_corpus.build(self.corpus, self.repository, cases, "d-broken", target)
        self.assertEqual(os.listdir(target), [])
        work, _ = eval_corpus.build(self.corpus, self.repository, eval_corpus.load(self.corpus), "d-broken", target)
        self.assertTrue(os.path.isfile(os.path.join(work, "tool.sh")))

    def test_the_settings_of_the_person_who_builds_a_fixture_do_not_shape_it(self):
        # A home folder whose git settings ignore every file, turn line endings, name a
        # folder of hooks with one that would stop the commit, and take the executable
        # bit away from every file that is read out of a commit.
        home = os.path.join(self.folder, "home")
        write(os.path.join(home, "ignore"), "*\n")
        write(os.path.join(home, "hooks", "post-commit"), "#!/bin/sh\necho ran > \"$HOME/hook-ran\"\n")
        settings = os.path.join(home, ".gitconfig")
        for key, value in (("core.excludesFile", os.path.join(home, "ignore")), ("core.autocrlf", "true"),
                           ("core.hooksPath", os.path.join(home, "hooks")), ("init.defaultBranch", "other"),
                           ("tar.umask", "0111")):
            subprocess.run(["git", "config", "--file", settings, key, value], check=True)
        try:
            os.chmod(os.path.join(home, "hooks", "post-commit"), 0o755)
        except OSError:
            pass
        saved = {key: os.environ.get(key) for key in ("HOME", "GIT_CONFIG_GLOBAL", "XDG_CONFIG_HOME")}
        os.environ.update(HOME=home, GIT_CONFIG_GLOBAL=settings, XDG_CONFIG_HOME=os.path.join(home, "none"))
        try:
            work, _ = self.build("w-broken")
            other, _ = self.build("d-broken")
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        self.assertEqual(run_git(work, "ls-files").split(), ["app.py"])
        self.assertEqual(run_git(work, "status", "--porcelain").strip(), "M app.py")
        self.assertEqual(run_git(work, "symbolic-ref", "--short", "HEAD").strip(), "main")
        with open(os.path.join(other, "tool.sh"), "rb") as handle:
            self.assertEqual(handle.read(), b"#!/bin/sh\necho bad\n")
        self.assertFalse(os.path.exists(os.path.join(home, "hook-ran")))
        # The modes are the commit's, and the fixture has nothing left to commit.
        self.assertTrue(run_git(other, "ls-files", "-s", "tool.sh").startswith("100755 "))
        self.assertTrue(run_git(other, "ls-files", "-s", "notes.txt").startswith("100644 "))
        self.assertEqual(run_git(other, "status", "--porcelain").strip(), "")
        if os.name != "nt":
            self.assertTrue(os.access(os.path.join(other, "tool.sh"), os.X_OK))
            self.assertFalse(os.access(os.path.join(other, "notes.txt"), os.X_OK))

    def test_the_attributes_of_the_person_who_builds_a_fixture_do_not_shape_it(self):
        # Attributes for every repository of a person: a filter that rewrites each file
        # as it is committed, a line-ending rule, a keyword, and a way to show changes
        # that shows none. A fixture's commit holds each file byte for byte all the same,
        # and the change under review shows as it is.
        home = os.path.join(self.folder, "home")
        write(os.path.join(home, "attributes"), "* filter=loud text eol=crlf ident diff=quiet\n")
        settings = os.path.join(home, ".gitconfig")
        for key, value in (("core.attributesFile", os.path.join(home, "attributes")),
                           ("filter.loud.clean", "tr a-z A-Z"), ("filter.loud.smudge", "cat"),
                           ("diff.quiet.textconv", "true")):
            subprocess.run(["git", "config", "--file", settings, key, value], check=True)
        handed = {"HOME": home, "GIT_CONFIG_GLOBAL": settings, "XDG_CONFIG_HOME": os.path.join(home, "none")}
        saved = {key: os.environ.get(key) for key in handed}
        os.environ.update(handed)
        try:
            work, _ = self.build("w-broken")
            other, _ = self.build("d-broken")
            # What a reviewer would see, with the same settings of the person.
            committed = [run_git(work, "show", "HEAD:app.py"), run_git(other, "show", "HEAD:tool.sh")]
            status = [run_git(work, "status", "--porcelain"), run_git(other, "status", "--porcelain")]
            shown = run_git(work, "diff", "--no-color")
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        self.assertEqual(committed, ["def answer():\n    return 1\n", "#!/bin/sh\necho bad\n"])
        self.assertEqual([text.strip() for text in status], ["M app.py", ""])
        for line in ("+# The answer.", "-    return 1", "+    return 2"):
            self.assertIn("\n" + line + "\n", shown)
        with open(os.path.join(other, "tool.sh"), "rb") as handle:
            self.assertEqual(handle.read(), b"#!/bin/sh\necho bad\n")
        with open(os.path.join(work, ".git", "info", "attributes"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), eval_corpus.OWN_ATTRIBUTES)

    def test_a_template_of_the_person_who_builds_a_fixture_does_not_shape_it(self):
        # A folder that git copies into every new repository: its ignore rules would leave
        # the files out of the commit, and its hook would run on it. Named once by a
        # setting, once by the variable of the environment.
        home = os.path.join(self.folder, "home")
        template = os.path.join(home, "template")
        write(os.path.join(template, "info", "exclude"), "*\n")
        write(os.path.join(template, "hooks", "post-commit"), "#!/bin/sh\necho ran > \"$HOME/hook-ran\"\n")
        try:
            os.chmod(os.path.join(template, "hooks", "post-commit"), 0o755)
        except OSError:
            pass
        settings = os.path.join(home, ".gitconfig")
        subprocess.run(["git", "config", "--file", settings, "init.templateDir", template], check=True)
        for named in ({"GIT_CONFIG_GLOBAL": settings}, {"GIT_TEMPLATE_DIR": template}):
            handed = dict(named, HOME=home, XDG_CONFIG_HOME=os.path.join(home, "none"))
            saved = {key: os.environ.get(key) for key in handed}
            os.environ.update(handed)
            try:
                work, _ = self.build("w-broken")
                other, _ = self.build("d-broken")
                again = make_repository(os.path.join(self.folder, "made-" + "-".join(named)))
            finally:
                for key, value in saved.items():
                    if value is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = value
            self.assertEqual(run_git(work, "ls-files").split(), ["app.py"], named)
            self.assertEqual(run_git(work, "status", "--porcelain", "--ignored").strip(), "M app.py", named)
            self.assertEqual(sorted(run_git(other, "ls-files").split()), ["notes.txt", "tool.sh"], named)
            self.assertEqual(again, self.commit, named)
            self.assertFalse(os.path.exists(os.path.join(home, "hook-ran")), named)
        # A fixture whose commit left a file out would be said, not passed over.
        cases = eval_corpus.load(self.corpus)
        real = eval_corpus.git

        def without_force(folder, *arguments, **more):
            return real(folder, *[argument for argument in arguments if argument != "-f"], **more)

        write(os.path.join(self.corpus, "shared", "app", ".gitignore"), "app.py\n")
        with unittest.mock.patch.object(eval_corpus, "git", without_force):
            with self.assertRaises(eval_corpus.Problem) as raised:
                eval_corpus.build(self.corpus, self.repository, cases, "w-control", os.path.join(self.folder, "left"))
        self.assertIn("the commit of the fixture does not hold every file", str(raised.exception))

    def test_a_sound_corpus_holds_and_every_proof_runs(self):
        self.assertEqual(self.check(), ([], [], 2))

    def test_check_names_what_is_wrong_with_a_definition_or_a_label(self):
        def drop(key):
            return lambda data: data.pop(key)

        def first(key, value):
            return lambda data: data["mechanisms"][0].update({key: value})

        def place(key, value):
            return lambda data: data["mechanisms"][0]["place"].update({key: value})

        wrong = [
            ("d-broken", "case", drop("control"), "control must name a control case"),
            ("d-broken", "case", lambda d: d.update(control="w-broken"), "control must name a control case"),
            ("d-broken", "case", lambda d: d.update(target=["other.sh"]), "the same mode, on the same target"),
            ("d-broken", "case", lambda d: d.update(kind="broken"), "kind must be one of"),
            ("d-broken", "case", lambda d: d.update(source="found"), "source must be one of"),
            ("d-broken", "case", lambda d: d.update(mode="branch"), "mode must be one of"),
            ("d-broken", "case", drop("differs"), "differs must name the files"),
            ("d-broken", "case", drop("target"), "an audit names its target paths"),
            ("d-broken", "case", lambda d: d["fixture"].update(commit="abc"), "commit must be a full commit id"),
            ("d-broken", "case", lambda d: d["fixture"].update(subtree="../x"), "subtree must name the folder"),
            ("d-broken", "case", lambda d: d["fixture"].update(base="shared/app"), "one of the two"),
            ("d-broken", "case", lambda d: d["fixture"].update(task="cases/w-control/task.md"),
             "an audit has no uncommitted change and no task file"),
            ("d-broken", "case", lambda d: d["fixture"].update(edits=[{"file": "tool.sh", "old": "", "new": "x"}]),
             "every one of the edits needs file, old, and new"),
            ("d-control", "case", lambda d: d.update(control="d-control"), "a control names no control"),
            ("w-broken", "case", lambda d: d["fixture"].update(base="../repository"), "outside the corpus"),
            ("w-broken", "case", lambda d: d["fixture"].update(base="shared/none"), "shared/none is missing"),
            ("w-broken", "case", lambda d: d["fixture"].pop("task"), "needs a change and a task file"),
            ("w-broken", "case", lambda d: d["fixture"].pop("change_edits"), "needs a change and a task file"),
            ("d-broken", "label", lambda d: d.update(expect="nothing"), "a defect's label expects"),
            ("d-broken", "label", lambda d: d.update(mechanisms=[]), "names at least one mechanism"),
            ("d-broken", "label", lambda d: d.update(known_defects="one"), "known_defects must be a list"),
            ("d-broken", "label", first("trigger", " "), "trigger must be a text"),
            ("d-broken", "label", first("mechanism", None), "mechanism must be a text"),
            ("d-broken", "label", first("why_severity", ""), "why_severity must be a text"),
            ("d-broken", "label", first("severity", "P5"), "severity must be one of"),
            ("d-broken", "label", first("tag", "criterion"), "tag must be none, handoff"),
            ("d-broken", "label", first("place", "tool.sh"), "place needs file, lines, and holds"),
            ("d-broken", "label", place("lines", [3, 2]), "a first and a last line number"),
            ("d-broken", "label", place("lines", [0, 1]), "a first and a last line number"),
            ("d-broken", "label", place("in", "label"), "in must be fixture or task"),
            ("d-broken", "label", first("proof", {"kind": "guess"}), "proof needs a kind"),
            ("d-broken", "label", first("proof", {"kind": "reading"}), "why must be a text"),
            ("d-broken", "label", first("proof", {"kind": "python", "file": "proofs/none.py"}), "proofs/none.py is missing"),
            ("d-broken", "label", first("proof", {"kind": "test", "file": "t.sh", "env": "T", "script": "s"}),
             "cases must name the cases of the test"),
            ("d-control", "label", lambda d: d.update(expect="finding"), "a control's label expects"),
        ]
        for name, what, edit, message in wrong:
            with self.subTest(message=message, name=name):
                self.setUp()
                self.change(name, what, edit)
                problems, _, ran = self.check()
                self.assertTrue(any(message in problem and problem.startswith(name) for problem in problems), problems)
                self.assertEqual(ran, 0)
        self.setUp()
        os.remove(os.path.join(self.corpus, "labels", "w-control.json"))
        self.assertEqual(self.check()[0], ["w-control: no label"])
        # A label without a case, a definition that is no object, and a control named by
        # something that is no name.
        self.setUp()
        self.put("gone", label={"expect": "no must-fix finding"})
        self.assertEqual(self.check()[0], ["labels/gone.json: no case of that name"])
        self.setUp()
        self.put("d-control", case=["a", "list"])
        self.assertEqual(self.check()[0], ["d-broken: control must name a control case",
                                           "d-control: the definition must be an object"])
        self.setUp()
        self.change("d-broken", "case", lambda d: d.update(control=["d-control"]))
        self.assertEqual(self.check()[0], ["d-broken: control must name a control case"])

    def test_check_proves_each_label_on_its_fixture(self):
        def place(key, value):
            return lambda data: data["mechanisms"][0]["place"].update({key: value})

        always = "import sys\nsys.exit({code})\n"
        wrong = [
            (lambda: self.change("d-broken", "label", place("lines", [2, 9])), "tool.sh has 3 lines, fewer than 9"),
            (lambda: self.change("d-broken", "label", place("lines", [1, 1])),
             "tool.sh:1-1 does not hold the text the label quotes"),
            (lambda: self.change("d-broken", "label", place("file", "none.sh")), "none.sh cannot be read in the fixture"),
            (lambda: self.change("d-broken", "label", place("in", "task")), "a place in the task file names task.md"),
            (lambda: self.change("d-broken", "case", lambda d: d.update(differs=["notes.txt"])),
             "differs from its control in files its definition does not name: repo/tool.sh"),
            (lambda: self.change("w-broken", "case", lambda d: d.update(differs=["app.py"])),
             "differs from its control in files its definition does not name: task.md"),
            (lambda: self.change("d-broken", "case", lambda d: d["fixture"].update(
                edits=[{"file": "tool.sh", "old": "good", "new": "good"}])), "the fixture is the same as its control"),
            (lambda: write(os.path.join(self.corpus, "proofs", "says_good.py"), always.format(code=0)),
             "the proof does not fail on the defect fixture (holds)"),
            (lambda: write(os.path.join(self.corpus, "proofs", "says_good.py"), always.format(code=10)),
             "the proof does not pass on the control (violated)"),
            (lambda: write(os.path.join(self.corpus, "proofs", "says_good.py"), always.format(code=5)),
             "says_good.py ended with exit code 5"),
            # A program that stops on an error of its own exits 1. That is no defect shown.
            (lambda: write(os.path.join(self.corpus, "proofs", "says_good.py"), "import no_such_module\n"),
             "says_good.py ended with exit code 1"),
        ]
        for breaks, message in wrong:
            with self.subTest(message=message):
                self.setUp()
                breaks()
                problems = self.check()[0]
                # A fixture that equals its control also fails its place and its proof.
                self.assertEqual(len(problems), 3 if "the same as its control" in message else 1, problems)
                self.assertIn(message, problems[0])
        # A place in the task file is read from the file beside the repository.
        self.setUp()
        self.change("w-broken", "label", lambda d: d["mechanisms"][0].update(
            place={"file": "task.md", "lines": [11, 11], "holds": "All done.", "in": "task"}))
        self.assertEqual(self.check()[0], [])

    def test_a_commit_that_this_clone_does_not_hold_is_reported_and_is_no_problem(self):
        for name in ("d-broken", "d-control"):
            self.change(name, "case", lambda d: d["fixture"].update(commit="0" * 40))
        problems, not_run, ran = self.check()
        self.assertEqual(problems, [])
        self.assertEqual([(where, kind) for where, _, kind in not_run], [("d-broken", "unbuilt"), ("d-control", "unbuilt")])
        self.assertIn("is not in this clone", not_run[0][1])
        self.assertEqual(ran, 1)
        # Only the control is missing: the defect is built, and not compared with it.
        self.setUp()
        self.change("d-control", "case", lambda d: d["fixture"].update(commit="0" * 40))
        problems, not_run, ran = self.check()
        self.assertEqual(problems, [])
        self.assertIn(("d-broken", "not compared: its control d-control was not built", "unbuilt"), not_run)

    def test_a_repository_that_git_cannot_read_is_a_problem_and_not_a_commit_that_is_missing(self):
        # A folder that is no checkout at all: git stops with a message when a commit is
        # asked for. That must not read as missing history.
        plain = os.path.join(self.folder, "plain")
        os.makedirs(plain)
        problems, not_run, ran = eval_corpus.check(self.corpus, plain)
        self.assertEqual([where for where, _, kind in not_run if kind == "unbuilt"], [])
        self.assertEqual([problem.split(":")[0] for problem in problems], ["d-broken", "d-control"])
        for problem in problems:
            self.assertIn("cannot read the repository at", problem)
            # What git said is kept.
            self.assertGreater(len(problem.split(plain, 1)[1].strip(": ")), 5, problem)
        self.assertEqual(ran, 1)
        self.assertEqual(self.command("--repository", plain, "check")[0], 1)
        # A checkout that git will not name: its .git leads nowhere here, as git also
        # stops for a checkout it refuses for its owner. Nothing goes on from the folder
        # alone, because the rest of that checkout would then be unguarded.
        broken = os.path.join(self.folder, "broken")
        write(os.path.join(broken, ".git"), "gitdir: /no/such/place\n")
        os.makedirs(os.path.join(broken, "inner"))
        self.assertTrue(eval_corpus.marked(os.path.join(broken, "inner")))
        self.assertFalse(eval_corpus.marked(plain))
        problems, not_run, ran = eval_corpus.check(self.corpus, broken)
        self.assertEqual((len(problems), not_run, ran), (1, [], 0))
        self.assertIn("git cannot tell which checkout holds", problems[0])
        self.assertGreater(len(problems[0].split(broken, 1)[1].strip(": ")), 5, problems[0])
        code, _, err = self.command("--repository", broken, "check")
        self.assertEqual((code, "git cannot tell which checkout holds" in err), (2, True))
        # A written fixture reads no commit, so only this stops a build inside it: with
        # the repository named by a folder of that checkout, and with the corpus in it.
        cases = eval_corpus.load(self.corpus)
        shutil.copytree(self.corpus, os.path.join(broken, "eval"))
        for corpus, repository in ((self.corpus, os.path.join(broken, "inner")),
                                   (os.path.join(broken, "eval"), self.repository)):
            with self.assertRaises(eval_corpus.Problem) as raised:
                eval_corpus.build(corpus, repository, cases, "w-control", os.path.join(broken, "out"))
            self.assertIn("git cannot tell which checkout holds", str(raised.exception))
            self.assertFalse(os.path.exists(os.path.join(broken, "out")))
        # An object that is there and is no commit is said to be that.
        self.setUp()
        tree = run_git(self.repository, "rev-parse", "HEAD^{tree}").strip()
        self.change("d-broken", "case", lambda d: d["fixture"].update(commit=tree))
        self.assertEqual(self.check()[0], [f"d-broken: {tree[:12]} is a tree of this repository, not a commit"])

    def test_a_proof_can_say_that_this_system_cannot_run_it_and_a_proof_by_reading_is_not_run(self):
        write(os.path.join(self.corpus, "proofs", "says_good.py"), "import sys\nprint('no shell here')\nsys.exit(77)\n")
        self.assertEqual(self.check(), ([], [("d-broken: mechanism 1", "no shell here", "skipped")], 1))
        self.change("d-broken", "label", lambda d: d["mechanisms"][0].update(
            proof={"kind": "reading", "why": "Running it would do harm."}))
        self.assertEqual(self.check(), ([], [("d-broken: mechanism 1", "proved by reading only", "reading")], 1))

    def test_a_proof_by_a_shell_test_reads_the_named_cases_of_its_output(self):
        if shutil.which("bash") is None or (eval_corpus.on_windows() and "system32" in shutil.which("bash").lower()):
            self.skipTest("a proof by a shell test: no bash that can run the shell tests")

        def proof(*cases):
            return lambda d: d["mechanisms"][0].update(proof={
                "kind": "test", "file": "tests/tool.test.sh", "env": "TOOL", "script": "tool.sh", "cases": list(cases)})

        self.change("d-broken", "label", proof("says good"))
        self.assertEqual(self.check(slow=True), ([], [], 2))
        if eval_corpus.on_windows():
            _, not_run, ran = self.check()
            self.assertEqual((not_run[0][2], ran), ("skipped", 1))
            self.assertIn("check --slow runs it", not_run[0][1])
        # A case that the test skipped proves nothing; a case it does not report is a problem.
        self.change("d-broken", "label", proof("needs a clock"))
        problems, not_run, ran = self.check(slow=True)
        self.assertEqual((problems, [kind for _, _, kind in not_run], ran), ([], ["skipped"], 1))
        self.change("d-broken", "label", proof("no such case"))
        self.assertIn('reported no case that starts with "no such case"', self.check(slow=True)[0][0])
        self.change("d-broken", "label", lambda d: d["mechanisms"][0]["proof"].update(cases=["says good"], script="x.sh"))
        self.assertIn("x.sh is not in the fixture", self.check(slow=True)[0][0])
        # A case the test skipped beside one that ran: the proof counts, and the skipped
        # case is named as not run.
        self.change("d-broken", "label", proof("says good", "needs a clock"))
        self.assertEqual(self.check(slow=True), ([], [(
            "d-broken: mechanism 1", 'the case "needs a clock" of the proof did not run on this system', "skipped")], 2))

    def test_a_proof_that_only_one_kind_of_system_can_run_is_skipped_on_the_other(self):
        here = eval_corpus.system()
        other = "posix" if here == "windows" else "windows"
        self.assertIn(here, eval_corpus.SYSTEMS)
        self.change("d-broken", "label", lambda d: d["mechanisms"][0]["proof"].update(systems=[other]))
        self.assertEqual(self.check(), ([], [(
            "d-broken: mechanism 1", f"only {other} can show this defect; this system is {here}", "skipped")], 1))
        self.assertIn(f"Only {other} can show it.", eval_corpus.sheet(self.corpus))
        self.change("d-broken", "label", lambda d: d["mechanisms"][0]["proof"].update(systems=[here]))
        self.assertEqual(self.check(), ([], [], 2))
        for wrong in ([], "windows", ["windows", "amiga"]):
            self.change("d-broken", "label", lambda d: d["mechanisms"][0]["proof"].update(systems=wrong))
            self.assertEqual(self.check()[0], [
                "d-broken: mechanism 1: proof: systems must name one or more of windows, posix"])
        # The environment can ask for the slow proofs, as the workflow does.
        saved = os.environ.pop("EVAL_CORPUS_SLOW", None)
        try:
            self.assertFalse(eval_corpus.slow_asked())
            os.environ["EVAL_CORPUS_SLOW"] = "1"
            self.assertTrue(eval_corpus.slow_asked())
            if shutil.which("bash") and not (eval_corpus.on_windows() and "system32" in shutil.which("bash").lower()):
                self.change("d-broken", "label", lambda d: d["mechanisms"][0].update(proof={
                    "kind": "test", "file": "tests/tool.test.sh", "env": "TOOL", "script": "tool.sh",
                    "cases": ["says good"], "systems": [here]}))
                code, out, _ = self.command("check")
                self.assertEqual((code, out.split("\n")[0]), (0, "4 cases: 2 defect, 2 control. Proofs run: 2."))
        finally:
            os.environ.pop("EVAL_CORPUS_SLOW", None)
            if saved is not None:
                os.environ["EVAL_CORPUS_SLOW"] = saved

    def test_the_sheet_holds_every_part_of_every_label(self):
        self.change("d-broken", "label", lambda d: d.update(note="Read it twice."))
        text = eval_corpus.sheet(self.corpus)
        for part in ("## d-broken", "## d-control", "## w-broken", "## w-control", "Kind: defect, control: `d-control`",
                     f"`plugin` of commit `{self.commit[:12]}`", "1 edit(s) before the commit, in tool.sh",
                     "an audit without a task file, of `tool.sh`", "Mechanism 1: It says the wrong word.",
                     "Trigger: Run it.", "Place: `tool.sh:2`, which holds `echo bad`",
                     "A correct finding: P1, tag none. It is always wrong.",
                     "`tests/eval/proofs/says_good.py` fails on this fixture and passes on the control",
                     "Expected: no must-fix finding.", "no false alarm when found: An old one that is known.",
                     "Note: Read it twice.", "the made-up project in `shared/app`",
                     "2 edit(s) left uncommitted, in app.py", "Request: Return one.", "tag criterion 1",
                     "python tests/eval_corpus.py agree"):
            self.assertIn(part, text)
        self.change("d-broken", "label", lambda d: d["mechanisms"][0].update(
            proof={"kind": "reading", "why": "Running it would do harm."}))
        self.assertIn("Proof: by reading only. Running it would do harm.", eval_corpus.sheet(self.corpus))

    def test_an_agreement_holds_for_the_case_and_the_label_as_they_were(self):
        cases = eval_corpus.load(self.corpus)
        self.assertEqual(eval_corpus.state(self.corpus, self.repository, cases, "w-broken"), "not agreed")
        self.assertEqual(eval_corpus.agree(self.corpus, self.repository, ["w-broken", "d-broken"], "2026-01-02"), 2)
        with open(os.path.join(self.corpus, "agreed.json"), encoding="utf-8") as handle:
            record = json.load(handle)["agreed"]
        self.assertEqual(list(record), ["d-broken", "w-broken"])
        self.assertEqual(record["w-broken"]["date"], "2026-01-02")
        self.assertEqual(len(record["w-broken"]["hash"]), 64)

        def states():
            loaded = eval_corpus.load(self.corpus)
            return [eval_corpus.state(self.corpus, self.repository, loaded, name) for name in ("d-broken", "d-control", "w-broken")]

        self.assertEqual(states(), ["agreed", "not agreed", "agreed"])
        changed = "changed since it was agreed with"
        # Each of these is part of what was agreed with: the label, the definition, the
        # task file, the base of the fixture, and the file of the proof.
        changes = [
            lambda: self.change("w-broken", "label", lambda d: d["mechanisms"][0].update(severity="P2")),
            lambda: self.change("w-broken", "case", lambda d: d.update(differs=["app.py", "task.md", "x"])),
            lambda: write(os.path.join(self.corpus, "cases", "w-broken", "task.md"), TASK + "\nNearly done.\n"),
            lambda: write(os.path.join(self.corpus, "shared", "app", "app.py"), "def answer():\n    return 1  # one\n"),
            lambda: write(os.path.join(self.corpus, "proofs", "returns_one.py"), "import sys\nsys.exit(1)\n"),
        ]
        for number, change in enumerate(changes):
            with self.subTest(change=number):
                self.setUp()
                eval_corpus.agree(self.corpus, self.repository, ["w-broken", "d-broken"], "2026-01-02")
                change()
                self.assertEqual(states(), ["agreed", "not agreed", changed])
        # Agreeing again takes the case as it is now, and keeps the other agreements.
        eval_corpus.agree(self.corpus, self.repository, ["w-broken"], "2026-01-03")
        self.assertEqual(states(), ["agreed", "not agreed", "agreed"])
        # A shell test that proves a label is part of what was agreed with, like a program.
        self.setUp()
        self.change("d-broken", "label", lambda d: d["mechanisms"][0].update(proof={
            "kind": "test", "file": "tests/tool.test.sh", "env": "TOOL", "script": "tool.sh", "cases": ["says good"]}))
        eval_corpus.agree(self.corpus, self.repository, ["w-broken", "d-broken"], "2026-01-02")
        self.assertEqual(states(), ["agreed", "not agreed", "agreed"])
        test = os.path.join(self.repository, "tests", "tool.test.sh")
        try:
            write(test, SHELL_TEST + "echo 'ok   - one more case'\n")
            self.assertEqual(states(), [changed, "not agreed", "agreed"])
            os.remove(test)
            self.assertEqual(states(), [changed, "not agreed", "agreed"])
        finally:
            write(test, SHELL_TEST)
        self.assertEqual(states(), ["agreed", "not agreed", "agreed"])
        with self.assertRaises(eval_corpus.Problem):
            eval_corpus.agree(self.corpus, self.repository, ["no-such"], "2026-01-03")
        # A case with a problem cannot be agreed with.
        self.change("d-control", "label", lambda d: d.update(expect="finding"))
        with self.assertRaises(eval_corpus.Problem) as raised:
            eval_corpus.agree(self.corpus, self.repository, ["d-control"], "2026-01-03")
        self.assertIn("a case with a problem cannot be agreed with", str(raised.exception))

    def test_the_commands(self):
        code, out, _ = self.command("list")
        self.assertEqual((code, out.split("\n")[0]), (0, "d-broken\tdefect\tderived\taudit\td-control"))
        code, out, _ = self.command("check")
        self.assertEqual(code, 0)
        self.assertEqual(out.strip().split("\n"), ["4 cases: 2 defect, 2 control. Proofs run: 2.", "the corpus holds"])
        target = os.path.join(self.folder, "from-command")
        code, out, _ = self.command("build", "w-broken", target)
        self.assertEqual(code, 0)
        self.assertEqual(out.strip().split("\n"), [f"repository: {os.path.join(target, 'repo')}",
                                                  f"task file: {os.path.join(target, 'task.md')}"])
        code, _, err = self.command("build", "w-broken", target)
        self.assertEqual(code, 2)
        self.assertIn("not an empty folder", err)
        code, out, _ = self.command("sheet")
        self.assertEqual(code, 0)
        self.assertIn("## w-broken", out)
        code, out, _ = self.command("status")
        self.assertEqual((code, out.strip().split("\n")[-1]), (0, "0 of 4 agreed"))
        for arguments in (["agree"], ["agree", "--all", "w-broken"], ["agree", "w-broken", "--date", "soon"]):
            self.assertEqual(self.command(*arguments)[0], 2, arguments)
        self.assertEqual(self.command("agree", "w-broken", "--date", "2026-01-02")[:2], (0, "agreed with 1 case(s)\n"))
        self.assertEqual(self.command("agree", "--all")[:2], (0, "agreed with 4 case(s)\n"))
        code, out, _ = self.command("status")
        self.assertEqual(out.strip().split("\n")[-1], "4 of 4 agreed")
        # A problem makes check exit 1 and say what it is.
        self.change("d-broken", "label", lambda d: d["mechanisms"][0]["place"].update(lines=[1, 1]))
        code, out, _ = self.command("check")
        self.assertEqual(code, 1)
        self.assertIn("problem - d-broken: mechanism 1: tool.sh:1-1 does not hold", out)
        self.assertEqual(out.strip().split("\n")[-1], "1 problem(s)")
        self.assertIn("d-broken\tchanged since it was agreed with", self.command("status")[1])
        # A corpus with a problem: no sheet is printed, and the other commands say what
        # they can without a trace.
        self.put("d-control", case=["a", "list"])
        code, out, err = self.command("sheet")
        self.assertEqual((code, out), (2, ""))
        self.assertIn("the sheet is for a corpus that check finds no problem in", err)
        self.assertEqual(self.command("list")[0], 0)
        self.assertEqual(self.command("check")[0], 1)
        code, out, _ = self.command("status")
        self.assertEqual(code, 0)
        self.assertIn("d-control\tchanged since it was agreed with", out)
        # A record of agreements that cannot be read is said, not shown as a trace.
        write(os.path.join(self.corpus, "agreed.json"), "[]")
        code, _, err = self.command("status")
        self.assertEqual(code, 2)
        self.assertIn("must be an object that holds the object agreed", err)
        code, _, err = self.command("--corpus", os.path.join(self.folder, "none"), "list")
        self.assertEqual((code, "no cases folder" in err), (2, True))


class RealCorpusTest(unittest.TestCase):
    """The corpus of this repository, in tests/eval."""

    @classmethod
    def setUpClass(cls):
        cls.cases = eval_corpus.load(REAL)
        cls.result = eval_corpus.check(REAL, ROOT, eval_corpus.slow_asked())

    def test_the_corpus_of_this_repository_has_20_to_30_cases_from_three_sources(self):
        self.assertTrue(20 <= len(self.cases) <= 30, len(self.cases))
        defects = {name: entry for name, entry in self.cases.items() if entry["case"]["kind"] == "defect"}
        by_source = {}
        for name, entry in defects.items():
            by_source.setdefault(entry["case"]["source"], []).append(name)
        self.assertGreaterEqual(len(by_source.get("history", [])), 2, by_source)
        self.assertGreaterEqual(len(by_source.get("derived", [])), 1, by_source)
        # The written cases: one that no criterion covers and that is P0, the security
        # rubric; an unmet criterion; a false handoff claim; an addition beyond the request.
        written = [(item["tag"].split(" ")[0], item["severity"])
                   for name in by_source.get("written", []) for item in self.cases[name]["label"]["mechanisms"]]
        self.assertEqual(sorted(written), [("beyond", "P2"), ("criterion", "P1"), ("handoff", "P2"), ("none", "P0")])

    def test_the_corpus_of_this_repository_holds(self):
        self.assertEqual(self.result[0], [])

    def test_every_proof_of_the_corpus_ran_on_this_system(self):
        waiting = [f"{where}: {why}" for where, why, kind in self.result[1] if kind != "reading"]
        if waiting:
            self.skipTest(f"{len(waiting)} proofs or comparisons of the corpus did not run on this system; "
                          f"the first: {waiting[0]}")
        self.assertGreater(self.result[2], 0)

    def test_no_fixture_of_the_corpus_holds_a_label_or_the_name_of_a_case(self):
        with tempfile.TemporaryDirectory() as folder:
            for number, (name, entry) in enumerate(self.cases.items()):
                try:
                    work, _ = eval_corpus.build(REAL, ROOT, self.cases, name, os.path.join(folder, str(number)))
                except eval_corpus.Missing:
                    continue
                secrets = [name.encode()] + [item[key].encode("utf-8") for item in (entry["label"] or {}).get(
                    "mechanisms", []) for key in ("mechanism", "trigger", "why_severity")]
                for root, _, names in os.walk(os.path.dirname(work)):
                    for file in names:
                        with open(os.path.join(root, file), "rb") as handle:
                            data = handle.read()
                        for secret in secrets:
                            self.assertNotIn(secret, data, f"{name}: {file}")

    def test_the_tests_of_each_written_fixture_pass_and_number_what_its_handoff_says(self):
        # A control must make no false claim, and the one defect about a handoff makes
        # exactly its own: it names one test more than there is. Another package named
        # tests on the path, as an installed one would be, does not get in the way.
        with tempfile.TemporaryDirectory() as folder:
            write(os.path.join(folder, "other", "tests", "__init__.py"), "")
            env = dict(os.environ, PYTHONPATH=os.path.join(folder, "other"))
            for number, (name, entry) in enumerate(self.cases.items()):
                if entry["case"]["source"] != "written":
                    continue
                work, task = eval_corpus.build(REAL, ROOT, self.cases, name, os.path.join(folder, str(number)))
                done = subprocess.run([sys.executable, "-B", "-m", "unittest", "tests.test_app"], cwd=work, env=env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                said = done.stderr.decode("utf-8", "replace")
                self.assertEqual(done.returncode, 0, f"{name}: {said[-600:]}")
                ran = int(re.search(r"Ran (\d+) tests", said).group(1))
                with open(task, encoding="utf-8") as handle:
                    claimed = int(re.search(r"passed, `OK`, (\d+) tests", handle.read()).group(1))
                tags = [item["tag"] for item in (entry["label"].get("mechanisms") or [])]
                self.assertEqual(claimed - ran, 1 if tags == ["handoff"] else 0, name)

    def test_the_proof_that_makes_a_repository_of_its_own_is_not_shaped_by_a_template(self):
        # The proof of the first pair from history makes a small repository and edits a
        # file in it. A template folder whose ignore rules hide every file would hide that
        # file too, and the proof would see no change on the control either.
        with tempfile.TemporaryDirectory() as folder:
            write(os.path.join(folder, "template", "info", "exclude"), "*\n")
            env = eval_corpus.own_environment({"GIT_TEMPLATE_DIR": os.path.join(folder, "template")})
            for number, (name, code) in enumerate((("h1-control", 0), ("h1-subfolder", 10))):
                try:
                    work, _ = eval_corpus.build(REAL, ROOT, self.cases, name, os.path.join(folder, str(number)))
                except eval_corpus.Missing as error:
                    self.skipTest(f"the proof that makes a repository of its own: {error}")
                done = subprocess.run([sys.executable, "-B", "-I", os.path.join(REAL, "proofs", "subfolder.py"), work],
                                      env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if done.returncode == 77:
                    self.skipTest("the proof that makes a repository of its own: no bash or no git to run it with")
                self.assertEqual(done.returncode, code, f"{name}: {done.stdout.decode('utf-8', 'replace')}")

    def test_a_proof_reads_the_fixture_and_not_another_package_of_the_same_name(self):
        # The proof of the handoff pair imports the fixture's tests. A package named
        # tests later on the path, as in a Python that has one installed, must not win.
        runner = ("import runpy, sys\nsys.path.append(sys.argv[1])\nsys.argv = sys.argv[2:]\n"
                  "runpy.run_path(sys.argv[0], run_name='__main__')\n")
        with tempfile.TemporaryDirectory() as folder:
            write(os.path.join(folder, "other", "tests", "__init__.py"), "")
            for number, (name, code) in enumerate((("w-handoff-control", 0), ("w-handoff", 10))):
                work, _ = eval_corpus.build(REAL, ROOT, self.cases, name, os.path.join(folder, str(number)))
                done = subprocess.run([sys.executable, "-B", "-I", "-c", runner, os.path.join(folder, "other"),
                                       os.path.join(REAL, "proofs", "named_test.py"), work],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(done.returncode, code, f"{name}: {done.stderr.decode('utf-8', 'replace')[-600:]}")

    def test_the_sheet_of_the_corpus_names_every_case_and_no_case_is_agreed_with_by_a_test(self):
        text = eval_corpus.sheet(REAL)
        for name in self.cases:
            self.assertIn(f"## {name}\n", text)
        record = eval_corpus.read_agreed(REAL)
        for name in record:
            self.assertIn(name, self.cases)


class Lines(unittest.TextTestResult):
    """Prints one line per test in the form the shell tests use."""

    def addSuccess(self, test):
        super().addSuccess(test)
        print(f"ok   - {test._testMethodName[5:].replace('_', ' ')}")

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        print(f"skip - {reason}")

    def addFailure(self, test, err):
        super().addFailure(test, err)
        print(f"FAIL - {test._testMethodName[5:].replace('_', ' ')}")

    def addError(self, test, err):
        super().addError(test, err)
        print(f"FAIL - {test._testMethodName[5:].replace('_', ' ')} (error)")

    def addSubTest(self, test, subtest, err):
        # A part of a test that fails is named, so that the failed case has a line.
        super().addSubTest(test, subtest, err)
        if err is not None:
            print(f"FAIL - {test._testMethodName[5:].replace('_', ' ')} ({subtest._subDescription()})")


if __name__ == "__main__":
    suite = unittest.TestSuite()
    for case in (SmallCorpusTest, RealCorpusTest):
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(case))
    result = unittest.TextTestRunner(stream=io.StringIO(), resultclass=Lines, verbosity=0).run(suite)
    for _, trace in result.failures + result.errors:
        print(trace, file=sys.stderr)
    if not result.wasSuccessful():
        print(f"{len(result.failures) + len(result.errors)} failed")
        sys.exit(1)
    print("all passed" + (f", {len(result.skipped)} skipped" if result.skipped else ""))
