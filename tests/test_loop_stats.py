#!/usr/bin/env python3
"""Tests for tests/loop_stats.py. Run through: bash tests/loop-stats.test.sh

Every log below is synthetic and is built in a temporary folder at run time.
Python 3, standard library only.
"""
import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import unittest.mock

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("loop_stats", os.path.join(HERE, "loop_stats.py"))
loop_stats = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(loop_stats)

ROUND_FACTS = os.path.join(HERE, "..", "plugins", "codex-review-loop", "skills", "codex-loop",
                           "round-facts.sh")
RULE = "--------"
# A fingerprint as fingerprint.sh prints it: four hashes.
PRINT = " ".join(digit * 40 for digit in "1234")


def review(opening, *findings):
    """A review as Codex renders it: an opening, then one bullet per finding."""
    text = opening + "\n"
    if findings:
        text += "\nFull review comments:\n"
    for label, tag, title in findings:
        text += f"\n- [{label}] {'(' + tag + ') ' if tag else ''}{title} — src/app.py:1-2\n  What goes wrong.\n"
    return text


def log(ran=2, failed=0, tools=(), echoed=True, sandbox="read-only"):
    """A Codex log: header, the echoed prompt, shell commands, tool calls, the answer."""
    lines = ["OpenAI Codex v0.0.1", RULE, "workdir: /work/repo", "model: test-model",
             f"sandbox: {sandbox}", "reasoning effort: high", "session id: 0-0", RULE, "user"]
    if echoed:
        # Lines in the echoed prompt that look like events are not events.
        lines += ["exec", " succeeded in 1ms:", "mcp: a/b started", "</grounding_rules>"]
    for _ in range(ran):
        lines += ["exec", '"sh" -c "git status" in /work/repo', " succeeded in 12ms:", " M a.txt", ""]
    for _ in range(failed):
        lines += ["exec", '"sh" -c "git status" in /work/repo',
                  "2026-01-01T00:00:00.000000Z ERROR codex_core::tools::router: error=exec_command failed: x",
                  " exited -1 in 0ms:"]
    for name in tools:
        lines += [f"mcp: {name} started", f"mcp: {name} (completed)"]
    return "\n".join(lines + ["codex", "No findings."]) + "\n"


def triage(*rows):
    """A triage note in the fixed shape. A row is (finding, reviewer label, final label, decision)."""
    text = ("# Round 1 triage: repo, 2026-01-01\n\n## Findings\n\n"
            "| # | Finding | Reviewer label | Final label | Decision | Evidence | Proof |\n"
            "|---|---|---|---|---|---|---|\n")
    for i, (finding, reviewer, final, decision) in enumerate(rows, 1):
        text += f"| {i} | {finding} | {reviewer} | {final} | {decision} | read `a \\| b` | a test |\n"
    return text + "\n## Requirement checklist\n\n| Criterion | State | Verified by | Basis |\n|---|---|---|---|\n"


def summary(**changes):
    """A summary that fits schema 1, with the given keys replaced."""
    data = {
        "schema": 1, "run": "20260101-000000", "plugin": "0.0.1", "mode": "uncommitted",
        "task_file": True, "report_only": False, "rounds_limit": 3, "web": "cached",
        "tools": "default", "task_hash_start": "aaa", "task_hash_end": "aaa",
        "verdict": "clean with unverified items",
        "rounds": [
            {"round": 1, "seconds": 300, "review_model": "test-model", "reviewed": True,
             "unverified": False, "fingerprint": PRINT,
             "facts": ["codex_cli=0.0.1", "sandbox=read-only", "shell_started=4", "shell_ran=4",
                       "shell_start_failed=0", "shell_usable=yes", "tool_calls=2",
                       "web_search_calls=2", "other_tool_calls=0",
                       "tool=codex_apps/search_service.web_run calls=2 lines=10,12"],
             "findings": [
                 {"tag": "criterion", "reviewer_label": "P1", "final_label": "P1", "decision": "fixed"},
                 {"tag": "none", "reviewer_label": "P2", "final_label": "P3",
                  "decision": "listed for the user"}]},
            {"round": 2, "seconds": 500, "review_model": "test-model", "reviewed": True,
             "unverified": True, "fingerprint": PRINT,
             "facts": ["codex_cli=0.0.1", "sandbox=read-only", "shell_started=3", "shell_ran=3",
                       "shell_start_failed=0", "shell_usable=yes", "tool_calls=0",
                       "web_search_calls=0", "other_tool_calls=0"],
             "findings": []}],
        "checklist": [{"criterion": 1, "state": "met", "verified_by": "reviewer"},
                      {"criterion": 2, "state": "met", "verified_by": "implementer"}],
    }
    data.update(changes)
    return data


class LoopStatsTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.folder, True)

    def put(self, name, text, mtime=None):
        path = os.path.join(self.folder, name)
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        if mtime is not None:
            os.utime(path, (mtime, mtime))
        return path

    def lines(self):
        return loop_stats.report(*loop_stats.collect(self.folder))

    def line(self, start):
        found = [line.strip() for line in self.lines() if line.strip().startswith(start)]
        self.assertEqual(len(found), 1, f"lines that start with {start!r}: {found}")
        return found[0]

    def test_a_run_with_a_valid_summary_is_read_from_it(self):
        self.put("20260101-000000-summary.json", json.dumps(summary()))
        runs, unusable = loop_stats.collect(self.folder)
        self.assertEqual(unusable, [])
        self.assertEqual([(run["source"], len(run["rounds"]), run["limit"], run["verdict"]) for run in runs],
                         [("summary", 2, 3, "clean with unverified items")])
        self.assertIn("Read from a summary file: 1.", self.line("Runs:"))
        self.assertEqual(self.line("Verdicts:"), "Verdicts: clean with unverified items: 1")

    def test_a_run_without_a_summary_is_read_from_its_files(self):
        self.put("r-round1-prompt.md", "prompt", mtime=1000)
        self.put("r-round1-codex.md", review("Reviewed. The tests were not run.",
                                             ("P1", "criterion 2", "Do the thing"), ("P2", "", "Guard it")),
                 mtime=1600)
        self.put("r-round1-codex.log", log(ran=3, failed=1, tools=("codex_apps/search_service.web_run", "x/y")))
        self.put("r-round1-claude.md", "Free-form notes from an earlier version.\n")
        runs, _ = loop_stats.collect(self.folder)
        entry = runs[0]["rounds"][0]
        self.assertEqual(runs[0]["source"], "files")
        self.assertEqual(entry["seconds"], 600)
        self.assertEqual([(f["tag"], f["reviewer_label"], f["decision"]) for f in entry["findings"]],
                         [("criterion", "P1", None), ("none", "P2", None)])
        self.assertTrue(entry["unverified"])
        self.assertEqual((entry["facts"]["shell_started"], entry["facts"]["shell_ran"],
                          entry["facts"]["shell_start_failed"], entry["facts"]["web_search_calls"],
                          entry["facts"]["other_tool_calls"]), (4, 3, 1, 1, 1))
        self.assertIn("Read from review files, logs, and triage notes: 1.", self.line("Runs:"))

    def test_a_triage_note_that_lists_other_findings_than_the_review_does_not_replace_them(self):
        self.put("r-round1-codex.md", review("Reviewed.", ("P1", "criterion 2", "Do the thing"),
                                             ("P2", "", "Guard it")))
        # The note calls the first finding P3 and leaves the second out.
        self.put("r-round1-claude.md", triage(
            ("(criterion 2) Does not do the thing", "P3", "P3", "listed for the user")))
        # A note beside a review that lists nothing, and a note without a review file,
        # are all there is to read: they are used as they are.
        self.put("s-round1-codex.md", review("Reviewed. No findings."))
        self.put("s-round1-claude.md", triage(("A defect the implementer found", "none", "P2", "fixed")))
        self.put("t-round1-claude.md", triage(("(handoff) No test", "P2", "P2", "fixed")))
        runs, _ = loop_stats.collect(self.folder)
        self.assertEqual([[(f["tag"], f["reviewer_label"], f["final_label"], f["decision"])
                           for f in run["rounds"][0]["findings"]] for run in runs],
                         [[("criterion", "P1", None, None), ("none", "P2", None, None)],
                          [("none", "none", "P2", "fixed")], [("handoff", "P2", "P2", "fixed")]])
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 1 of 3 (33%). "
                         "Runs without a reviewed first round, not counted: 0.")

    def test_a_triage_note_in_the_fixed_shape_gives_labels_and_decisions(self):
        self.put("r-round1-codex.md", review("Reviewed.", ("P1", "criterion 2", "Do the thing"),
                                             ("P2", "handoff", "The claimed test is missing"),
                                             ("P2", "", "Not a defect")))
        self.put("r-round1-claude.md", triage(
            ("(criterion 2) Does not do the thing", "P1", "P1", "fixed"),
            ("(handoff) The claimed test is missing", "P2", "P3", "listed for the user"),
            ("A defect the implementer found", "none", "P2", "`fixed`"),
            ("Not a defect", "P2", "P2", "rejected")))
        runs, _ = loop_stats.collect(self.folder)
        self.assertEqual([(f["tag"], f["reviewer_label"], f["final_label"], f["decision"])
                          for f in runs[0]["rounds"][0]["findings"]],
                         [("criterion", "P1", "P1", "fixed"), ("handoff", "P2", "P3", "listed for the user"),
                          ("none", "none", "P2", "fixed"), ("none", "P2", "P2", "rejected")])
        self.assertEqual(self.line("Implementer overrides:"), "Implementer overrides: 2")
        self.assertEqual(self.line("Decisions:"), "Decisions: fixed: 2, listed for the user: 1, rejected: 1")
        self.assertEqual(self.line("The reviewer's label and the final label:"),
                         "The reviewer's label and the final label: P1 to P1: 1, P2 to P2: 1, P2 to P3: 1")

    def test_a_summary_that_does_not_fit_is_named_and_the_run_read_from_files(self):
        self.put("r-summary.json", json.dumps(summary(run="r", verdict="clean")))
        self.put("r-round1-codex.md", review("Reviewed.", ("P2", "", "Guard it")))
        runs, unusable = loop_stats.collect(self.folder)
        self.assertEqual([run["source"] for run in runs], ["files"])
        self.assertEqual(unusable, [("r-summary.json", ["verdict: must be one of the five verdicts"])])
        self.assertEqual(self.line("Summary not used:"),
                         "Summary not used: r-summary.json: verdict: must be one of the five verdicts")

    def test_a_summary_that_is_not_json_is_named(self):
        self.put("r-summary.json", "{ not json")
        runs, unusable = loop_stats.collect(self.folder)
        self.assertEqual(runs, [])
        self.assertEqual(unusable[0][0], "r-summary.json")
        self.assertTrue(unusable[0][1][0].startswith("not JSON"))

    def test_every_field_of_the_schema_is_checked(self):
        cases = {
            "schema": 2, "run": 5, "plugin": None, "mode": "everything", "task_file": "yes",
            "report_only": 0, "rounds_limit": 0, "web": "on", "tools": "all", "task_hash_start": 1,
            "task_hash_end": None, "verdict": "clean", "rounds": {}, "checklist": "none",
        }
        for key, bad in cases.items():
            reasons = loop_stats.check_summary(summary(**{key: bad}))
            self.assertEqual([reason.split(":")[0] for reason in reasons], [key], f"{key}={bad!r}: {reasons}")
        self.assertEqual(loop_stats.check_summary(summary()), [])
        self.assertEqual(loop_stats.check_summary([summary()]), ["the file does not hold one object"])
        missing = summary()
        del missing["verdict"]
        self.assertEqual(loop_stats.check_summary(missing), ["verdict: must be one of the five verdicts"])

    def test_every_field_of_a_round_and_of_a_checklist_row_is_checked(self):
        for key, bad in {"round": 0, "seconds": -1, "review_model": 3, "unverified": "no",
                         "reviewed": "yes", "fingerprint": "abc", "facts": ["no equals sign"],
                         "findings": None}.items():
            data = summary()
            data["rounds"][1][key] = bad
            reasons = loop_stats.check_summary(data)
            self.assertEqual(reasons, [reason for reason in reasons if reason.startswith(f"round 2: {key}:")])
            self.assertEqual(len(reasons), 1, f"{key}={bad!r}: {reasons}")
        for key, bad in {"tag": "security", "reviewer_label": "P4", "final_label": "none",
                         "decision": "accepted"}.items():
            data = summary()
            data["rounds"][0]["findings"][0][key] = bad
            self.assertEqual([reason.split(":")[1].strip() for reason in loop_stats.check_summary(data)], [key])
        for key, bad in {"criterion": "one", "state": "done", "verified_by": "codex"}.items():
            data = summary()
            data["checklist"][0][key] = bad
            self.assertEqual([reason.split(":")[0] for reason in loop_stats.check_summary(data)], [key])
        for good in ("none", PRINT, " ".join("a" * 64 for _ in range(4))):
            data = summary()
            data["rounds"][0]["fingerprint"] = good
            self.assertEqual(loop_stats.check_summary(data), [], good)
        for bad in (PRINT + " " + "5" * 40, " ".join("A" * 40 for _ in range(4)), "1" * 40, ""):
            data = summary()
            data["rounds"][0]["fingerprint"] = bad
            self.assertEqual(len(loop_stats.check_summary(data)), 1, bad)
        data = summary()
        data["rounds"][1]["round"] = 1.5
        self.assertEqual(loop_stats.check_summary(data), ["round 2: round: must be a whole number, 1 or more"])
        data = summary()
        data["rounds"][1]["round"] = 1
        self.assertEqual(loop_stats.check_summary(data), ["round 2: round: appears twice"])
        data = summary()
        data["rounds"][0]["reviewed"] = False
        self.assertEqual(loop_stats.check_summary(data),
                         ["round 1: findings: must be empty when reviewed is false"])
        data = summary()
        data["rounds"][0] = "round one"
        self.assertTrue(all(reason.startswith("round 1: ") for reason in loop_stats.check_summary(data)))
        self.assertTrue(loop_stats.check_summary(data))

    def test_the_measures(self):
        # Run a: three rounds of three allowed, findings 2, then 3, then 1.
        a = summary(run="a", task_hash_end="bbb", verdict="open findings")
        a["rounds"] = [
            dict(a["rounds"][0]),
            {**a["rounds"][1], "findings": [
                {"tag": "handoff", "reviewer_label": "P2", "final_label": "P2", "decision": "fixed"},
                {"tag": "beyond request", "reviewer_label": "P2", "final_label": "P2", "decision": "rejected"},
                {"tag": "none", "reviewer_label": "P0", "final_label": "P0", "decision": "fixed"}]},
            {"round": 3, "seconds": 100, "review_model": "test-model", "reviewed": True,
             "unverified": False, "fingerprint": "none",
             "facts": ["codex_cli=0.0.2", "sandbox=workspace-write", "shell_started=2", "shell_ran=1",
                       "shell_start_failed=1", "shell_usable=yes", "tool_calls=1", "web_search_calls=0",
                       "other_tool_calls=1", "tool=node_repl/js calls=1 lines=7"],
             "findings": [{"tag": "none", "reviewer_label": "P1", "final_label": "P1",
                           "decision": "not fixed"}]}]
        # Run b: one clean round that named something unverified.
        b = summary(run="b", verdict="verified")
        b["rounds"] = [{**b["rounds"][1], "round": 1, "seconds": 200}]
        # Run c: one clean round, nothing unverified, and a P3 that does not count as must-fix.
        c = summary(run="c", verdict="verified", rounds_limit=1)
        c["rounds"] = [{**c["rounds"][1], "round": 1, "seconds": 900, "unverified": False,
                        "findings": [{"tag": "none", "reviewer_label": "P3", "final_label": "P3",
                                      "decision": "listed for the user"}]}]
        for data in (a, b, c):
            self.put(f"{data['run']}-summary.json", json.dumps(data))
        want = [
            "Rounds without a usable review: 0 of 5. They count in no figure about findings.",
            "Rounds per run: 1 round(s): 2 run(s), 3 round(s): 1 run(s)",
            "Runs whose first round had no must-fix finding: 2 of 3 (67%). "
            "Runs without a reviewed first round, not counted: 0.",
            "Must-fix findings by round: round 1: 2 in 3 round(s), round 2: 3 in 1 round(s), round 3: 1 in 1 round(s)",
            "A round after a round with must-fix findings reported more of them: 1 of 2 (50%)",
            "Runs that used every allowed round and still had must-fix findings in the last: 1 of 2 (50%). "
            "The limit is known only from summary files.",
            "Findings: 7. By the reviewer's label: P0: 1, P1: 2, P2: 3, P3: 1",
            "By tag: criterion: 1, beyond request: 1, handoff: 1, none: 4",
            "Decisions: fixed: 3, not fixed: 1, listed for the user: 2, rejected: 1",
            "Implementer overrides: 2",
            "Rounds with a readable log: 5 of 5",
            "Shell commands started: 15, failed to start: 1, rounds in which none ran: 0",
            "Web searches: 2. Other tool calls: 1. Tool calls by server: codex_apps: 2, node_repl: 1",
            "Sandbox line: read-only: 4, workspace-write: 1",
            "Codex CLI version: 0.0.1: 4, 0.0.2: 1",
            "Rounds without a must-fix finding that named something not run or not verified: 1 of 2 (50%)",
            "Duration of a round in seconds: shortest 100, median 300, longest 900, from 5 round(s)",
            "Verdicts: verified: 2, open findings: 1",
            "Runs whose request or criteria differ between the start and the end: 1",
        ]
        got = [line.strip() for line in self.lines()]
        for line in want:
            self.assertIn(line, got)

    def test_the_template_the_loop_copies_fits_the_schema_once_it_is_filled_in(self):
        path = os.path.join(HERE, "..", "plugins", "codex-review-loop", "skills", "codex-loop",
                            "summary-template.json")
        with open(path, encoding="utf-8") as handle:
            template = json.load(handle)
        # As it stands, with its "<...>" texts, it must not pass for a summary.
        self.assertTrue(loop_stats.check_summary(template))

        def fill(node):
            """Each "<a, b, or c>" becomes its first choice; any other text stays text."""
            if isinstance(node, dict):
                return {key: fill(value) for key, value in node.items()}
            if isinstance(node, list):
                if node and isinstance(node[0], str) and "round-facts.sh" in node[0]:
                    return ["shell_started=1", "shell_ran=1", "shell_start_failed=0", "shell_usable=yes",
                            "tool_calls=0", "web_search_calls=0", "other_tool_calls=0"]
                return [fill(value) for value in node]
            if isinstance(node, str) and node.startswith("<"):
                return "none" if "fingerprint" in node else node.strip("<>").split(",")[0].strip()
            return node

        self.assertEqual(loop_stats.check_summary(fill(template)), [])

    def test_wording_that_counts_as_unverified(self):
        for text, expected in (("Reviewed; the test suites were not run.", True),
                               ("Criterion 3 is not verifiable from the code.", True),
                               ("The live check remains unverified.", True),
                               ("I could not start the server.", True),
                               ("Reviewed everything; all checks passed.", False)):
            self.put("r-round1-codex.md", review(text))
            self.assertIs(loop_stats.collect(self.folder)[0][0]["rounds"][0]["unverified"], expected, text)

    def test_tags(self):
        self.assertEqual([loop_stats.tag_of(text) for text in
                          ("criterion 3", "Criterion 12", "beyond request", "handoff", "nit", "", None)],
                         ["criterion", "criterion", "beyond request", "handoff", "none", "none", "none"])

    def test_an_escaped_bar_does_not_split_a_cell(self):
        # The bar inside the finding's text is escaped, as a table cell needs it.
        rows = loop_stats.triage_rows(triage(("(handoff) Reads `a \\| b` wrongly", "P1", "P2", "fixed")))
        self.assertEqual(rows, [{"tag": "handoff", "reviewer_label": "P1", "final_label": "P2", "decision": "fixed"}])

    def test_a_triage_note_that_says_none_is_a_reviewed_round_without_findings(self):
        # The form the triage template asks for when the review reported no finding.
        clean = "# Round 1 triage: repo, 2026-01-01\n\n## Findings\n\nNone.\n\n## Requirement checklist\n"
        self.assertEqual(loop_stats.triage_rows(clean), [])
        self.assertEqual(loop_stats.triage_rows(clean.replace("\n\nNone.\n", "\nNone.  \n")), [])
        # The review file was not kept: the note alone shows that the round was clean.
        self.put("r-round1-claude.md", clean)
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 0 of 1. They count in no figure about findings.")
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 1 of 1 (100%). "
                         "Runs without a reviewed first round, not counted: 0.")

    def test_a_triage_note_in_neither_form_leaves_the_round_unknown(self):
        notes = ("Free-form notes from an earlier version.\n",
                 "## Findings\n\nNo finding.\n",
                 "## Findings\n\nNone. The rest is in round 2.\n",
                 "## Rejected findings\n\nNone.\n",
                 "## Findings\n\nSee the review.\n\nNone.\n")
        for number, note in enumerate(notes, 1):
            self.assertIsNone(loop_stats.triage_rows(note), note)
            self.put(f"r-round{number}-claude.md", note)
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 5 of 5. They count in no figure about findings.")

    def test_a_triage_note_without_rows_does_not_hide_what_the_review_found(self):
        found = review("Reviewed.", ("P1", "criterion 2", "Do the thing"))
        # Round 1: the note says "None.". Round 2: the note has the table and no row.
        self.put("r-round1-codex.md", found)
        self.put("r-round1-claude.md", "## Findings\n\nNone.\n")
        self.put("r-round2-codex.md", found)
        self.put("r-round2-claude.md", triage())
        self.assertEqual(self.line("Must-fix findings by round:"),
                         "Must-fix findings by round: round 1: 1 in 1 round(s), round 2: 1 in 1 round(s)")

    def test_which_rounds_count_for_the_first_round_and_for_reporting_more(self):
        def run(name, *must_fix_per_round):
            data = summary(run=name)
            data["rounds"] = [
                {**data["rounds"][1], "round": i + 1, "findings": [
                    {"tag": "none", "reviewer_label": "P1", "final_label": "P1", "decision": "fixed"}] * count}
                for i, count in enumerate(must_fix_per_round)]
            self.put(f"{name}-summary.json", json.dumps(data))

        run("x", 2, 0)
        run("y", 0, 2)
        run("z", 1, 0)
        # Only y starts clean. A round after a clean round is not "a round after a round
        # with findings", so y's second round is not counted there.
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 1 of 3 (33%). "
                         "Runs without a reviewed first round, not counted: 0.")
        self.assertEqual(self.line("A round after a round with must-fix findings"),
                         "A round after a round with must-fix findings reported more of them: 0 of 2 (0%)")

    def test_the_log_is_read_like_the_loop_reads_it(self):
        bash = shutil.which("bash")
        if not bash or not os.path.isfile(ROUND_FACTS):
            self.skipTest("the log reader against round-facts.sh: no bash, or the script is not here")
        for text in (log(ran=3, failed=2, tools=("codex_apps/search_service.web_run", "x/y", "x/y")),
                     log(ran=0, failed=1), log(ran=1, echoed=False), log(ran=2).replace("\n", "\r\n")):
            path = self.put("one-round1-codex.log", text)
            printed = subprocess.run([bash, ROUND_FACTS, path], capture_output=True, text=True, check=True).stdout
            script = loop_stats.facts_of_lines(printed.splitlines())
            ours = loop_stats.facts_of_log(text)
            for key in ("codex_cli", "sandbox", "shell_started", "shell_ran", "shell_start_failed",
                        "shell_usable", "tool_calls", "web_search_calls", "other_tool_calls", "tools"):
                self.assertEqual(ours[key], script[key], key)
        self.assertIsNone(loop_stats.facts_of_log("not a log\n"))

    def test_incomplete_and_odd_files_do_not_stop_the_reading(self):
        # Rounds sort by number, a run's name may hold dots and spaces, a round may lack
        # its review, and a file may hold bytes that are not text.
        self.put("my run.v2-round10-codex.md", review("Reviewed.", ("P2", "", "Late")))
        self.put("my run.v2-round2-codex.md", review("Reviewed.", ("P1", "", "Early")))
        self.put("my run.v2-round3-prompt.md", "a prompt whose review never came")
        with open(os.path.join(self.folder, "my run.v2-round2-codex.log"), "wb") as handle:
            handle.write(log(ran=1).encode("utf-8") + b"odd byte \xff here\n")
        with open(os.path.join(self.folder, "other-round1-codex.md"), "wb") as handle:
            handle.write(b"Reviewed \xff.\n\n- [P1] Something \xe2\x80\x94 a.py:1-2\n")
        self.put("notes.txt", "not a file of the loop")
        runs, unusable = loop_stats.collect(self.folder)
        self.assertEqual(unusable, [])
        self.assertEqual([run["run"] for run in runs], ["my run.v2", "other"])
        first = runs[0]["rounds"]
        self.assertEqual([(entry["round"], entry["reviewed"], [f["reviewer_label"] for f in entry["findings"]])
                          for entry in first], [(2, True, ["P1"]), (3, False, []), (10, True, ["P2"])])
        self.assertEqual(first[0]["facts"]["shell_ran"], 1)
        self.assertEqual((first[1]["unverified"], first[1]["facts"], first[1]["seconds"]), (None, None, None))
        self.assertEqual(len(runs[1]["rounds"][0]["findings"]), 1)
        self.assertIn("Runs: 2, with 4 rounds.", self.line("Runs:"))
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 1 of 4. They count in no figure about findings.")
        # Rounds 2 and 10 keep their numbers, and they are not one after the other.
        self.assertEqual(self.line("Must-fix findings by round:"),
                         "Must-fix findings by round: round 1: 1 in 1 round(s), round 2: 1 in 1 round(s), "
                         "round 10: 1 in 1 round(s)")
        self.assertEqual(self.line("A round after a round with must-fix findings"),
                         "A round after a round with must-fix findings reported more of them: 0 of 0")
        # Only the other run has a reviewed round 1.
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 0 of 1 (0%). "
                         "Runs without a reviewed first round, not counted: 1.")

    def test_a_round_without_a_review_is_not_a_clean_round(self):
        # Codex stopped before it wrote a review: the prompt and the log are all there is.
        self.put("r-round1-prompt.md", "prompt", mtime=1000)
        self.put("r-round1-codex.log", log(ran=0, failed=2))
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 1 of 1. They count in no figure about findings.")
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 0 of 0. "
                         "Runs without a reviewed first round, not counted: 1.")
        self.assertEqual(self.line("Must-fix findings by round:"), "Must-fix findings by round: none")
        self.assertEqual(self.line("Rounds without a must-fix finding that named"),
                         "Rounds without a must-fix finding that named something not run or not verified: 0 of 0")
        # What the log shows is still counted.
        self.assertEqual(self.line("Shell commands started:"),
                         "Shell commands started: 2, failed to start: 2, rounds in which none ran: 1")

    def test_a_review_written_when_no_sandboxed_command_ran_is_not_a_usable_review(self):
        # The loop stops such a review as failed, whatever it says. In run c it claims a
        # clean round; in run d it lists a finding, and a triage note beside it has a row.
        self.put("c-round1-codex.md", review("Reviewed. No findings."))
        self.put("c-round1-codex.log", log(ran=0, failed=2))
        self.put("d-round1-codex.md", review("Reviewed.", ("P1", "", "Do the thing")))
        self.put("d-round1-codex.log", log(ran=0, failed=1))
        self.put("d-round1-claude.md", triage(("Do the thing", "P1", "P1", "fixed")))
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 2 of 2. They count in no figure about findings.")
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 0 of 0. "
                         "Runs without a reviewed first round, not counted: 2.")
        self.assertEqual(self.line("Must-fix findings by round:"), "Must-fix findings by round: none")
        self.assertEqual(self.line("Findings:"), "Findings: 0. By the reviewer's label: none")
        # A review beside a log in which a command ran, and one without a log, are usable.
        self.put("e-round1-codex.md", review("Reviewed. No findings."))
        self.put("e-round1-codex.log", log(ran=1, failed=2))
        self.put("f-round1-codex.md", review("Reviewed. No findings."))
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 2 of 4. They count in no figure about findings.")
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 2 of 2 (100%). "
                         "Runs without a reviewed first round, not counted: 2.")

    def test_a_review_beside_a_log_that_cannot_be_read_is_not_a_usable_review(self):
        # The loop stops a round whose facts it cannot read. A log that is empty, cut off
        # in its header, or no log at all leaves the round unknown, whatever the review says.
        for run, text in (("a", ""), ("b", "OpenAI Codex v0.0.1\n--------\nworkdir: /work/repo\n"),
                          ("c", "not a log\n")):
            self.put(f"{run}-round1-codex.md", review("Reviewed. No findings."))
            self.put(f"{run}-round1-codex.log", text)
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 3 of 3. They count in no figure about findings.")
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 0 of 0. "
                         "Runs without a reviewed first round, not counted: 3.")
        self.assertEqual(self.line("Rounds with a readable log:"), "Rounds with a readable log: 0 of 3")

    def test_a_number_in_a_summary_is_a_finite_one(self):
        text = json.dumps(summary(run="n"))
        for bad in ("1e400", "Infinity", "NaN", "1" + "0" * 400):
            for field, at, reason in (
                    ("seconds", '"seconds": 300', "round 1: seconds: must be a number, 0 or more"),
                    ("rounds_limit", '"rounds_limit": 3', "rounds_limit: must be a number, 1 or more"),
                    ("criterion", '"criterion": 1', "criterion: must be a number, 1 or more")):
                self.assertEqual(text.count(at), 1, at)
                data = json.loads(text.replace(at, f'"{field}": {bad}'))
                self.assertEqual(loop_stats.check_summary(data), [reason], f"{field}: {bad}")
        # The summary is named, the run is read from its files, and the report is printed.
        self.put("n-summary.json", text.replace('"seconds": 300', '"seconds": 1e400'))
        self.put("n-round1-codex.md", review("Reviewed.", ("P2", "", "Guard it")))
        self.assertEqual(self.line("Summary not used:"),
                         "Summary not used: n-summary.json: round 1: seconds: must be a number, 0 or more")
        self.assertIn("Read from review files, logs, and triage notes: 1.", self.line("Runs:"))

    def test_input_that_cannot_be_read_is_named_or_left_out_and_does_not_stop_the_report(self):
        # A summary nested deeper than some interpreters read, beside a run that can be
        # read. An interpreter that does read it finds no object in it.
        self.put("d-summary.json", "[" * 100000 + "]" * 100000)
        self.put("g-summary.json", json.dumps(summary(run="g")))
        # A folder where a review, a log, and a summary are expected.
        for name in ("h-round1-codex.md", "h-round1-codex.log", "i-summary.json"):
            os.mkdir(os.path.join(self.folder, name))
        runs, unusable = loop_stats.collect(self.folder)
        self.assertEqual([name for name, _ in unusable], ["d-summary.json", "i-summary.json"])
        self.assertIn(unusable[0][1], (["nested too deep to read"], ["the file does not hold one object"]))
        self.assertTrue(unusable[1][1][0].startswith("not JSON"), unusable[1][1])
        self.assertEqual([(run["run"], [entry["reviewed"] for entry in run["rounds"]]) for run in runs],
                         [("g", [True, True]), ("h", [False])])
        self.assertIn("Runs: 2, with 3 rounds.", self.line("Runs:"))

    def test_a_summary_the_interpreter_refuses_to_read_is_named(self):
        # How deep an interpreter reads differs, so here the reader itself refuses.
        self.put("d-summary.json", json.dumps(summary(run="d")))
        self.put("d-round1-codex.md", review("Reviewed. No findings."))
        with unittest.mock.patch.object(loop_stats.json, "loads", side_effect=RecursionError):
            runs, unusable = loop_stats.collect(self.folder)
        self.assertEqual(unusable, [("d-summary.json", ["nested too deep to read"])])
        self.assertEqual([run["run"] for run in runs], ["d"])

    def test_only_the_counts_among_the_facts_are_numbers(self):
        # A sandbox line that happens to be a number is a word like any other.
        other = summary(run="p")
        other["rounds"] = [{**other["rounds"][1], "round": 1, "facts": [
            line.replace("sandbox=read-only", "sandbox=123") for line in other["rounds"][1]["facts"]]}]
        self.put("p-summary.json", json.dumps(other))
        self.put("q-summary.json", json.dumps(summary(run="q")))
        self.assertEqual(self.line("Sandbox line:"), "Sandbox line: 123: 1, read-only: 2")

    def test_the_median_duration_of_an_even_number_of_rounds(self):
        def run(name, *seconds):
            data = summary(run=name)
            data["rounds"] = [{**data["rounds"][1], "round": i + 1, "seconds": value}
                              for i, value in enumerate(seconds)]
            return self.put(f"{name}-summary.json", json.dumps(data))

        first = run("e", 100, 300)
        self.assertEqual(self.line("Duration of a round"),
                         "Duration of a round in seconds: shortest 100, median 200, longest 300, from 2 round(s)")
        os.remove(first)
        # Two durations whose sum is too large a number: the report is still printed.
        run("f", 1e308, 1e308)
        large = round(1e308)
        self.assertEqual(self.line("Duration of a round"),
                         f"Duration of a round in seconds: shortest {large}, median {large}, longest {large}, "
                         "from 2 round(s)")

    def test_the_default_folder_of_a_repository_whose_name_has_another_letter(self):
        git = shutil.which("git")
        if not git:
            self.skipTest("the default folder of a repository named with another letter: no git")
        repo = os.path.join(self.folder, "café")
        try:
            os.mkdir(repo)
        except (OSError, UnicodeError):
            self.skipTest("the default folder of a repository named with another letter: no such folder name here")
        subprocess.run([git, "init", "-q", repo], check=True, capture_output=True)
        # A child that reads text in the encoding of the system, as Python did before 3.15.
        code = ("import importlib.util, os, sys\n"
                "spec = importlib.util.spec_from_file_location('loop_stats', sys.argv[1])\n"
                "module = importlib.util.module_from_spec(spec)\n"
                "spec.loader.exec_module(module)\n"
                "sys.stdout.buffer.write(os.fsencode(module.default_folder()))\n")
        printed = subprocess.run([sys.executable, "-X", "utf8=0", "-B", "-I", "-c", code,
                                  os.path.join(HERE, "loop_stats.py")], cwd=repo, capture_output=True,
                                 check=True).stdout
        self.assertEqual(os.path.basename(os.fsdecode(printed)), "café")

    def test_the_default_folder_is_under_the_home_folder_of_the_loop(self):
        git = shutil.which("git")
        if not git:
            self.skipTest("the default folder under the home folder of the loop: no git")
        repo, home = os.path.join(self.folder, "myrepo"), os.path.join(self.folder, "another home")
        os.mkdir(repo)
        os.mkdir(home)
        subprocess.run([git, "init", "-q", repo], check=True, capture_output=True)
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(repo)
        # The loop writes under HOME, which need not be the profile folder of the system.
        with unittest.mock.patch.dict(os.environ, {"HOME": home}):
            self.assertEqual(loop_stats.default_folder(),
                             os.path.join(home, ".claude", "codex-reviews", "myrepo"))
        # Without HOME, the home folder of the system is used.
        with unittest.mock.patch.dict(os.environ):
            os.environ.pop("HOME", None)
            self.assertEqual(loop_stats.default_folder(),
                             os.path.join(os.path.expanduser("~"), ".claude", "codex-reviews", "myrepo"))
        # Git Bash names a drive /c/...; Python for Windows needs C:/...
        for value, on_windows in (("/c/work/home", "C:/work/home"), ("/d", "D:/")):
            with unittest.mock.patch.dict(os.environ, {"HOME": value}):
                self.assertEqual(loop_stats.home_folder(), on_windows if os.name == "nt" else value)

    def test_a_time_or_a_folder_that_cannot_be_read_does_not_stop_the_report_with_a_trace(self):
        self.put("r-round1-prompt.md", "prompt", mtime=1000)
        self.put("r-round1-codex.md", review("Reviewed. No findings."), mtime=1600)
        # The time of a file that went away, or of a link to nowhere, cannot be read.
        with unittest.mock.patch.object(loop_stats.os.path, "getmtime", side_effect=OSError("gone")):
            runs, _ = loop_stats.collect(self.folder)
        self.assertEqual([(entry["reviewed"], entry["seconds"]) for entry in runs[0]["rounds"]], [(True, None)])
        self.assertEqual([line.strip() for line in loop_stats.report(runs, []) if "uration" in line],
                         ["No duration is known."])
        # A folder that cannot be listed ends the run with a message.
        errors = io.StringIO()
        with unittest.mock.patch.object(loop_stats.os, "listdir", side_effect=PermissionError("denied")), \
                contextlib.redirect_stderr(errors), contextlib.redirect_stdout(io.StringIO()):
            code = loop_stats.main(["loop_stats.py", self.folder])
        self.assertEqual(code, 2)
        self.assertIn("loop_stats: cannot read", errors.getvalue())

    def test_a_terminal_that_cannot_show_a_character_still_gets_the_figures(self):
        data = summary(run="o")
        data["rounds"][0]["facts"][1] = "sandbox=réad-only"
        self.put("o-summary.json", json.dumps(data))
        raw = io.BytesIO()
        with contextlib.redirect_stdout(io.TextIOWrapper(raw, encoding="ascii", newline="\n")) as out:
            code = loop_stats.main(["loop_stats.py", self.folder])
            out.flush()
        self.assertEqual(code, 0)
        self.assertIn(b"Sandbox line: read-only: 1, r?ad-only: 1", raw.getvalue())

    def test_a_summary_cannot_call_a_round_reviewed_in_which_no_sandboxed_command_ran(self):
        none_ran = ["codex_cli=0.0.1", "sandbox=read-only", "shell_started=2", "shell_ran=0",
                    "shell_start_failed=2", "shell_usable=no", "tool_calls=0", "web_search_calls=0",
                    "other_tool_calls=0"]
        refused = ["round 2: reviewed: must be false when no sandboxed command ran"]
        data = summary(run="s", verdict="review failed")
        data["rounds"][1]["facts"] = none_ran
        self.assertEqual(loop_stats.check_summary(data), refused)
        # The count decides, with or without the line that says the shell was not usable.
        data["rounds"][1]["facts"] = [line for line in none_ran if line != "shell_usable=no"]
        self.assertEqual(loop_stats.check_summary(data), refused)
        # The summary is named with the reason, and the run is read from its files.
        self.put("s-summary.json", json.dumps(data))
        self.put("s-round2-codex.md", review("Reviewed. No findings."))
        self.put("s-round2-codex.log", log(ran=0, failed=2))
        runs, unusable = loop_stats.collect(self.folder)
        self.assertEqual(unusable, [("s-summary.json", refused)])
        self.assertEqual([(run["source"], [entry["reviewed"] for entry in run["rounds"]]) for run in runs],
                         [("files", [False])])
        # With reviewed false the summary fits. The round is counted with the rounds
        # without a usable review, and its log figures still count.
        data["rounds"][1]["facts"] = none_ran
        data["rounds"][1]["reviewed"] = False
        self.assertEqual(loop_stats.check_summary(data), [])
        self.put("s-summary.json", json.dumps(data))
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 1 of 2. They count in no figure about findings.")
        self.assertEqual(self.line("Shell commands started:"),
                         "Shell commands started: 6, failed to start: 2, rounds in which none ran: 1")
        # A run that ends with such a round has one verdict.
        for verdict in ("verified", "clean with unverified items", "fixes not re-reviewed", "open findings"):
            data["verdict"] = verdict
            self.assertEqual(loop_stats.check_summary(data),
                             ["verdict: must be review failed when the last round gave no usable review"])
        # The last round is the one with the highest number, wherever it is listed.
        data["rounds"].reverse()
        self.assertEqual(loop_stats.check_summary(data),
                         ["verdict: must be review failed when the last round gave no usable review"])
        data["rounds"].reverse()
        # An earlier round like it does not decide the verdict.
        data["rounds"][0], data["rounds"][1] = ({**data["rounds"][1], "round": 1},
                                                {**data["rounds"][0], "round": 2, "findings": []})
        self.assertEqual(loop_stats.check_summary(data), [])

    def test_a_list_of_facts_in_a_summary_is_empty_or_complete(self):
        good = summary()["rounds"][0]["facts"]

        def reasons(change, **fields):
            data = summary()
            data["rounds"][0].update(fields)
            data["rounds"][0]["facts"] = change(good)
            return loop_stats.check_summary(data)

        def without(key):
            return lambda facts: [line for line in facts if not line.startswith(key + "=")]

        def with_line(new):
            return lambda facts: [new if line.startswith(new.split("=")[0] + "=") else line for line in facts]

        # Every count that the loop prints for a log it can read must be there, as a number.
        for key in ("shell_started", "shell_ran", "shell_start_failed", "tool_calls", "web_search_calls",
                    "other_tool_calls"):
            self.assertEqual(reasons(without(key)), [f"round 1: facts: must hold a whole number for {key}"])
        for bad in ("shell_ran=many", "shell_ran=-1", "shell_ran=1.5", "shell_ran=", "shell_ran=²",
                    "shell_ran=" + "1" * 30):
            self.assertEqual(reasons(with_line(bad)), ["round 1: facts: must hold a whole number for shell_ran"],
                             bad)
        self.assertEqual(reasons(lambda facts: ["codex_cli=0.0.1"]),
                         ["round 1: facts: must hold a whole number for shell_started, shell_ran, "
                          "shell_start_failed, tool_calls, web_search_calls, other_tool_calls"])
        # The line that says whether the shell was usable must agree with the count.
        disagree = ["round 1: facts: shell_usable must be yes when shell_ran is above 0, and no otherwise"]
        self.assertEqual(reasons(with_line("shell_usable=no")), disagree)
        self.assertEqual(reasons(without("shell_usable")), disagree)
        self.assertEqual(reasons(lambda facts: with_line("shell_usable=yes")(with_line("shell_ran=0")(facts)),
                                 reviewed=False, findings=[]), disagree)
        # The lines about tools must be readable, and add up to the counts of tool calls.
        tools = ["round 1: facts: the tool lines and the counts of tool calls must agree"]
        self.assertEqual(reasons(with_line("tool=codex_apps/search_service.web_run calls=1 lines=10")), tools)
        self.assertEqual(reasons(without("tool")), tools)
        self.assertEqual(reasons(with_line("other_tool_calls=1")), tools)
        self.assertEqual(reasons(lambda facts: without("tool")(with_line("tool_calls=0")(
            with_line("web_search_calls=0")(facts))) + ["tool=x/y calls=many lines=3"]), tools)
        # Each count follows from the tool lines: two web searches cannot be recorded as
        # two other calls, and a tool has one line.
        self.assertEqual(reasons(lambda facts: with_line("other_tool_calls=2")(
            with_line("web_search_calls=0")(facts))), tools)
        self.assertEqual(reasons(with_line("web_search_calls=1")), tools)
        self.assertEqual(reasons(with_line("tool_calls=5")), tools)
        self.assertEqual(reasons(lambda facts: facts + [facts[-1]]), tools)
        # An empty list stands for a log that could not be read. The loop stops such a
        # round as failed, so it cannot be a reviewed one.
        self.assertEqual(reasons(lambda facts: []), ["round 1: reviewed: must be false when the round has no facts"])
        self.assertEqual(reasons(lambda facts: [], reviewed=False, findings=[]), [])
        self.assertEqual(reasons(lambda facts: facts), [])

    def test_a_line_like_a_finding_in_the_summary_or_in_a_body_is_not_a_finding(self):
        # Above the line that starts the list nothing is a finding: not a bullet, and not
        # what follows a block that never closes. Below it, the lines of a body are
        # indented: a fenced example, an item of a list, a block without an end.
        above = ("Reviewed. Two things from the last round:\n"
                 "- [P1] The first is fixed.\n\n"
                 "```\nan example without an end\n")
        one = ("- [P3] Name the format — src/app.py:1-2\n"
               "  The note should show the format, for example:\n"
               "  ```\n  - [P1] Example finding\n  ```\n"
               "  - [P0] and an item of a list in the body\n")
        more = ("\n- [P2] (handoff) Guard it — src/app.py:3-4\n  ~~~\n  another example without an end\n"
                "\n- [P1] Do the thing — src/app.py:5-6\n  What goes wrong.\n"
                "\n- [P3] Mind the gap — src/app.py:7-8\n  ~~~\n  and one more\n")
        for start in ("Full review comments:", "Full review comments: "):
            self.assertEqual(loop_stats.findings_of(above + start + "\n\n" + one + more),
                             ([("P3", None), ("P2", "handoff"), ("P1", None), ("P3", None)], above[:-1]),
                             repr(start))
        # One finding that quotes another is one finding, and a P3 leaves the round clean.
        self.put("q-round1-codex.md", "Reviewed.\n\nFull review comments:\n\n" + one)
        self.assertEqual(self.line("Findings:"), "Findings: 1. By the reviewer's label: P3: 1")
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 1 of 1 (100%). "
                         "Runs without a reviewed first round, not counted: 0.")

    def test_in_a_review_without_the_line_that_starts_the_list_a_fenced_bullet_is_an_example(self):
        # One block for each rule of a fenced block, and a line that starts with a code
        # span and opens none.
        blocks = ("Reviewed. Earlier reports had these shapes:\n\n"
                  "```\n~~~\n- [P1] other mark\n```\n\n"
                  "```\n``` text\n- [P1] text after the run\n```\n\n"
                  "````\n```\n- [P1] shorter run\n````\n\n"
                  "```\n- [P1] closed by a longer run\n`````\n\n"
                  "~~~\n- [P1] tildes\n~~~\n\n"
                  "```value``` shows the form.\n\n")
        real = "- [P3] Name the format — src/app.py:1-2\n  What goes wrong.\n"
        self.assertEqual(loop_stats.findings_of(blocks + real), ([("P3", None)], blocks[:-1]))
        # A block that never closes is no block: the bullets below its first line count.
        self.assertEqual(loop_stats.findings_of("Reviewed.\n\n```\n- [P2] One\n\n- [P1] Two\n")[0],
                         [("P2", None), ("P1", None)])

    def test_a_label_in_a_triage_table_may_stand_in_backticks_and_must_be_a_label(self):
        self.put("r-round1-claude.md", triage(("(criterion 1) Does not do the thing", "`P1`", "`P1`", "`fixed`")))
        runs, _ = loop_stats.collect(self.folder)
        self.assertEqual([(f["reviewer_label"], f["final_label"], f["decision"])
                          for f in runs[0]["rounds"][0]["findings"]], [("P1", "P1", "fixed")])
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 0 of 1 (0%). "
                         "Runs without a reviewed first round, not counted: 0.")
        # A row whose label of the reviewer cannot be read cannot be counted: the note is
        # not in the fixed shape, and without a review file the round is unknown.
        for label in ("high", "P4", "P1 or P2", ""):
            self.assertIsNone(loop_stats.triage_rows(triage(("A finding", label, "P1", "fixed"))), label)
        self.put("u-round1-claude.md", triage(("A finding", "high", "P1", "fixed")))
        self.assertEqual(self.line("Rounds without a usable review:"),
                         "Rounds without a usable review: 1 of 2. They count in no figure about findings.")
        # A row counts whatever its first cell holds, and so does a row cut short after
        # the label of the reviewer. A row cut short before it makes the note unreadable.
        table = triage().split("\n\n## Requirement checklist")[0]
        rows = loop_stats.triage_rows(table + "\n|  | (handoff) No test | P2 | P2 | fixed | read | a test |\n"
                                              "| 2 | Cut short | P1 |\n")
        self.assertEqual([(row["tag"], row["reviewer_label"], row["decision"]) for row in rows],
                         [("handoff", "P2", "fixed"), ("none", "P1", "")])
        self.assertIsNone(loop_stats.triage_rows(table + "\n| 1 | Cut short before the label |\n"))

    def test_a_failed_run_in_a_summary_is_not_a_clean_run_and_has_no_log_figures(self):
        data = summary(run="f", verdict="review failed", rounds_limit=1)
        data["rounds"] = [{"round": 1, "seconds": 40, "review_model": "test-model", "reviewed": False,
                           "unverified": False, "fingerprint": "none", "facts": [], "findings": []}]
        self.put("f-summary.json", json.dumps(data))
        runs, unusable = loop_stats.collect(self.folder)
        self.assertEqual(unusable, [])
        self.assertIsNone(runs[0]["rounds"][0]["facts"])
        self.assertEqual(self.line("Runs whose first round"),
                         "Runs whose first round had no must-fix finding: 0 of 0. "
                         "Runs without a reviewed first round, not counted: 1.")
        self.assertEqual(self.line("Runs that used every allowed round"),
                         "Runs that used every allowed round and still had must-fix findings in the last: 0 of 0. "
                         "The limit is known only from summary files.")
        self.assertEqual(self.line("Rounds with a readable log:"), "Rounds with a readable log: 0 of 1")
        self.assertEqual(self.line("Duration of a round"),
                         "Duration of a round in seconds: shortest 40, median 40, longest 40, from 1 round(s)")

    def test_a_summary_without_any_round_is_read(self):
        self.put("e-summary.json", json.dumps(summary(run="e", verdict="review failed", rounds=[])))
        self.assertEqual(self.lines()[2:], ["Runs: 1, with 0 rounds. Read from a summary file: 1. "
                                            "Read from review files, logs, and triage notes: 0.",
                                            "No review round found."])
        # Beside a run that has rounds, it is one more run and adds no round.
        self.put("h-summary.json", json.dumps(summary(run="h")))
        self.assertIn("Runs: 2, with 2 rounds.", self.line("Runs:"))
        self.assertEqual(self.line("Rounds per run:"), "Rounds per run: 0 round(s): 1 run(s), 2 round(s): 1 run(s)")

    def test_only_rounds_with_neighbouring_numbers_are_compared(self):
        data = summary(run="g", rounds_limit=5)
        one = {"tag": "none", "reviewer_label": "P1", "final_label": "P1", "decision": "fixed"}
        data["rounds"] = [{**data["rounds"][1], "round": number, "findings": [one] * count}
                          for number, count in ((1, 1), (2, 3), (4, 5), (5, 2))]
        self.put("g-summary.json", json.dumps(data))
        # Rounds 1 to 2 and 4 to 5 are compared; 2 to 4 is not, because round 3 is missing.
        self.assertEqual(self.line("A round after a round with must-fix findings"),
                         "A round after a round with must-fix findings reported more of them: 1 of 2 (50%)")
        self.assertEqual(self.line("Must-fix findings by round:"),
                         "Must-fix findings by round: round 1: 1 in 1 round(s), round 2: 3 in 1 round(s), "
                         "round 4: 5 in 1 round(s), round 5: 2 in 1 round(s)")
        self.assertEqual(self.line("Runs that used every allowed round"),
                         "Runs that used every allowed round and still had must-fix findings in the last: 1 of 1 (100%). "
                         "The limit is known only from summary files.")

    def test_an_empty_folder(self):
        self.assertEqual(self.lines()[2:], ["Runs: 0, with 0 rounds. Read from a summary file: 0. "
                                            "Read from review files, logs, and triage notes: 0.",
                                            "No review round found."])

    def test_the_output_starts_with_the_privacy_line_and_no_file_is_written(self):
        self.put("r-round1-codex.md", review("Reviewed.", ("P2", "", "Guard it")))
        before = sorted(os.listdir(self.folder))
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            code = loop_stats.main(["loop_stats.py", self.folder])
        self.assertEqual(code, 0)
        self.assertEqual(printed.getvalue().split("\n")[0],
                         "Private: these figures describe your own reviews. Do not commit or publish them.")
        self.assertEqual(sorted(os.listdir(self.folder)), before)
        self.assertEqual(os.listdir(HERE).count("__pycache__"), 0, "the tests left a cache folder beside them")

    def test_a_folder_that_does_not_exist(self):
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors), contextlib.redirect_stdout(io.StringIO()):
            code = loop_stats.main(["loop_stats.py", os.path.join(self.folder, "missing")])
        self.assertEqual(code, 2)
        self.assertIn("no such folder", errors.getvalue())

    def test_several_folders_are_added_up(self):
        other = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, other, True)
        self.put("a-summary.json", json.dumps(summary(run="a")))
        with open(os.path.join(other, "b-summary.json"), "w", encoding="utf-8") as handle:
            json.dump(summary(run="b"), handle)
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            loop_stats.main(["loop_stats.py", self.folder, other])
        self.assertIn("Runs: 2, with 4 rounds.", printed.getvalue())
        # A folder named twice, the second time by another path, is read once.
        again = io.StringIO()
        with contextlib.redirect_stdout(again):
            loop_stats.main(["loop_stats.py", self.folder, other, os.path.join(self.folder, ".")])
        self.assertIn("Runs: 2, with 4 rounds.", again.getvalue())


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


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(LoopStatsTest)
    result = unittest.TextTestRunner(stream=io.StringIO(), resultclass=Lines, verbosity=0).run(suite)
    for _, trace in result.failures + result.errors:
        print(trace, file=sys.stderr)
    if not result.wasSuccessful():
        print(f"{len(result.failures) + len(result.errors)} failed")
        sys.exit(1)
    print("all passed" + (f", {len(result.skipped)} skipped" if result.skipped else ""))
