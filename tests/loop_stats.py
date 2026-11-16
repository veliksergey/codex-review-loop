#!/usr/bin/env python3
"""Prints figures about your own review runs, read from the review loop's log folders.

Usage: python tests/loop_stats.py [<log folder>...]
Without a folder it reads the log folder of the repository in the current directory,
~/.claude/codex-reviews/<name of the repository's root folder>.

The figures describe one person's work. This script prints them and writes no file.
Do not commit or publish its output.

A run that has a valid <run>-summary.json is read from that file. Any other run is
read from its review files, logs, file times, and triage notes. Python 3, standard
library only.
"""
import json
import math
import os
import re
import subprocess
import sys

PRIVATE = "Private: these figures describe your own reviews. Do not commit or publish them."

ROUND_FILE = re.compile(r"^(?P<run>.+)-round(?P<n>\d+)-(?P<kind>prompt\.md|codex\.md|codex\.log|claude\.md)$")
SUMMARY_FILE = re.compile(r"^(?P<run>.+)-summary\.json$")
# A finding as Codex renders it, at the start of a line: "- [P1] (criterion 2) Title -
# path:lines". The lines of its body are indented.
FINDING = re.compile(r"^[-*][ \t]*\[(P[0-3])\][ \t]*(?:\(([^)]{1,60})\))?")
# The line under which Codex lists its findings.
LISTED = "Full review comments:"
# A line that can open or close a fenced block: three or more ` or ~ after up to three spaces.
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
UNVERIFIED = re.compile(
    r"not run\b|not verifi|unverifi|could not|cannot verify|unable to|not verifiable", re.I)
TRIAGE_HEADER = re.compile(
    r"^\|\s*#\s*\|\s*Finding\s*\|\s*Reviewer label\s*\|\s*Final label\s*\|\s*Decision\s*\|", re.M)
# What the triage template asks for in place of the table when a review has no finding.
TRIAGE_NONE = re.compile(r"^## Findings[ \t]*\n(?:[ \t]*\n)*None\.[ \t]*$", re.M)
# The four hashes fingerprint.sh prints, or "none" when no fingerprint could be taken.
FINGERPRINT = re.compile(r"^(none|[0-9a-f]{40,64}( [0-9a-f]{40,64}){3})$")

LABELS = ("P0", "P1", "P2", "P3")
MUST_FIX = ("P0", "P1", "P2")
TAGS = ("criterion", "beyond request", "handoff", "none")
DECISIONS = ("fixed", "not fixed", "listed for the user", "rejected", "outside scope", "disputed twice")
VERDICTS = ("verified", "clean with unverified items", "fixes not re-reviewed", "open findings",
            "review failed")
MODES = ("uncommitted", "branch", "paths", "audit")
STATES = ("met", "not met", "fixed this round", "not verifiable")
VERIFIERS = ("reviewer", "implementer", "nobody")
# The counts round-facts.sh prints for every log it can read.
COUNTS = ("shell_started", "shell_ran", "shell_start_failed", "tool_calls", "web_search_calls",
          "other_tool_calls")
# The line it prints for each tool called outside the shell.
TOOL = re.compile(r"^tool=(\S+) calls=([0-9]{1,18})( |$)")
# The tools whose calls it counts as web searches.
WEB = "codex_apps/search_service."


def tag_of(text):
    """The requirement tag at the start of a finding's title, or "none"."""
    text = (text or "").strip().lower()
    if text.startswith("criterion"):
        return "criterion"
    return text if text in ("beyond request", "handoff") else "none"


def bullets(lines, fenced):
    """The findings among these lines, the lines above the first, and whether a fenced
    block was left open. With fenced, a bullet inside a fenced block is an example."""
    found, opening, fence = [], [], ""
    for line in lines:
        mark = FENCE.match(line) if fenced else None
        if fence:
            # A block closes on a line that holds only a run of its mark, at least as long.
            if (mark and mark.group(1)[0] == fence[0] and len(mark.group(1)) >= len(fence)
                    and not mark.group(2).strip()):
                fence = ""
        # A block that opens after spaces is part of a finding's body, which is indented.
        elif mark and mark.start(1) == 0 and not (mark.group(1)[0] == "`" and "`" in mark.group(2)):
            fence = mark.group(1)
        else:
            item = FINDING.match(line)
            if item:
                found.append((item.group(1), item.group(2)))
        if not found:
            opening.append(line)
    return found, opening, bool(fence)


def findings_of(review):
    """The findings a review lists, as (label, tag) pairs, and the text above them.

    Codex lists them below the line "Full review comments:", one bullet at the start of
    a line each; the lines of a finding's body are indented. What stands above that line
    is the summary. A review without that line is searched as a whole.
    """
    lines, summary = review.split("\n"), None
    for i, line in enumerate(lines):
        if line.rstrip() == LISTED:
            summary, lines = lines[:i], lines[i + 1:]
            break
    found, opening, left_open = bullets(lines, True)
    if left_open:
        # A block that never closes is no block: it would hide every finding below it.
        found, opening, _ = bullets(lines, False)
    return found, "\n".join(opening if summary is None else summary)


def facts_of_log(text):
    """What the reviewer ran, read from Codex's log by the rules of round-facts.sh."""
    lines = [line.rstrip("\r") for line in text.split("\n")]
    facts, rules, body = {}, 0, None
    for i, line in enumerate(lines):
        if "codex_cli" not in facts:
            if line.startswith("OpenAI Codex v"):
                facts["codex_cli"] = line[len("OpenAI Codex v"):]
            continue
        if line == "--------":
            rules += 1
            if rules == 2:
                body = i + 1
                break
            continue
        for key, name in (("sandbox: ", "sandbox"), ("model: ", "model"),
                          ("reasoning effort: ", "effort")):
            if line.startswith(key):
                facts[name] = line[len(key):]
    if body is None:
        return None
    # Events are counted after the echoed prompt, or from the header when it has no end.
    rest = lines[body:]
    if "</grounding_rules>" in rest:
        rest = rest[rest.index("</grounding_rules>") + 1:]
    started = sum(1 for line in rest if line == "exec")
    ran = sum(1 for line in rest
              if re.match(r"^ (succeeded in|exited [0-9]+ in) [0-9.]+[a-z]+:$", line))
    failed = sum(1 for line in rest
                 if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z +ERROR .*error=exec_command failed", line))
    tools = {}
    for line in rest:
        found = re.match(r"^mcp: (\S+) started$", line)
        if found:
            tools[found.group(1)] = tools.get(found.group(1), 0) + 1
    web = sum(n for name, n in tools.items() if name.startswith(WEB))
    facts.update(shell_started=started, shell_ran=ran, shell_start_failed=failed,
                 shell_usable="yes" if ran > 0 else "no", tool_calls=sum(tools.values()),
                 web_search_calls=web, other_tool_calls=sum(tools.values()) - web, tools=tools)
    return facts


def facts_of_lines(lines):
    """The same facts from the key=value lines that round-facts.sh printed."""
    if not lines:
        # A round whose log could not be read printed no facts: nothing is known of it.
        return None
    facts, tools = {}, {}
    for line in lines:
        if line.startswith("tool="):
            found = TOOL.match(line)
            if found:
                tools[found.group(1)] = int(found.group(2))
            continue
        key, _, value = line.partition("=")
        # Only the counts are numbers; any other value, and a count that is not one, is text.
        if key in COUNTS and value.isascii() and value.isdigit() and len(value) <= 18:
            value = int(value)
        facts[key] = value
    facts["tools"] = tools
    return facts


def triage_rows(text):
    """The rows of a triage note's findings table. An empty list for a note that says
    "None." in place of the table, and None for a note that has neither."""
    header = TRIAGE_HEADER.search(text)
    if not header:
        return [] if TRIAGE_NONE.search(text) else None
    rows = []
    for line in text[header.end():].split("\n")[1:]:
        if not line.startswith("|"):
            if rows or line.strip():
                break
            continue
        cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", line)[1:-1]]
        if cells and all(cell and set(cell) <= set("-:") for cell in cells):
            # The line of dashes under the header.
            continue
        reviewer, final, decision = (cell.strip("` ") for cell in (cells + [""] * 5)[2:5])
        if reviewer not in LABELS + ("none",):
            # A row that is too short, or without a readable label of the reviewer, cannot
            # be counted, so the note is not in the fixed shape.
            return None
        tag = re.match(r"^\(([^)]{1,60})\)", cells[1])
        rows.append({"tag": tag_of(tag.group(1) if tag else ""), "reviewer_label": reviewer,
                     "final_label": final, "decision": decision})
    return rows


def check_summary(data):
    """Why a summary does not fit schema 1, as a list of reasons; empty when it fits."""
    why = []

    def need(obj, key, test, what):
        if not isinstance(obj, dict) or key not in obj or not test(obj[key]):
            why.append(f"{key}: {what}")

    def one_of(options):
        return lambda value: isinstance(value, str) and value in options

    def number(value):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return False
        try:
            return math.isfinite(value) and value >= 0
        except OverflowError:
            # A whole number too large to be a duration, a limit, or a criterion.
            return False

    def text(value):
        return isinstance(value, str)

    def flag(value):
        return isinstance(value, bool)

    def as_list(value):
        return value if isinstance(value, list) else []

    if not isinstance(data, dict):
        return ["the file does not hold one object"]
    need(data, "schema", lambda value: value == 1 and not isinstance(value, bool), "must be 1")
    need(data, "run", text, "must be text")
    need(data, "plugin", text, "must be text")
    need(data, "mode", one_of(MODES), "must be one of " + ", ".join(MODES))
    need(data, "task_file", flag, "must be true or false")
    need(data, "report_only", flag, "must be true or false")
    need(data, "rounds_limit", lambda value: number(value) and value >= 1, "must be a number, 1 or more")
    need(data, "web", one_of(("cached", "live", "off")), "must be cached, live, or off")
    need(data, "tools", one_of(("default", "allowed")), "must be default or allowed")
    need(data, "task_hash_start", text, "must be text")
    need(data, "task_hash_end", text, "must be text")
    need(data, "verdict", one_of(VERDICTS), "must be one of the five verdicts")
    need(data, "rounds", lambda value: isinstance(value, list), "must be a list")
    need(data, "checklist", lambda value: isinstance(value, list), "must be a list")
    numbers = []
    for i, entry in enumerate(as_list(data.get("rounds"))):
        here = len(why)
        need(entry, "round", lambda value: isinstance(value, int) and number(value) and value >= 1,
             "must be a whole number, 1 or more")
        need(entry, "seconds", number, "must be a number, 0 or more")
        need(entry, "review_model", text, "must be text")
        need(entry, "reviewed", flag, "must be true or false")
        need(entry, "unverified", flag, "must be true or false")
        need(entry, "fingerprint", lambda value: isinstance(value, str) and bool(FINGERPRINT.match(value)),
             "must be four hashes separated by spaces, or none")
        need(entry, "facts", lambda value: isinstance(value, list) and all(
            isinstance(line, str) and "=" in line for line in value), "must be a list of key=value lines")
        need(entry, "findings", lambda value: isinstance(value, list), "must be a list")
        findings = as_list(entry.get("findings") if isinstance(entry, dict) else None)
        for finding in findings:
            need(finding, "tag", one_of(TAGS), "must be one of " + ", ".join(TAGS))
            need(finding, "reviewer_label", one_of(LABELS + ("none",)), "must be P0 to P3, or none")
            need(finding, "final_label", one_of(LABELS), "must be P0 to P3")
            need(finding, "decision", one_of(DECISIONS), "must be one of the six decision words")
        if isinstance(entry, dict):
            # A round without a usable review has no findings to list.
            if entry.get("reviewed") is False and findings:
                why.append("findings: must be empty when reviewed is false")
            lines = as_list(entry.get("facts"))
            if not lines:
                # The loop also stops a round as failed when it can read no facts of it.
                if entry.get("facts") == [] and entry.get("reviewed") is True:
                    why.append("reviewed: must be false when the round has no facts")
            elif all(isinstance(line, str) and "=" in line for line in lines):
                # A list of facts is empty, for a log that could not be read, or complete.
                facts = facts_of_lines(lines)
                missing = [key for key in COUNTS if not isinstance(facts.get(key), int)]
                if missing:
                    why.append("facts: must hold a whole number for " + ", ".join(missing))
                # The loop stops a review as failed when no sandboxed command ran.
                elif entry.get("reviewed") is True and facts["shell_ran"] == 0:
                    why.append("reviewed: must be false when no sandboxed command ran")
                elif facts.get("shell_usable") != ("yes" if facts["shell_ran"] > 0 else "no"):
                    why.append("facts: shell_usable must be yes when shell_ran is above 0, and no otherwise")
                else:
                    # One readable line for each tool, and three counts that follow from them.
                    calls = facts["tools"]
                    web = sum(n for name, n in calls.items() if name.startswith(WEB))
                    if (len(calls) != sum(1 for line in lines if line.startswith("tool="))
                            or facts["tool_calls"] != sum(calls.values())
                            or facts["web_search_calls"] != web
                            or facts["other_tool_calls"] != sum(calls.values()) - web):
                        why.append("facts: the tool lines and the counts of tool calls must agree")
            if entry.get("round") in numbers:
                why.append("round: appears twice")
            numbers.append(entry.get("round"))
        why[here:] = [f"round {i + 1}: {reason}" for reason in why[here:]]
    for row in as_list(data.get("checklist")):
        need(row, "criterion", lambda value: number(value) and value >= 1, "must be a number, 1 or more")
        need(row, "state", one_of(STATES), "must be one of " + ", ".join(STATES))
        need(row, "verified_by", one_of(VERIFIERS), "must be one of " + ", ".join(VERIFIERS))
    if not why and data["rounds"]:
        # A run whose last round gave no usable review has one verdict.
        last = max(data["rounds"], key=lambda entry: entry["round"])
        if last["reviewed"] is False and data["verdict"] != "review failed":
            why.append("verdict: must be review failed when the last round gave no usable review")
    return why


def read(path):
    """The text of a file, or nothing when it cannot be read: such a file tells nothing."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def collect(folder):
    """Every run of one log folder, and the summaries that could not be used."""
    files, summaries = {}, {}
    for name in sorted(os.listdir(folder)):
        found = ROUND_FILE.match(name)
        if found:
            files.setdefault(found.group("run"), {}).setdefault(int(found.group("n")), {})[
                found.group("kind")] = os.path.join(folder, name)
            continue
        found = SUMMARY_FILE.match(name)
        if found:
            summaries[found.group("run")] = os.path.join(folder, name)
    runs, unusable = [], []
    for run in sorted(set(files) | set(summaries)):
        if run in summaries:
            try:
                data = json.loads(read(summaries[run]))
                why = check_summary(data)
            except ValueError as error:
                data, why = None, [f"not JSON: {error}"]
            except RecursionError:
                data, why = None, ["nested too deep to read"]
            if not why:
                runs.append(from_summary(data))
                continue
            unusable.append((os.path.basename(summaries[run]), why))
        if run in files:
            runs.append(from_files(run, files[run]))
    return runs, unusable


def from_summary(data):
    """A run as its summary describes it. Each round keeps its own number."""
    rounds = []
    for entry in sorted(data["rounds"], key=lambda entry: entry["round"]):
        rounds.append({"round": entry["round"], "reviewed": entry["reviewed"], "seconds": entry["seconds"],
                       "facts": facts_of_lines(entry["facts"]), "unverified": entry["unverified"],
                       "findings": entry["findings"]})
    return {"run": data["run"], "source": "summary", "rounds": rounds, "limit": data["rounds_limit"],
            "verdict": data["verdict"],
            "task_changed": data["task_hash_start"] != data["task_hash_end"]}


def from_files(run, by_round):
    """A run as its files show it. Each round keeps the number in its file names."""
    rounds = []
    for n in sorted(by_round):
        kinds = by_round[n]
        review = read(kinds["codex.md"]) if "codex.md" in kinds else ""
        listed, opening = findings_of(review)
        findings = [{"tag": tag_of(tag), "reviewer_label": label, "final_label": None, "decision": None}
                    for label, tag in listed]
        # A triage note in the fixed shape also holds the final labels and the decisions.
        rows = triage_rows(read(kinds["claude.md"])) if "claude.md" in kinds else None
        # Its rows are used when they list what the review lists, or when the review lists
        # nothing. Otherwise the review's own list stands: it is what the reviewer said.
        theirs = [row["reviewer_label"] for row in rows or [] if row["reviewer_label"] in LABELS]
        if rows and (not listed or theirs == [label for label, _ in listed]):
            findings = [{"tag": row["tag"],
                         "reviewer_label": row["reviewer_label"] if row["reviewer_label"] in LABELS else "none",
                         "final_label": row["final_label"] if row["final_label"] in LABELS else None,
                         "decision": row["decision"] if row["decision"] in DECISIONS else None}
                        for row in rows]
        seconds = None
        if "codex.md" in kinds and "prompt.md" in kinds:
            try:
                took = os.path.getmtime(kinds["codex.md"]) - os.path.getmtime(kinds["prompt.md"])
                seconds = took if took >= 0 else None
            except OSError:
                # A file that went away, or a link to nowhere: the duration is unknown.
                pass
        facts = facts_of_log(read(kinds["codex.log"])) if "codex.log" in kinds else None
        # Without a review, or a triage note in the fixed shape, the round's result is
        # unknown, not clean. So is a review beside a log that cannot be read, or that
        # shows that no sandboxed command ran: the loop stops such a round as failed.
        failed = "codex.log" in kinds and (facts is None or facts["shell_usable"] == "no")
        reviewed = not failed and (bool(review.strip()) or rows is not None)
        rounds.append({"round": n, "reviewed": reviewed, "seconds": seconds, "facts": facts,
                       "findings": findings,
                       "unverified": bool(UNVERIFIED.search(opening)) if review.strip() else None})
    return {"run": run, "source": "files", "rounds": rounds, "limit": None, "verdict": None,
            "task_changed": None}


def must_fix(entry):
    return sum(1 for finding in entry["findings"] if finding["reviewer_label"] in MUST_FIX)


def share(part, whole):
    return f"{part} of {whole}" + (f" ({round(100 * part / whole)}%)" if whole else "")


def counted(counts, order=None):
    keys = [key for key in (order or sorted(counts)) if counts.get(key)]
    return ", ".join(f"{key}: {counts[key]}" for key in keys) or "none"


def report(runs, unusable):
    """The lines to print for these runs."""
    out = [PRIVATE, ""]
    rounds = [entry for run in runs for entry in run["rounds"]]
    by_source = {source: sum(1 for run in runs if run["source"] == source) for source in ("summary", "files")}
    out.append(f"Runs: {len(runs)}, with {len(rounds)} rounds. Read from a summary file: "
               f"{by_source['summary']}. Read from review files, logs, and triage notes: {by_source['files']}.")
    for name, why in unusable:
        out.append(f"Summary not used: {name}: {'; '.join(why[:3])}" + (" ..." if len(why) > 3 else ""))
    if not rounds:
        return out + ["No review round found."]
    # A round without a usable review has no known result. It is counted here and in
    # the figures about cost and tools, and in no figure about findings.
    reviewed = [entry for entry in rounds if entry["reviewed"]]
    out.append(f"Rounds without a usable review: {len(rounds) - len(reviewed)} of {len(rounds)}. "
               "They count in no figure about findings.")

    sizes = {}
    for run in runs:
        sizes[len(run["rounds"])] = sizes.get(len(run["rounds"]), 0) + 1
    firsts = [entry for run in runs for entry in run["rounds"] if entry["round"] == 1 and entry["reviewed"]]
    out += ["", "Does a clean first round end most runs?",
            "  Rounds per run: " + ", ".join(f"{size} round(s): {sizes[size]} run(s)" for size in sorted(sizes)),
            "  Runs whose first round had no must-fix finding: "
            + share(sum(1 for entry in firsts if must_fix(entry) == 0), len(firsts))
            + f". Runs without a reviewed first round, not counted: {len(runs) - len(firsts)}."]

    by_number, pairs, more = {}, 0, 0
    for run in runs:
        known = {entry["round"]: must_fix(entry) for entry in run["rounds"] if entry["reviewed"]}
        for n, count in known.items():
            by_number.setdefault(n, []).append(count)
            # Only the round with the next number is "the round after".
            if count > 0 and n + 1 in known:
                pairs += 1
                more += known[n + 1] > count
    capped = [run["rounds"][-1] for run in runs if run["limit"] and run["rounds"]
              and run["rounds"][-1]["round"] >= run["limit"] and run["rounds"][-1]["reviewed"]]
    out += ["", "Do rounds converge?",
            "  Must-fix findings by round: " + (", ".join(
                f"round {n}: {sum(by_number[n])} in {len(by_number[n])} round(s)" for n in sorted(by_number))
                or "none"),
            "  A round after a round with must-fix findings reported more of them: " + share(more, pairs),
            "  Runs that used every allowed round and still had must-fix findings in the last: "
            + share(sum(1 for entry in capped if must_fix(entry) > 0), len(capped))
            + ". The limit is known only from summary files."]

    findings = [finding for entry in reviewed for finding in entry["findings"]]
    labels, tags, decisions, matrix, overrides = {}, {}, {}, {}, 0
    for finding in findings:
        labels[finding["reviewer_label"]] = labels.get(finding["reviewer_label"], 0) + 1
        tags[finding["tag"]] = tags.get(finding["tag"], 0) + 1
        if finding["decision"]:
            decisions[finding["decision"]] = decisions.get(finding["decision"], 0) + 1
        if finding["final_label"] and finding["reviewer_label"] in LABELS:
            pair = f"{finding['reviewer_label']} to {finding['final_label']}"
            matrix[pair] = matrix.get(pair, 0) + 1
        if finding["decision"] == "rejected" or (
                finding["reviewer_label"] in MUST_FIX and finding["final_label"] == "P3"):
            overrides += 1
    out += ["", "Which checks produce findings?",
            f"  Findings: {len(findings)}. By the reviewer's label: " + counted(labels, LABELS + ("none",)),
            "  By tag: " + counted(tags, TAGS),
            "", "How does triage treat the reviewer?",
            "  Decisions: " + counted(decisions, DECISIONS),
            "  The reviewer's label and the final label: " + counted(matrix),
            f"  Implementer overrides: {overrides}",
            "  Decisions and final labels are known from summary files, and from triage notes in the fixed "
            "shape that list the review's findings."]

    known = [entry["facts"] for entry in rounds if entry["facts"]]
    sandboxes, versions, servers = {}, {}, {}
    for facts in known:
        sandboxes[facts.get("sandbox", "unknown")] = sandboxes.get(facts.get("sandbox", "unknown"), 0) + 1
        versions[facts.get("codex_cli", "unknown")] = versions.get(facts.get("codex_cli", "unknown"), 0) + 1
        for name, calls in facts.get("tools", {}).items():
            server = name.split("/")[0]
            servers[server] = servers.get(server, 0) + calls

    def total(key):
        return sum(facts.get(key, 0) for facts in known if isinstance(facts.get(key, 0), int))

    out += ["", "What did the reviewer use?",
            f"  Rounds with a readable log: {len(known)} of {len(rounds)}",
            f"  Shell commands started: {total('shell_started')}, failed to start: {total('shell_start_failed')}, "
            f"rounds in which none ran: {sum(1 for facts in known if facts.get('shell_usable') == 'no')}",
            f"  Web searches: {total('web_search_calls')}. Other tool calls: {total('other_tool_calls')}. "
            "Tool calls by server: " + counted(servers),
            "  Sandbox line: " + counted(sandboxes),
            "  Codex CLI version: " + counted(versions)]

    clean = [entry for entry in reviewed if must_fix(entry) == 0 and entry["unverified"] is not None]
    out += ["", "Does a clean round say what it could not verify?",
            "  Rounds without a must-fix finding that named something not run or not verified: "
            + share(sum(1 for entry in clean if entry["unverified"]), len(clean))]

    seconds = sorted(entry["seconds"] for entry in rounds if entry["seconds"] is not None)
    out += ["", "What does a round cost?"]
    if seconds:
        # The median of an even number of rounds lies halfway between the two in the
        # middle. It is reached from the lower one: their sum can be too large a number.
        low, high = seconds[(len(seconds) - 1) // 2], seconds[len(seconds) // 2]
        out.append(f"  Duration of a round in seconds: shortest {round(seconds[0])}, "
                   f"median {round(low + (high - low) / 2)}, longest {round(seconds[-1])}, "
                   f"from {len(seconds)} round(s)")
    else:
        out.append("  No duration is known.")

    verdicts = {}
    for run in runs:
        if run["verdict"]:
            verdicts[run["verdict"]] = verdicts.get(run["verdict"], 0) + 1
    # A summary holds the hash at the start and at the end, not what happened in between.
    differ = sum(1 for run in runs if run["task_changed"])
    out += ["", "From summary files only:",
            "  Verdicts: " + counted(verdicts, VERDICTS),
            f"  Runs whose request or criteria differ between the start and the end: {differ}"]
    return out


def home_folder():
    """The home folder as the loop sees it: HOME when it is set, as in the loop's shell."""
    home = os.environ.get("HOME")
    if not home:
        return os.path.expanduser("~")
    # Git Bash names a drive /c/...; Python for Windows needs C:/...
    drive = re.match(r"^/([A-Za-z])(/.*)?$", home) if os.name == "nt" else None
    return f"{drive.group(1).upper()}:{drive.group(2) or '/'}" if drive else home


def default_folder():
    try:
        printed = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                                 check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    # Git prints the path in UTF-8 on Windows, and in the bytes of the file system elsewhere.
    root = printed.decode("utf-8", "replace") if os.name == "nt" else os.fsdecode(printed)
    return os.path.join(home_folder(), ".claude", "codex-reviews", os.path.basename(root.rstrip("\r\n")))


def main(argv):
    folders = argv[1:] or [default_folder()]
    if folders == [None]:
        print("loop_stats: give a log folder, or run inside a git repository", file=sys.stderr)
        return 2
    runs, unusable, read_before = [], [], set()
    for folder in folders:
        if not os.path.isdir(folder):
            print(f"loop_stats: no such folder: {folder}", file=sys.stderr)
            return 2
        # A folder named twice is read once.
        if os.path.realpath(folder) in read_before:
            continue
        read_before.add(os.path.realpath(folder))
        try:
            more_runs, more_unusable = collect(folder)
        except OSError as error:
            print(f"loop_stats: cannot read {folder}: {error}", file=sys.stderr)
            return 2
        runs += more_runs
        unusable += more_unusable
    text = "\n".join(report(runs, unusable))
    try:
        print(text)
    except UnicodeEncodeError:
        # A terminal that cannot show a character read from a log still gets the figures.
        print(text.encode("ascii", "replace").decode("ascii"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
