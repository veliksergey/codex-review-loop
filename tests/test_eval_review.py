#!/usr/bin/env python3
"""Tests for tests/eval_review.py. Run through: bash tests/eval-review.test.sh

They work on the small corpus of test_eval_corpus.py, with a stand-in named codex first
on PATH and a home folder of their own. No test starts a review, and none reads or
writes the log folder of a person. The lines of a made-up log are put together when the
tests run: no line of this file has the shape of a log event. Python 3, standard
library only.
"""
import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import unittest.mock

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def beside(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


eval_review = beside("eval_review")
eval_corpus = eval_review.eval_corpus
# The small corpus, and how a test file of this repository prints its cases. Loading it
# also keeps git from looking above the folder for temporary files.
corpus_tests = beside("test_eval_corpus")
write = corpus_tests.write

# The stand-in answers what tool-flags.sh asks Codex. For a review it writes what its
# control folder holds: the review, a log around the prompt it was given, and its exit
# code. It notes every call, and the folder a review was started in.
STAND_IN = """#!/usr/bin/env bash
control="{control}"
printf '%s\\n' "$*" >> "$control/calls"
case "$1 $2" in
  "--stand-in ") echo stand-in; exit 0 ;;
  "mcp list") [ ! -e "$control/no-servers" ] || exit 1; echo '[]'; exit 0 ;;
  "debug prompt-input") echo '[{{"name":"shell"}}]'; exit 0 ;;
  "exec review") ;;
  *) exit 64 ;;
esac
pwd > "$control/folder"
out=""; before=""
for argument in "$@"; do
  if [ "$before" = "-o" ]; then out="$argument"; fi
  before="$argument"
done
{{ cat "$control/log-head"; echo user; cat; cat "$control/log-tail"; }} >&2
[ ! -e "$control/review" ] || cat "$control/review" > "$out"
[ ! -e "$control/change" ] || echo changed > changed.txt
exit "$(cat "$control/code")"
"""
RULE = "-" * 8
# One command that ran, and one call of a tool outside the shell, as Codex logs them.
RAN = "".join(line + "\n" for line in ("exec", '"sh" -c "git status" in /work/repo', " succeeded in 12ms:", ""))
TOOL = "".join(line + "\n" for line in ("mcp: files/read started", "mcp: files/read (completed)"))
SEARCH = TOOL.replace("files/read", "codex_apps/search_service.web_run")
# A review of the case w-broken: its mechanism, a false alarm, and a point of style.
REVIEW = "\n".join([
    "Criterion 1 is not met; the change stays within the request.", "", "Full review comments:", "",
    "- [P1] (criterion 1) The answer is two, not one \u2014 /work/repo/app.py:3-3", "  `answer()` returns 2.", "",
    "- [P2] The comment misleads \u2014 /work/repo/app.py:1-1", "  It says nothing.", "",
    "- [P3] Name the constant", "  A point of style.", ""])
HASHES = " ".join(4 * ["e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"])
FACTS = "\n".join(["sandbox=read-only", "shell_started=3", "shell_ran=3", "shell_start_failed=0", "shell_usable=yes",
                   "tool_calls=0", "web_search_calls=0", "other_tool_calls=0"])
# A command that failed to start, with a sample of a log in its text: one of its lines
# has the shape of a command that ran.
NO_START = "".join(line + "\n" for line in (
    "exec", '"sh" -c "cat <<EOF', " succeeded in 12ms:", 'EOF" in /work/repo',
    "2026-01-01T00:00:00.000000Z ERROR codex_core::tools::router: error=" + "exec_command failed: CreateProcess",
    " exited -1 in 0ms:", "Failed to create unified exec process"))
UNSTATED = {"is": None, "mechanism": None, "note": ""}


def header(sandbox="read-only"):
    return "".join(line + "\n" for line in (
        "OpenAI Codex v0.0.1", RULE, "workdir: /work/repo", "model: test-model", "provider: test", "approval: never",
        f"sandbox: {sandbox}", "reasoning effort: high", "session id: 00000000-0000-0000-0000-000000000001", RULE))


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


class Small(unittest.TestCase):
    """The small corpus with every label agreed, an empty results folder, and the stand-in."""

    @classmethod
    def setUpClass(cls):
        try:
            bash = eval_review.bash()
        except eval_review.Problem as error:
            raise unittest.SkipTest(f"the review runner: {error}")
        outer = tempfile.TemporaryDirectory()
        cls.addClassCleanup(outer.cleanup)
        cls.repository = os.path.join(outer.name, "repository")
        cls.commit = corpus_tests.make_repository(cls.repository)
        cls.home, cls.control = os.path.join(outer.name, "home"), os.path.join(outer.name, "control")
        os.makedirs(cls.home)
        os.makedirs(cls.control)
        stand_in = os.path.join(outer.name, "bin", "codex")
        write(stand_in, STAND_IN.format(control=cls.control.replace(os.sep, "/")))
        os.chmod(stand_in, 0o755)
        changed = unittest.mock.patch.dict(os.environ, {
            "HOME": cls.home, "PATH": os.path.dirname(stand_in) + os.pathsep + os.environ.get("PATH", "")})
        changed.start()
        cls.addClassCleanup(changed.stop)
        # Nothing runs unless the name codex leads to the stand-in: a test must not be
        # able to spend a review.
        found = subprocess.run([bash, "-c", "codex --stand-in"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if found.stdout.decode("utf-8", "replace").strip() != "stand-in":
            raise AssertionError("the stand-in for codex is not the first codex on PATH")

    def setUp(self):
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.folder = holder.name
        self.corpus, self.results = os.path.join(self.folder, "corpus"), os.path.join(self.folder, "results")
        corpus_tests.small_corpus(self.corpus, self.commit)
        self.cases = eval_corpus.load(self.corpus)
        eval_corpus.agree(self.corpus, self.repository, sorted(self.cases), "2026-01-31")
        self.codex()

    def codex(self, review=REVIEW, code=0, head=None, tail=RAN, change=False, servers=True):
        """What the stand-in does from now on. No review at all: review=None."""
        for file in os.listdir(self.control):
            os.remove(os.path.join(self.control, file))
        for file, content in (("review", review), ("code", str(code)), ("log-head", head or header()),
                              ("log-tail", tail), ("change", "x" if change else None),
                              ("no-servers", None if servers else "x")):
            if content is not None:
                write(os.path.join(self.control, file), content)

    def calls(self):
        return [line for line in eval_review.read(os.path.join(self.control, "calls")).split("\n") if line]

    def command(self, *arguments, results=""):
        """Runs the script. results: the folder to name, None to name none."""
        named = [] if results is None else ["--results", results or self.results]
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = eval_review.main(["--corpus", self.corpus, "--repository", self.repository] + named
                                    + list(arguments))
        return code, out.getvalue(), err.getvalue()

    def left(self, out):
        """The folder a run left, from what it printed."""
        return next(line for line in out.split("\n") if line.startswith("review: "))[len("review: "):]

    def change_label(self, name):
        path = os.path.join(self.corpus, "labels", name + ".json")
        label = load(path)
        label["note"] = "Read again."
        write(path, json.dumps(label))

    def review(self, name, review, stamp="20260131-120000", **more):
        """A review folder as run leaves one, made without a run."""
        folder = os.path.join(self.results, name, stamp)
        os.makedirs(folder)
        write(os.path.join(folder, eval_review.REVIEW), review)
        record = {"case": name, "label": eval_corpus.case_hash(self.corpus, self.repository, self.cases[name]),
                  "dry_run": False, "codex_exit": 0, "usable": True, "unusable": []}
        record.update(more)
        write(os.path.join(folder, "record.json"), json.dumps(record))
        return folder

    def state(self, folder, *said, edit=None):
        """States what the findings of a judgment are, each as (is, mechanism) or None,
        and signs it. edit: a last change to the judgment."""
        path = os.path.join(folder, "judgment.json")
        judgment = load(path)
        for found, what in zip(judgment["findings"], said):
            if what is not None:
                found["is"], found["mechanism"] = what[0], (what[1] if len(what) > 1 else None)
        judgment.update(judged_by="a tester", judged_on="2026-01-31")
        if edit:
            edit(judgment)
        write(path, json.dumps(judgment))


class RunTest(Small):
    def test_a_review_runs_codex_as_the_loop_does_and_leaves_a_folder_of_its_own(self):
        before = (eval_corpus.tree(self.corpus), eval_corpus.tree(self.repository))
        code, out, err = self.command("run", "w-broken", results=None)
        self.assertEqual(code, 0, err)
        folder = self.left(out)
        # Without --results: the folder eval in the loop's log folder of this repository.
        self.assertTrue(os.path.samefile(os.path.dirname(folder), os.path.join(
            self.home, ".claude", "codex-reviews", os.path.basename(ROOT), "eval", "w-broken")))
        self.assertEqual(sorted(os.listdir(folder)), [
            "facts.txt", "record.json", "review-codex.log", "review-codex.md", "review-prompt.md", "review.sh",
            "tool-flags.txt"])
        # One call started a review: read-only, in the fixture, with the flags tool-flags.sh
        # gives for a review without web search.
        flags = "--disable plugins --disable apps -c web_search=\"disabled\""
        self.assertEqual([call for call in self.calls() if call.startswith("exec ")],
                         [f"exec review -c sandbox_mode=\"read-only\" {flags} -o ../out/review-codex.md -"])
        self.assertTrue(eval_review.read(os.path.join(self.control, "folder")).strip().endswith("/repo"))
        prompt = eval_review.read(os.path.join(folder, "review-prompt.md"))
        self.assertIn("<scope>\nTarget: all uncommitted changes in this repository", prompt)
        self.assertIn("<task>\n" + corpus_tests.TASK + "\nAll done.\n</task>", prompt)
        self.assertIn("does not\napply.\nnone\n\nThese files carry rules", prompt)
        self.assertIn("Extra focus from the user: none\n", prompt)
        self.assertNotIn("{{", prompt)
        # Codex was given that prompt, and its log echoes it.
        self.assertIn(prompt, eval_review.read(os.path.join(folder, "review-codex.log")))
        self.assertEqual(eval_review.read(os.path.join(folder, "review-codex.md")), REVIEW)
        facts = eval_review.read(os.path.join(folder, "facts.txt")).split("\n")
        for line in ("log=review-codex.log", "sandbox=read-only", "shell_ran=1", "shell_usable=yes", "tool_calls=0"):
            self.assertIn(line, facts)
        record = load(os.path.join(folder, "record.json"))
        self.assertEqual({key: record[key] for key in ("case", "kind", "mode", "dry_run", "codex_exit", "usable",
                                                       "unusable")},
                         {"case": "w-broken", "kind": "defect", "mode": "uncommitted", "dry_run": False,
                          "codex_exit": 0, "usable": True, "unusable": []})
        self.assertEqual(record["label"], eval_corpus.case_hash(self.corpus, self.repository, self.cases["w-broken"]))
        self.assertEqual(record["plugin"]["version"],
                         load(os.path.join(eval_review.PLUGIN, ".claude-plugin", "plugin.json"))["version"])
        self.assertRegex(record["fingerprint"]["before"], eval_review.HASHES)
        self.assertEqual(record["fingerprint"]["after"], record["fingerprint"]["before"])
        self.assertIsInstance(record["seconds"], int)
        self.assertRegex(record["commit"], r"^([0-9a-f]{40,64}|unknown)$")
        # Nothing of the review is written in the corpus or in the repository it reads.
        self.assertEqual((eval_corpus.tree(self.corpus), eval_corpus.tree(self.repository)), before)
        # What run left is what judge and report read.
        code, out, err = self.command("judge", results=os.path.dirname(os.path.dirname(folder)))
        self.assertEqual(code, 0, err)
        self.assertIn("1 judgment(s) written, 1 to complete", out)
        self.assertEqual([found["label"] for found in load(os.path.join(folder, "judgment.json"))["findings"]],
                         ["P1", "P2", "P3"])
        # Report finds the folder that run used when none is named.
        code, out, err = self.command("report", results=None)
        self.assertEqual(code, 0, err)
        self.assertIn("Reviews: 1. Scored: 0. Left out: 1.\n  judgment not complete: 1\n", out)

    def test_a_dry_run_builds_the_prompt_of_an_audit_and_starts_no_review(self):
        code, out, err = self.command("run", "d-broken", "--dry-run", "--web", "cached")
        self.assertEqual(code, 0, err)
        folder = self.left(out)
        # The web search mode that was asked for is the one tool-flags.sh was given.
        cached = ("--disable plugins -c 'apps._default.enabled=false' "
                  "-c 'apps.connector_openai_search_service.enabled=true' -c 'web_search=\"cached\"'")
        self.assertEqual(eval_review.read(os.path.join(folder, "tool-flags.txt")), cached + "\n")
        self.assertIn("codex exec review -c 'sandbox_mode=\"read-only\"' " + cached + "\n", out)
        self.assertEqual(sorted(os.listdir(folder)), ["record.json", "review-prompt.md", "tool-flags.txt"])
        prompt = eval_review.read(os.path.join(folder, "review-prompt.md"))
        self.assertIn("Target files and folders, relative to the repository root:\ntool.sh\nReview the current", prompt)
        self.assertIn("`git diff --cached -- tool.sh` to see what changed recently", prompt)
        self.assertIn("<task>\n" + eval_review.NO_TASK + "\n</task>", prompt)
        for mark in ("<paths>", "<target>", "{{"):
            self.assertNotIn(mark, prompt)
        self.assertEqual([call for call in self.calls() if call.startswith("exec ")], [])
        record = load(os.path.join(folder, "record.json"))
        self.assertTrue(record["dry_run"])
        self.assertEqual(record["web"], "cached")
        self.assertNotIn("usable", record)
        # A dry run is no review: nothing to judge, and none counted.
        code, out, err = self.command("judge")
        self.assertIn("0 judgment(s) written, 0 to complete", out)
        code, out, err = self.command("report")
        self.assertIn("Reviews: 0. Scored: 0. Left out: 0.", out)
        self.assertIn("Dry runs, which are no reviews: 1", out)

    def test_a_case_whose_label_is_not_agreed_with_is_not_reviewed(self):
        self.change_label("w-broken")
        code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 2)
        self.assertIn("the label is changed since it was agreed with", err)
        os.remove(os.path.join(self.corpus, "agreed.json"))
        code, out, err = self.command("run", "w-control")
        self.assertEqual(code, 2)
        self.assertIn("the label is not agreed", err)
        code, out, err = self.command("run", "no-such-case")
        self.assertEqual(code, 2)
        # Codex was not asked anything, and nothing was kept.
        self.assertEqual(self.calls(), [])
        self.assertFalse(os.path.exists(self.results))

    def test_results_inside_this_repository_or_beside_the_corpus_are_refused(self):
        places = {"the corpus": os.path.join(self.corpus, "results"),
                  "the repository that is read": os.path.join(self.repository, "results"),
                  "this repository": os.path.join(ROOT, "tests", "results-of-a-test")}
        for name, place in places.items():
            with self.subTest(name):
                for command in (["run", "w-broken"], ["judge"]):
                    code, out, err = self.command(*command, results=place)
                    self.assertEqual(code, 2)
                    self.assertIn("the results of a review are kept outside this repository", err)
                self.assertFalse(os.path.exists(place))
        self.assertEqual(self.calls(), [])

    def test_a_folder_for_temporary_files_inside_this_repository_is_refused(self):
        # The corpus and the repository that is read lie elsewhere; the folder the review
        # would be written to first lies in the checkout of the runner.
        scratch = os.path.join(ROOT, "tests", "no-such-folder")
        with unittest.mock.patch.object(eval_review.tempfile, "tempdir", scratch):
            for more in ([], ["--dry-run"]):
                code, out, err = self.command("run", "w-broken", *more)
                self.assertEqual(code, 2)
                self.assertIn("the folder for temporary files lies inside this repository", err)
        self.assertEqual(self.calls(), [])
        self.assertFalse(os.path.exists(scratch))

    def test_no_review_starts_when_the_tools_of_the_reviewer_cannot_be_limited(self):
        self.codex(servers=False)
        code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 2)
        self.assertIn("the tools of the reviewer cannot be limited, so no review starts", err)
        self.assertEqual([call for call in self.calls() if call.startswith("exec ")], [])
        self.assertFalse(os.path.exists(self.results))

    def test_a_results_folder_that_cannot_be_made_stops_the_run_before_the_review(self):
        write(self.results, "a file where the folder should be\n")
        code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 2)
        self.assertEqual([call for call in self.calls() if call.startswith("exec ")], [])

    def failing_write(self, file):
        """A write that fails for one file name, as on a full disk."""
        real = eval_review.write

        def failing(path, content):
            if os.path.basename(path) == file:
                raise OSError("the disk is full")
            real(path, content)
        return unittest.mock.patch.object(eval_review, "write", failing)

    def test_a_review_that_was_started_is_not_thrown_away_when_a_later_step_fails(self):
        steps = {"the copy to the results": unittest.mock.patch.object(
                     eval_review, "keep", side_effect=OSError("the disk is full")),
                 "the facts": self.failing_write("facts.txt"), "the record": self.failing_write("record.json")}
        for name, step in steps.items():
            with self.subTest(name):
                with step:
                    code, out, err = self.command("run", "w-broken")
                self.assertEqual(code, 2)
                self.assertIn("could not be kept in the results; it stays in ", err)
                left = err.split("it stays in ", 1)[1].split(": the disk is full")[0]
                self.addCleanup(eval_review.remove, os.path.dirname(left))
                self.assertEqual(eval_review.read(os.path.join(left, "review-codex.md")), REVIEW)
                self.assertIn("exec\n", eval_review.read(os.path.join(left, "review-codex.log")))
        # Before the review nothing is lost, and the fixture is deleted as ever.
        with steps["the copy to the results"]:
            code, out, err = self.command("run", "w-broken", "--dry-run")
        self.assertEqual(code, 2)
        self.assertIn("the disk is full", err)
        self.assertNotIn("it stays in", err)

    def test_codex_is_started_with_the_flags_also_when_their_file_is_lost(self):
        real = eval_review.write

        def losing(path, content):
            # The file that records the flags never reaches the disk.
            if os.path.basename(path) != "tool-flags.txt":
                real(path, content)

        with unittest.mock.patch.object(eval_review, "write", losing):
            code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 0, err)
        self.assertNotIn("tool-flags.txt", os.listdir(self.left(out)))
        self.assertEqual([call for call in self.calls() if call.startswith("exec ")], [
            "exec review -c sandbox_mode=\"read-only\" --disable plugins --disable apps -c web_search=\"disabled\" "
            "-o ../out/review-codex.md -"])

    def test_a_run_that_is_stopped_names_the_folder_with_what_the_review_left(self):
        real = eval_review.subprocess.run

        def stopped(arguments, **more):
            if arguments[-1] == "../out/review.sh":
                raise KeyboardInterrupt
            return real(arguments, **more)

        with unittest.mock.patch.object(eval_review.subprocess, "run", stopped):
            code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 130)
        left = err.split("what it left stays in ", 1)[1].split("\n")[0]
        self.addCleanup(eval_review.remove, os.path.dirname(left))
        self.assertIn("review-prompt.md", os.listdir(left))
        self.assertEqual(os.listdir(os.path.join(self.results, "w-broken")), [])

    def link(self, target, path):
        """A link to a folder: a symbolic link, or a junction where Windows allows no other."""
        try:
            os.symlink(target, path, target_is_directory=True)
        except (OSError, NotImplementedError):
            made = subprocess.run(["cmd", "/c", "mklink", "/J", path, target], stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE) if os.name == "nt" else None
            if made is None or made.returncode != 0:
                self.skipTest("a link below the results folder: this system cannot create a link to a folder")

    def test_a_link_below_the_results_that_leads_into_the_repository_is_not_followed(self):
        # The results folder itself lies outside; the folder of a case in it is a link.
        inside = os.path.join(self.corpus, "kept-here")
        os.makedirs(inside)
        os.makedirs(self.results)
        self.link(inside, os.path.join(self.results, "w-broken"))
        code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 2)
        self.assertIn("the results of a review are kept outside this repository", err)
        self.assertEqual(self.calls(), [])
        self.assertEqual(os.listdir(inside), [])
        # And the folder of a review that is a link: judge writes no judgment through it.
        review = self.review("w-control", REVIEW)
        moved = os.path.join(self.corpus, "a-review")
        os.rename(review, moved)
        self.link(moved, review)
        code, out, err = self.command("judge")
        self.assertEqual(code, 2)
        self.assertIn("the results of a review are kept outside this repository", err)
        self.assertEqual(sorted(os.listdir(moved)), ["record.json", "review-codex.md"])

    def test_half_a_copy_in_the_results_is_never_taken_for_a_review(self):
        real = eval_review.shutil.copyfile

        def failing(source, target):
            # The prompt is copied after the review and its log.
            if os.path.basename(source) == "review-prompt.md":
                raise OSError("the disk is full")
            return real(source, target)

        def left(err):
            folder = os.path.dirname(err.split("it stays in ", 1)[1].split(": the disk is full")[0])
            self.addCleanup(eval_review.remove, folder)

        with unittest.mock.patch.object(eval_review.shutil, "copyfile", failing):
            code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 2)
        left(err)
        self.assertEqual(os.listdir(os.path.join(self.results, "w-broken")), [])
        # Where half a copy cannot be deleted, it holds no record and counts as no review.
        with unittest.mock.patch.object(eval_review.shutil, "copyfile", failing), \
                unittest.mock.patch.object(eval_review.shutil, "rmtree"):
            code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 2)
        left(err)
        (half,) = os.listdir(os.path.join(self.results, "w-broken"))
        self.assertEqual(sorted(os.listdir(os.path.join(self.results, "w-broken", half))),
                         ["facts.txt", "review-codex.log", "review-codex.md"])
        code, out, err = self.command("judge")
        self.assertIn("0 judgment(s) written, 0 to complete", out)
        code, out, err = self.command("report")
        self.assertIn("Reviews: 1. Scored: 0. Left out: 1.\n  no record: 1\n", out)

    def test_a_review_that_cannot_be_trusted_is_marked_with_each_reason_and_never_scored(self):
        # Everything at once: an exit code, no review, no command that ran, a tool call, a
        # web search, a sandbox that can write, a file added to the fixture, and the name of
        # the case.
        self.codex(review="", code=3, head=header("workspace-write"),
                   tail=TOOL + SEARCH + "cat labels/w-broken.json\n", change=True)
        code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 1, err)
        folder = self.left(out)
        record = load(os.path.join(folder, "record.json"))
        self.assertIs(record["usable"], False)
        self.assertEqual(record["codex_exit"], 3)
        self.assertNotEqual(record["fingerprint"]["after"], record["fingerprint"]["before"])
        for part in ("Codex ended with exit code 3", "the review is empty", "no sandboxed command ran",
                     "a tool that should be off was called: tool=files/read calls=1",
                     "the sandbox was workspace-write, not read-only", "the reviewer searched the web",
                     "the fixture changed during the review", "the log names the case"):
            self.assertEqual(sum(1 for why in record["unusable"] if part in why), 1, part)
        self.assertEqual(len(record["unusable"]), 8)
        self.assertIn("usable: no", out)
        code, out, err = self.command("judge")
        self.assertIn("0 judgment(s) written, 0 to complete", out)
        self.assertFalse(os.path.exists(os.path.join(folder, "judgment.json")))
        code, out, err = self.command("report")
        self.assertIn("Reviews: 1. Scored: 0. Left out: 1.\n  not usable: 1\n", out)

    def test_a_line_in_the_text_of_a_command_is_not_taken_for_a_command_that_ran(self):
        # The only command of the review failed to start; the count of commands that ran
        # is one all the same, from a line inside its text.
        self.codex(tail=NO_START)
        code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 1, err)
        folder = self.left(out)
        facts = eval_review.read(os.path.join(folder, "facts.txt")).split("\n")
        for line in ("shell_started=1", "shell_ran=1", "shell_start_failed=1", "shell_usable=yes"):
            self.assertIn(line, facts)
        self.assertEqual(load(os.path.join(folder, "record.json"))["unusable"], [
            "the log does not show beyond doubt that a sandboxed command ran: 1 started, 1 ran, 1 failed to start"])

    def test_each_reason_alone_makes_a_review_unusable(self):
        good = {"code": 0, "review": "Fine.", "facts": FACTS, "trouble": "", "before": HASHES, "after": HASHES,
                "leaked": False}
        self.assertEqual(eval_review.reasons(**good), [])
        other = HASHES.replace("e69d", "0000", 1)
        for change, part in (
                ({"code": 1}, "exit code 1"), ({"review": " \n"}, "the review is empty"),
                ({"facts": None, "trouble": "not a Codex review log"}, "cannot be read: not a Codex review log"),
                ({"facts": FACTS.replace("shell_usable=yes", "shell_usable=no")}, "no sandboxed command ran"),
                ({"facts": FACTS.replace("shell_start_failed=0", "shell_start_failed=1")},
                 "beyond doubt that a sandboxed command ran: 3 started, 3 ran, 1 failed to start"),
                ({"facts": FACTS.replace("shell_ran=3", "shell_ran=4")},
                 "beyond doubt that a sandboxed command ran: 3 started, 4 ran, 0 failed to start"),
                ({"facts": FACTS.replace("other_tool_calls=0", "other_tool_calls=1") + "\ntool=files/read calls=1 lines=7"},
                 "a tool that should be off was called: tool=files/read calls=1 lines=7"),
                ({"facts": FACTS.replace("sandbox=read-only", "sandbox=workspace-write")}, "not read-only"),
                ({"facts": FACTS.replace("sandbox=read-only\n", "")}, "the sandbox was not named"),
                ({"facts": FACTS.replace("web_search_calls=0", "web_search_calls=2")
                  + "\ntool=codex_apps/search_service.web_run calls=2 lines=5,9"}, "the reviewer searched the web"),
                ({"after": "failed: no git"}, "could not be taken after the review: failed: no git"),
                ({"after": other}, "the fixture changed during the review"),
                ({"leaked": True}, "the reviewer may have read a label")):
            with self.subTest(part):
                why = eval_review.reasons(**dict(good, **change))
                self.assertEqual(len(why), 1, why)
                self.assertIn(part, why[0])

    def test_a_label_read_by_a_path_that_names_nothing_is_noticed_by_its_lines(self):
        label = os.path.join(self.corpus, "labels", "w-broken.json")
        # The reviewer went to the corpus step by step and read every label with a
        # pattern: its log names neither the case nor a folder, and holds the label.
        self.codex(tail=RAN + "cat labels/*.json\n   1 " + eval_review.read(label) + "\n")
        code, out, err = self.command("run", "w-broken")
        self.assertEqual(code, 1, err)
        (why,) = load(os.path.join(self.left(out), "record.json"))["unusable"]
        self.assertIn("holds a line of the label or the definition of the case", why)
        # As the corpus keeps its files: one value on a line. The short lines, which a
        # log can hold by chance, are no sign; the long ones are.
        write(label, json.dumps(load(label), indent=2))
        lines = eval_review.telltales(self.corpus, "w-broken")
        self.assertIn('"mechanism": "It says the wrong word.",', lines)
        self.assertNotIn('"expect": "finding",', lines)
        self.assertNotIn("{", lines)
        # Nor is a value without its key, or the path of a file with one: the reviewer's
        # own commands print such paths in quotes.
        write(label, '{\n"cases": [\n"a long name of a test case that is run"\n],\n'
                     '"file": "a/long/path/of/the/fixture/app.py",\n"script": "a/long/path/of/the/fixture/tool.sh",\n'
                     '"trigger": "Run it with no argument at all."\n}\n')
        self.assertEqual(eval_review.telltales(self.corpus, "w-broken") - eval_review.telltales(self.corpus, "none"),
                         {'"trigger": "Run it with no argument at all."'} | {
                             line for line in eval_review.telltales(self.corpus, "w-broken") if line.startswith("{")})
        self.assertTrue(eval_review.names('  12   "mechanism": "It says the wrong word.",\n', "w-broken", [], lines))
        # The definition of a case is read the same way. This one does not hold its own name.
        definition = eval_review.read(os.path.join(self.corpus, "cases", "d-broken", "case.json"))
        self.assertFalse(eval_review.names(definition, "d-broken", []))
        self.assertTrue(eval_review.names(definition, "d-broken", [], eval_review.telltales(self.corpus, "d-broken")))
        # What a reviewer reads in the fixture is no line of either file.
        fixture = "# The answer.\ndef answer():\n    return 2\n" + corpus_tests.TASK
        self.assertFalse(eval_review.names(fixture, "w-broken", [], lines))

    def test_a_log_folder_that_leads_into_the_repository_is_refused_before_it_is_made(self):
        # The folder the review loop keeps its logs in is reached through a link.
        home, inside = os.path.join(self.folder, "home"), os.path.join(self.corpus, "kept-here")
        os.makedirs(home)
        os.makedirs(inside)
        self.link(inside, os.path.join(home, ".claude"))
        with unittest.mock.patch.dict(os.environ, {"HOME": home}):
            for command in (["run", "w-broken"], ["judge"], ["report"]):
                code, out, err = self.command(*command, results=None)
                self.assertEqual(code, 2)
                self.assertIn("the results of a review are kept outside this repository", err)
        self.assertEqual(os.listdir(inside), [])
        self.assertEqual(self.calls(), [])

    def test_a_log_that_names_the_case_or_a_folder_with_labels_is_noticed(self):
        folders = [self.corpus, self.results]
        self.assertFalse(eval_review.names("git status\ncat app.py\n", "w-broken", folders))
        self.assertTrue(eval_review.names("cat ../labels/W-Broken.json", "w-broken", folders))
        # Inside a longer word it is not the name of the case.
        self.assertFalse(eval_review.names("a narrow-broken-pipe", "w-broken", folders))
        for folder in folders:
            for path in (os.path.abspath(folder), os.path.realpath(folder)):
                forward = path.replace(os.sep, "/")
                self.assertTrue(eval_review.names(f"ls {forward}/labels", "another", folders))
                # As a program prints a path of Windows inside a text in quotes.
                self.assertTrue(eval_review.names("ls " + forward.replace("/", "\\\\"), "another", folders))


class JudgeTest(Small):
    def test_findings_are_read_with_their_title_and_their_place(self):
        review = "\n".join([
            "Summary.", "", "Review comment:", "",
            "- [P0] (Criterion  2) Loses data \u2014 C:\\work\\repo\\src\\a.py:10-12", "  The body - with a dash: 3",
            "- [P2] (handoff) A claim - src/b.py:7", "- [P3] No place at all",
            "* [P1] A title with a colon: here \u2014 docs/x.md:5"])
        self.assertEqual(eval_review.findings(review), [
            {"label": "P0", "tag": "criterion 2", "title": "Loses data", "file": "C:/work/repo/src/a.py",
             "lines": [10, 12]},
            {"label": "P2", "tag": "handoff", "title": "A claim", "file": "src/b.py", "lines": [7, 7]},
            {"label": "P3", "tag": "none", "title": "No place at all", "file": None, "lines": None},
            {"label": "P1", "tag": "none", "title": "A title with a colon: here", "file": "docs/x.md", "lines": [5, 5]}])
        self.assertEqual(eval_review.findings("Nothing to report.\n"), [])

    def test_judge_lists_the_findings_beside_the_label_and_never_writes_over_a_judgment(self):
        folder = self.review("w-broken", REVIEW)
        code, out, err = self.command("judge")
        self.assertEqual(code, 0, err)
        self.assertIn("1 judgment(s) written, 1 to complete", out)
        self.assertIn("finding 1 is not stated as one of: mechanism, known defect, other defect, false alarm", out)
        judgment = load(os.path.join(folder, "judgment.json"))
        self.assertEqual((judgment["case"], judgment["kind"], judgment["expect"], judgment["judged_by"]),
                         ("w-broken", "defect", "finding", ""))
        self.assertEqual(judgment["mechanisms"], [
            {"number": 1, "mechanism": "It says the wrong word.", "trigger": "Run it.", "file": "app.py",
             "lines": [3, 3], "severity": "P1", "tag": "criterion 1"}])
        place = {"file": "/work/repo/app.py", "same_file": [1]}
        self.assertEqual(judgment["findings"], [
            dict(UNSTATED, number=1, label="P1", tag="criterion 1", title="The answer is two, not one", lines=[3, 3],
                 same_lines=[1], **place),
            dict(UNSTATED, number=2, label="P2", tag="none", title="The comment misleads", lines=[1, 1],
                 same_lines=[], **place),
            dict(UNSTATED, number=3, label="P3", tag="none", title="Name the constant", file=None, lines=None,
                 same_file=[], same_lines=[])])
        # A control has no mechanism to list, and names what is known to stand in it.
        other = self.review("d-control", "- [P1] An old one \u2014 /work/repo/tool.sh:2\n  It is known.\n")
        self.state(folder, ("mechanism", 1), ("false alarm",))
        stated = eval_review.read(os.path.join(folder, "judgment.json"))
        code, out, err = self.command("judge")
        self.assertIn("1 judgment(s) written, 1 to complete", out)
        self.assertEqual(eval_review.read(os.path.join(folder, "judgment.json")), stated)
        judgment = load(os.path.join(other, "judgment.json"))
        self.assertEqual((judgment["mechanisms"], judgment["known_defects"]), ([], ["An old one that is known."]))

    def test_judge_writes_nothing_for_a_review_of_a_label_that_changed_since(self):
        folder = self.review("w-broken", REVIEW)
        self.change_label("w-broken")
        code, out, err = self.command("judge")
        self.assertEqual(code, 0, err)
        self.assertIn("0 judgment(s) written, 0 to complete", out)
        self.assertFalse(os.path.exists(os.path.join(folder, "judgment.json")))
        code, out, err = self.command("report")
        self.assertIn("Reviews: 1. Scored: 0. Left out: 1.\n  case or label changed: 1\n", out)


class ReportTest(Small):
    def test_report_gives_each_figure_with_the_size_of_its_sample(self):
        clean = "No findings. The residual risk is low.\n"
        found = self.review("w-broken", REVIEW)
        as_style = self.review("w-broken", "- [P3] (handoff) A wrong number \u2014 /work/repo/app.py:3\n  Two.\n",
                               stamp="20260131-130000")
        missed = self.review("d-broken", clean)
        alarm = self.review("w-control", "- [P2] Something \u2014 /work/repo/app.py:1-2\n  A body.\n")
        known = self.review("d-control", "- [P1] An old one \u2014 /work/repo/tool.sh:2\n  It is known.\n")
        self.review("d-control", clean, stamp="20260131-130000")
        unstated = self.review("w-control", "- [P2] Another \u2014 /work/repo/app.py:1\n  A body.\n",
                               stamp="20260131-140000")
        self.review("w-broken", "It stopped.\n", stamp="20260131-150000", usable=False,
                    unusable=["Codex ended with exit code 1"])
        self.review("d-broken", clean, stamp="20260131-160000", dry_run=True)
        code, out, err = self.command("judge")
        # Each of them waits: for a statement, or for a name and a date.
        self.assertIn("7 judgment(s) written, 7 to complete", out)
        self.state(found, ("mechanism", 1), ("false alarm",))
        self.state(as_style, ("mechanism", 1))
        self.state(missed)
        self.state(alarm, ("false alarm",))
        self.state(known, ("known defect",))
        self.state(os.path.join(self.results, "d-control", "20260131-130000"))
        # Made after judge ran: a review with no judgment file.
        self.review("w-control", clean, stamp="20260131-170000")
        before = eval_corpus.tree(self.results)
        code, out, err = self.command("report")
        self.assertEqual(code, 0, err)
        self.assertEqual(eval_corpus.tree(self.results), before)
        lines = out.rstrip("\n").split("\n")
        self.assertEqual(lines[:4], [eval_review.PRIVATE, "", f"Results: {self.results}",
                                     "Reviews: 9. Scored: 6. Left out: 3."])
        self.assertEqual(lines[4:8], ["  judgment not complete: 1", "  not judged: 1", "  not usable: 1",
                                      "Dry runs, which are no reviews: 1"])
        none = "a labeled mechanism 0, a known defect 0, another defect 0, a false alarm 0"
        for line in (
                "  w-broken/20260131-120000: defect, must-fix findings 2 (" + none.replace("mechanism 0", "mechanism 1")
                .replace("alarm 0", "alarm 1") + "); mechanisms found by a must-fix finding 1 of 1",
                "  w-broken/20260131-130000: defect, must-fix findings 0; mechanisms found by a must-fix finding 0 of 1",
                "  d-control/20260131-130000: control, must-fix findings 0",
                "  w-broken/20260131-150000: left out, not usable: Codex ended with exit code 1",
                "  w-control/20260131-140000: left out, judgment not complete: finding 1 is not stated as one of: "
                "mechanism, known defect, other defect, false alarm",
                "  w-control/20260131-170000: left out, not judged: it has no judgment file; judge writes one"):
            self.assertIn(line, lines)
        self.assertEqual(lines[lines.index("Defect cases: 3 review(s) of 2 case(s), 3 labeled mechanism(s)"):], [
            "Defect cases: 3 review(s) of 2 case(s), 3 labeled mechanism(s)",
            "  found by a must-fix finding: 1 of 3",
            "  found by a P3 finding only: 1 of 3",
            "  not found: 1 of 3",
            "  severity of the finding against the label: same 1, more severe 0, less severe 1, of 2 found",
            "  tag of the finding against the label: same 1, other 1, of 2 found",
            "  must-fix findings: 2, of which " + none.replace("mechanism 0", "mechanism 1").replace("alarm 0", "alarm 1"),
            "Controls: 3 review(s) of 2 case(s)",
            "  must-fix findings: 2, of which " + none.replace("defect 0, another", "defect 1, another")
            .replace("alarm 0", "alarm 1"),
            "  reviews without a false alarm: 2 of 3"])
        self.assertIsNotNone(unstated)

    def test_report_writes_nothing_also_where_no_results_folder_is_named(self):
        # A home folder in which the review loop has kept nothing yet.
        home = os.path.join(self.folder, "home")
        os.makedirs(home)
        with unittest.mock.patch.dict(os.environ, {"HOME": home}):
            code, out, err = self.command("report", results=None)
        self.assertEqual(code, 0, err)
        self.assertEqual(os.listdir(home), [])
        named = next(line for line in out.split("\n") if line.startswith("Results: "))
        self.assertTrue(named.endswith(os.path.join(".claude", "codex-reviews", os.path.basename(ROOT), "eval")), named)
        self.assertIn("Reviews: 0. Scored: 0. Left out: 0.", out)

    def test_report_says_so_when_no_review_is_scored(self):
        code, out, err = self.command("report")
        self.assertEqual(code, 0, err)
        self.assertEqual(out.rstrip("\n").split("\n"), [
            eval_review.PRIVATE, "", f"Results: {self.results}", "Reviews: 0. Scored: 0. Left out: 0.", "",
            "Defect cases: no review scored.", "Controls: no review scored."])
        self.assertFalse(os.path.exists(self.results))

    def test_a_judgment_counts_only_when_it_is_whole_and_signed(self):
        def gone(judgment):
            judgment["findings"].pop()

        edits = (
            (lambda judgment: judgment.update(judged_by=" "), "it is not signed with a name and a date"),
            (lambda judgment: judgment.update(judged_on="soon"), "it is not signed with a name and a date"),
            (lambda judgment: judgment["findings"][1].update({"is": None}), "finding 2 is not stated as one of"),
            (lambda judgment: judgment["findings"][1].update({"is": "bug"}), "finding 2 is not stated as one of"),
            (lambda judgment: judgment["findings"][2].update({"is": "bug"}), "finding 3 is not stated as one of"),
            (lambda judgment: judgment["findings"][0].update(mechanism=2), "finding 1 is stated as a mechanism and names"),
            (lambda judgment: judgment["findings"][0].update(mechanism=True), "finding 1 is stated as a mechanism and"),
            (gone, "it does not list the findings of the review"),
            (lambda judgment: judgment["findings"][0].update(title="Another title"), "it does not list the findings"),
            (lambda judgment: judgment["findings"][1].update(number=3), "it does not list the findings"),
            (lambda judgment: judgment.update(label="0"), "it was written for another label"),
            (lambda judgment: judgment.update(findings="none"), "it cannot be read"))
        folders = [self.review("w-broken", REVIEW, stamp=f"20260131-12{number:02d}00") for number in range(len(edits) + 2)]
        # Two findings of one severity, stated and then put in the other order: what was
        # stated of the first would be read as said of the second.
        swapped = self.review("w-broken", "- [P1] The answer — /work/repo/app.py:3\n  Two.\n\n"
                              "- [P1] The comment — /work/repo/app.py:1\n  Nothing.\n", stamp="20260131-130000")
        self.command("judge")
        self.state(swapped, ("mechanism", 1), ("false alarm",), edit=lambda judgment: judgment["findings"].reverse())
        for folder, (edit, _) in zip(folders, edits):
            self.state(folder, ("mechanism", 1), ("false alarm",), edit=edit)
        # One whose review was changed after it was judged, and one that is whole: its
        # P3 finding needs no statement.
        self.state(folders[-2], ("mechanism", 1), ("false alarm",))
        write(os.path.join(folders[-2], eval_review.REVIEW), REVIEW + "\n- [P1] One more\n")
        self.state(folders[-1], ("mechanism", 1), ("false alarm",))
        code, out, err = self.command("report")
        self.assertEqual(code, 0, err)
        self.assertIn(f"Reviews: {len(folders) + 1}. Scored: 1. Left out: {len(folders)}.\n"
                      f"  judgment not complete: {len(folders)}\n", out)
        self.assertIn("  w-broken/20260131-130000: left out, judgment not complete: "
                      "it does not list the findings of the review", out)
        for folder, (_, part) in zip(folders, edits):
            self.assertIn(f"  w-broken/{os.path.basename(folder)}: left out, judgment not complete: {part}", out)
        self.assertIn(f"  w-broken/{os.path.basename(folders[-2])}: left out, judgment not complete: "
                      "the review is not the one it was written for", out)
        self.assertIn("  found by a must-fix finding: 1 of 1", out)


if __name__ == "__main__":
    suite = unittest.TestSuite()
    for case in (RunTest, JudgeTest, ReportTest):
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(case))
    result = unittest.TextTestRunner(stream=io.StringIO(), resultclass=corpus_tests.Lines, verbosity=0).run(suite)
    for _, trace in result.failures + result.errors:
        print(trace, file=sys.stderr)
    if not result.wasSuccessful():
        print(f"{len(result.failures) + len(result.errors)} failed")
        sys.exit(1)
    print("all passed" + (f", {len(result.skipped)} skipped" if result.skipped else ""))
