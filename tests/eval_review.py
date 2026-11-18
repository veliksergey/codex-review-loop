#!/usr/bin/env python3
"""Runs a Codex review on a case of the evaluation corpus, and scores reviews against
the labels of their cases.

A review is run as the review loop runs one: the same prompt, the same flags, and the
same checks before and after. What a review leaves, and every figure made from it, stays
outside this repository.

Usage:
  python tests/eval_review.py run <case> [--dry-run] [--web off|cached|live]
                                                       one review of one case. It spends one
                                                       review of your Codex allowance and
                                                       sends the fixture to OpenAI; --dry-run
                                                       does everything but start Codex
  python tests/eval_review.py judge                    a judgment file for each review that
                                                       can be scored and has none
  python tests/eval_review.py report                   figures from the reviews that are judged

Before the command: --results <folder>, where reviews are kept. The default is the folder
eval in the log folder that the review loop keeps for this repository. --corpus and
--repository are those of eval_corpus.py. Python 3.8 or newer, standard library only.
"""
import argparse
import collections
import datetime
import importlib.util
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# The two modules beside this one are loaded without a cache folder in the repository.
sys.dont_write_bytecode = True


def beside(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


eval_corpus = beside("eval_corpus")
loop_stats = beside("loop_stats")
Problem = eval_corpus.Problem

# This repository, and in it the plugin whose loop a review follows.
HOME = os.path.dirname(HERE)
PLUGIN = os.path.join(HOME, "plugins", "codex-review-loop")
SKILL = os.path.join(PLUGIN, "skills", "codex-loop")
PRIVATE = "Private: these figures describe reviews run on your own account. Do not commit or publish them."
# The line SKILL.md gives for a review without a task file.
NO_TASK = "No task file was provided. Review the scope only and say so in your summary."
PLACEHOLDER = re.compile(r"\{\{([A-Z_]+)\}\}")
HASHES = re.compile(r"^[0-9a-f]{40,64}( [0-9a-f]{40,64}){3}$")
PLACE = re.compile(r"^(.*?):([0-9]+)(?:-([0-9]+))?$")
SEVERITIES = eval_corpus.SEVERITIES
MUST_FIX = ("P0", "P1", "P2")
# The web search modes of tool-flags.sh. A review of a case runs without web search
# unless asked: this repository is public, its labels and its fixes with it, and the log
# of a review does not say what a search fetched.
WEB = ("off", "cached", "live")
# From this length on, a line of a label or of a definition that opens with a key is no
# chance match in a log.
TELLTALE = 30
KEYED = re.compile(r'^\{?"([A-Za-z_]+)": ')
# What a person states a finding to be.
IS = ("mechanism", "known defect", "other defect", "false alarm")
NAMED = {"mechanism": "a labeled mechanism", "known defect": "a known defect", "other defect": "another defect",
         "false alarm": "a false alarm"}
# What a review leaves, by the names round-facts.sh knows a log and its prompt by.
PROMPT, REVIEW, LOG = "review-prompt.md", "review-codex.md", "review-codex.log"
# The command of SKILL.md, started in the fixture; no path in it names the case. The
# line that tool-flags.sh printed stands in the script itself, where SKILL.md has
# <tool flags>: nothing is read when it runs, so Codex cannot start without them.
COMMAND = f"""set -- <tool flags>
[ "$#" -gt 0 ] || exit 97
codex exec review -c 'sandbox_mode="read-only"' "$@" -o ../out/{REVIEW} - < ../out/{PROMPT} 2> ../out/{LOG}
"""
HOW = ("For every finding labelled P0, P1, or P2, set \"is\" to one of: " + ", ".join(IS) + ". With \"mechanism\", "
       "set \"mechanism\" to its number. A P3 finding may be stated the same way. Then fill judged_by, and "
       "judged_on with a date such as 2026-01-31.")


def bash():
    found = shutil.which("bash")
    if found is None or (eval_corpus.on_windows() and "system32" in found.lower()):
        raise Problem("no bash that can run the scripts of the plugin")
    return found


def started(arguments, folder):
    return subprocess.run([bash()] + arguments, cwd=folder, env=eval_corpus.own_environment(),
                          stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def script(name, folder, *arguments):
    """Runs a script of the review loop in a folder, as the loop runs it."""
    return started([os.path.join(SKILL, name).replace(os.sep, "/")] + list(arguments), folder)


def text(data):
    return data.decode("utf-8", "replace").replace("\r\n", "\n").rstrip("\n")


def read(path):
    """The text of a file, empty where there is none."""
    try:
        with open(path, "rb") as handle:
            return handle.read().decode("utf-8", "replace")
    except OSError:
        return ""


def write(path, content):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)


def default_results(writes, places):
    """The folder eval in the log folder that the review loop keeps for this repository.
    log-dir.sh names that folder, and makes and marks it where it is new. It is run only
    for a folder outside these places, and by a command that writes nothing only for a
    folder that is marked already."""
    unknown = "the log folder of this repository is not known; name a folder with --results. "
    # pwd -W, where bash has it, names a folder as Windows does.
    here = '{ pwd -W 2>/dev/null || pwd; }'
    root = eval_corpus.git(HOME, "rev-parse", "--show-toplevel")
    home = started(["-c", f'[ -n "${{HOME:-}}" ] && cd "$HOME" && {here}'], HOME)
    if root.returncode != 0 or not text(root.stdout) or home.returncode != 0 or not text(home.stdout):
        raise Problem(unknown + (text(root.stderr) or text(home.stderr)))
    # The folder as log-dir.sh names it: by the name of the repository's root folder.
    folder = os.path.join(os.path.normpath(text(home.stdout)), ".claude", "codex-reviews",
                          os.path.basename(os.path.normpath(text(root.stdout))))
    # Before the script makes anything: the folder, or one above it, can be a link.
    outside(folder, places)
    if not writes and not os.path.lexists(os.path.join(folder, "repository-root.txt")):
        return os.path.join(folder, "eval")
    done = started(["-c", f'folder="$(bash "$1")" && cd "$folder" && {here}', "log-dir",
                    os.path.join(SKILL, "log-dir.sh").replace(os.sep, "/")], HOME)
    if done.returncode != 0 or not text(done.stdout):
        raise Problem(unknown + text(done.stderr))
    return os.path.join(os.path.normpath(text(done.stdout)), "eval")


def guarded(corpus, repository):
    """The folders that results stay out of: this repository, the checkout that holds
    the corpus, and the one the history is read from."""
    return eval_corpus.protected(corpus, repository) + eval_corpus.protected(HOME, HOME)


def outside(folder, places, why="the results of a review are kept outside this repository"):
    """Stops when a folder that a review is written to lies in one of these folders,
    also where a link on the way to it leads there."""
    for place in places:
        if eval_corpus.within(folder, place):
            raise Problem(f"{folder}: {why}")


def scope_of(case):
    """The scope text that SKILL.md gives for the mode of a case, with its targets."""
    skill = read(os.path.join(SKILL, "SKILL.md"))
    # Each scope text is a fenced block; the line above it names the mode.
    texts, above, block = {}, "", None
    for line in skill.split("\n"):
        if block is not None:
            if line.strip() == "```":
                texts[above], block = "\n".join(block), None
            else:
                block.append(line)
        elif line.strip() == "```text":
            block = []
        elif line.strip():
            above = line.strip()
    if NO_TASK not in skill:
        raise Problem("SKILL.md no longer gives the line for a review without a task file")
    if case["mode"] == "uncommitted":
        scope = texts.get("Uncommitted:")
    else:
        scope = next((value for key, value in texts.items() if key.startswith("Paths (")), None)
        if scope and "<paths>" in scope and "<target>" in scope:
            scope = scope.replace("<paths>", "\n".join(case["target"]))
            scope = scope.replace("<target>", " ".join(shlex.quote(target) for target in case["target"]))
        else:
            scope = None
    if not scope:
        raise Problem(f"SKILL.md no longer gives the scope text of a review in {case['mode']} mode")
    return scope


def prompt_for(case, task, work):
    """The prompt of a review of a built fixture: review-prompt.md, each of its four
    placeholders filled as SKILL.md says."""
    template = read(os.path.join(SKILL, "review-prompt.md"))
    listed = eval_corpus.must(script("instruction-changes.sh", work),
                              "the instruction files that the change edits cannot be listed")
    values = {"SCOPE": scope_of(case), "FOCUS": "none", "INSTRUCTIONS": text(listed),
              "TASK": read(task).rstrip("\n") if task else NO_TASK}
    if sorted(PLACEHOLDER.findall(template)) != sorted(values):
        raise Problem("review-prompt.md does not hold each of its four placeholders once")
    # In one pass: a task file that holds the name of a placeholder is left as it is.
    return PLACEHOLDER.sub(lambda found: values[found.group(1)], template)


def fingerprint(work):
    """The four hashes of fingerprint.sh on one line, or what went wrong in their place."""
    done = script("fingerprint.sh", work)
    said = " ".join(text(done.stdout).split())
    if done.returncode == 0 and HASHES.match(said):
        return said
    return "failed: " + (text(done.stderr) or said or f"exit code {done.returncode}")[-300:]


def telltales(corpus, name):
    """Lines that stand in the log of a review only when the reviewer read the label or
    the definition of its case, by whatever path: each line of those two files, as it
    stands on disk, that is too long for a chance match."""
    lines = set()
    for path in (os.path.join(corpus, "labels", name + ".json"), os.path.join(corpus, "cases", name, "case.json")):
        lines.update(" ".join(line.split()) for line in read(path).split("\n"))
    # Only a line that opens with a key, or with the brace of a file kept on one line. A
    # bare value, such as the path of a file in quotes, is what any command may print;
    # so is a key with such a path, in a list a reviewer writes for itself.
    return {line for line in lines if len(line) >= TELLTALE and KEYED.match(line)
            and KEYED.match(line).group(1) not in ("file", "script")}


def names(log, name, folders, lines=()):
    """Whether the log of a review names the case or one of these folders, or holds one
    of these lines. The log holds every command the reviewer ran and what each printed,
    and the sandbox lets it read outside the fixture. A label it could have read makes
    the review worth nothing."""
    said = re.sub(r"\\+", "/", log).lower()
    if re.search(r"(?<![a-z0-9-])" + re.escape(name.lower()) + r"(?![a-z0-9-])", said):
        return True
    for folder in folders:
        # As it was named and as the system resolves it, both without the drive: bash
        # writes C:\Users as /c/Users.
        for path in (os.path.abspath(folder), os.path.realpath(folder)):
            if re.sub(r"^[a-z]:", "", path.replace(os.sep, "/").lower()) in said:
                return True
    # Whatever stands before a line, such as its number, and however it is indented.
    whole = " ".join(log.split())
    return any(line in whole for line in lines)


def reasons(code, review, facts, trouble, before, after, leaked):
    """Why a review cannot be scored, each reason as a sentence; empty when it can.
    facts is what round-facts.sh printed, or None with what went wrong in trouble."""
    why = []
    if code != 0:
        why.append(f"Codex ended with exit code {code}")
    if not review.strip():
        why.append("the review is empty")
    if facts is None:
        why.append("the log of the review cannot be read: " + trouble)
    else:
        lines = facts.split("\n")
        value = dict(line.split("=", 1) for line in lines if "=" in line and not line.startswith("tool="))
        started, ran, failed = (value.get(key) for key in ("shell_started", "shell_ran", "shell_start_failed"))
        if value.get("shell_usable") != "yes":
            why.append("no sandboxed command ran")
        elif failed != "0" or started != ran:
            # A line inside the text of a command can have the shape of a command that
            # ran. Only a log in which every command that started also ran leaves no doubt.
            why.append("the log does not show beyond doubt that a sandboxed command ran: "
                       f"{started} started, {ran} ran, {failed} failed to start")
        if value.get("other_tool_calls") != "0":
            tools = [line for line in lines if line.startswith("tool=") and not line.startswith("tool=" + loop_stats.WEB)]
            why.append("a tool that should be off was called: " + "; ".join(tools))
        if value.get("sandbox") != "read-only":
            why.append(f"the sandbox was {value.get('sandbox') or 'not named'}, not read-only")
        if value.get("web_search_calls") != "0":
            why.append("the reviewer searched the web, where this repository and its labels are public, "
                       "and the log does not say what it fetched")
    if not HASHES.match(after):
        why.append("the fingerprint of the fixture could not be taken after the review: " + after)
    elif after != before:
        why.append("the fixture changed during the review")
    if leaked:
        why.append("the log names the case, the corpus, the results, or this repository, or holds a line of the "
                   "label or the definition of the case, so the reviewer may have read a label")
    return why


def remove(folder):
    """Deletes a folder that holds a fixture. Git makes some of its files read-only."""
    for root, folders, files in os.walk(folder):
        for entry in folders + files:
            try:
                os.chmod(os.path.join(root, entry), 0o700)
            except OSError:
                pass
    shutil.rmtree(folder, ignore_errors=True)


def keep(results, name, stamp, out):
    """Copies what a review left into a folder of its own in the results. Returns that
    folder. The record is copied last and put in place in one step: a folder that holds
    a record holds the whole review."""
    for number in range(1, 1000):
        folder = os.path.join(results, name, stamp if number == 1 else f"{stamp}-{number}")
        try:
            os.makedirs(folder)
            break
        except FileExistsError:
            continue
    else:
        raise Problem(f"{os.path.join(results, name)}: no free folder for a review started at {stamp}")
    try:
        for file in sorted(os.listdir(out)):
            if file != "record.json":
                shutil.copyfile(os.path.join(out, file), os.path.join(folder, file))
        part = os.path.join(folder, "record.json.part")
        shutil.copyfile(os.path.join(out, "record.json"), part)
        os.replace(part, os.path.join(folder, "record.json"))
    except OSError:
        # Half a copy is not left among the results. Where it cannot be deleted, it has
        # no record and is counted as no review.
        shutil.rmtree(folder, ignore_errors=True)
        raise
    return folder


def run(corpus, repository, results, name, dry_run, web="off"):
    """One review of one case. Returns the folder it left in the results, and its record."""
    cases = eval_corpus.load(corpus)
    if name not in cases:
        raise Problem(f"{name}: no such case")
    wrong = eval_corpus.definition_problems(corpus, cases, name)
    if wrong:
        raise Problem("a case with a problem is not reviewed: " + wrong[0])
    state = eval_corpus.state(corpus, repository, cases, name)
    if state != "agreed":
        raise Problem(f"{name}: the label is {state}, and no review runs before a person agreed with it")
    # The folder of the case too: it can be a link that leads somewhere else.
    places = guarded(corpus, repository)
    outside(results, places)
    outside(os.path.join(results, name), places)
    # And the folder for temporary files, where the prompt, the log, and the review are
    # written first. build guards the corpus and the history; this guards this checkout.
    outside(tempfile.gettempdir(), places,
            "the folder for temporary files lies inside this repository, and no review is written there")
    case, now = cases[name]["case"], datetime.datetime.now()
    manifest = eval_corpus.read_json(os.path.join(PLUGIN, ".claude-plugin", "plugin.json"))
    head = eval_corpus.git(HOME, "rev-parse", "--verify", "--quiet", "HEAD")
    record = {"case": name, "kind": case["kind"], "mode": case["mode"],
              "label": eval_corpus.case_hash(corpus, repository, cases[name]),
              "plugin": {"version": manifest.get("version") if isinstance(manifest, dict) else None,
                         "prompt": eval_corpus.digest(os.path.join(SKILL, "review-prompt.md"))},
              "commit": text(head.stdout) if head.returncode == 0 and text(head.stdout) else "unknown",
              "started": now.isoformat(timespec="seconds"), "dry_run": dry_run, "web": web}
    # The fixture is built where nothing names the case, and is deleted after the review.
    holder = tempfile.mkdtemp(prefix="review-")
    out, spent, kept = os.path.join(holder, "out"), False, False
    try:
        work, task = eval_corpus.build(corpus, repository, cases, name, holder)
        os.makedirs(out)
        write(os.path.join(out, PROMPT), prompt_for(case, task, work))
        flags = text(eval_corpus.must(script("tool-flags.sh", work, web),
                                      "the tools of the reviewer cannot be limited, so no review starts"))
        if not flags or "\n" in flags:
            raise Problem("tool-flags.sh did not print one line of flags, so no review starts")
        write(os.path.join(out, "tool-flags.txt"), flags + "\n")
        before = fingerprint(work)
        if not HASHES.match(before):
            raise Problem("the fingerprint of the fixture cannot be taken, so no review starts: " + before)
        record.update(flags=flags, fingerprint={"before": before})
        if not dry_run:
            write(os.path.join(out, "review.sh"), COMMAND.replace("<tool flags>", flags))
            # Before the review is spent: a results folder that cannot be made stops here.
            os.makedirs(os.path.join(results, name), exist_ok=True)
            shell = bash()
            print(f"the review of {name} is started; it takes minutes", flush=True)
            begun, spent = time.time(), True
            code = subprocess.run([shell, "../out/review.sh"], cwd=work, env=eval_corpus.own_environment(),
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL).returncode
            record["seconds"] = int(round(time.time() - begun))
            after = fingerprint(work)
            done = script("round-facts.sh", work, "../out/" + LOG)
            facts = text(done.stdout) if done.returncode == 0 else None
            if facts is not None:
                write(os.path.join(out, "facts.txt"), facts + "\n")
            leaked = names(read(os.path.join(out, LOG)), name, (corpus, results) + places, telltales(corpus, name))
            why = reasons(code, read(os.path.join(out, REVIEW)), facts, text(done.stderr) or "round-facts.sh failed",
                          before, after, leaked)
            record["fingerprint"]["after"] = after
            record.update(codex_exit=code, usable=not why, unusable=why)
        write(os.path.join(out, "record.json"), json.dumps(record, indent=2) + "\n")
        folder = keep(results, name, now.strftime("%Y%m%d-%H%M%S"), out)
        kept = True
        return folder, record
    except (OSError, Problem) as error:
        if not spent:
            raise
        raise Problem(f"the review was started, and what it left could not be kept in the results; "
                      f"it stays in {out}: {error}")
    except KeyboardInterrupt:
        # Stopped by the person: what the review left so far is named as well.
        if spent:
            print(f"eval-review: stopped after the review was started; what it left stays in {out}", file=sys.stderr)
        raise
    finally:
        # A review that was spent is deleted with its fixture only once it is kept,
        # whatever went wrong after it started.
        if kept or not spent:
            remove(holder)


def reviews(results):
    """Every review folder of the results with its record, None for a record that is
    missing or cannot be read."""
    found = []
    for name in sorted(os.listdir(results)) if os.path.isdir(results) else []:
        holder = os.path.join(results, name)
        for stamp in sorted(os.listdir(holder)) if os.path.isdir(holder) else []:
            folder = os.path.join(holder, stamp)
            if not os.path.isdir(folder):
                continue
            try:
                record = eval_corpus.read_json(os.path.join(folder, "record.json"))
            except Problem:
                record = None
            found.append((folder, record if isinstance(record, dict) else None))
    return found


def standing(corpus, repository, cases, folder, record):
    """None for a review that can be scored. Otherwise why it is left out: a word for
    the count, and the detail."""
    if record is None:
        return "no record", "record.json is missing or cannot be read"
    if record.get("dry_run") is True:
        return "dry run", ""
    if record.get("usable") is not True:
        why = record.get("unusable")
        said = isinstance(why, list) and bool(why)
        return "not usable", "; ".join(str(item) for item in why) if said else "its record does not say that it is usable"
    if not read(os.path.join(folder, REVIEW)).strip():
        return "not usable", "the review is missing"
    name = record.get("case")
    if (not isinstance(name, str) or name not in cases
            or eval_corpus.case_hash(corpus, repository, cases[name]) != record.get("label")
            or eval_corpus.definition_problems(corpus, cases, name)):
        return "case or label changed", "the case or its label is not what was reviewed"
    return None


def findings(review):
    """The findings of a review, as loop_stats.py finds them: label, tag, title, and the
    file and lines each points at, None where it names no place."""
    found = []
    for line in loop_stats.finding_lines(review)[0]:
        item = loop_stats.FINDING.match(line)
        rest = line[item.end():].strip()
        title, file, lines = rest, None, None
        # Codex ends the line with a dash and the place: a path, a colon, and the lines.
        for dash in (" \u2014 ", " - "):
            head, cut, tail = rest.rpartition(dash)
            place = PLACE.match(tail.strip()) if cut else None
            if place:
                title, file = head.strip(), place.group(1).strip().replace("\\", "/")
                lines = [int(place.group(2)), int(place.group(3) or place.group(2))]
                break
        found.append({"label": item.group(1), "tag": " ".join((item.group(2) or "none").lower().split()),
                      "title": title, "file": file, "lines": lines})
    return found


def draft(record, entry, folder):
    """A judgment that states nothing yet: the findings of a review beside the
    mechanisms of the label, and for each finding the mechanisms whose place it is at."""
    case, label = eval_corpus.parts(entry)
    mechanisms = [{"number": number, "mechanism": item["mechanism"], "trigger": item["trigger"],
                   "file": item["place"]["file"], "lines": item["place"]["lines"],
                   "severity": item["severity"], "tag": item["tag"]}
                  for number, item in enumerate(label.get("mechanisms", []), start=1)]
    listed = []
    for number, found in enumerate(findings(read(os.path.join(folder, REVIEW))), start=1):
        # Codex names a file by its whole path; a label names it from the root of the fixture.
        near = [item for item in mechanisms
                if found["file"] and (found["file"] == item["file"] or found["file"].endswith("/" + item["file"]))]
        listed.append({"number": number, **found, "same_file": [item["number"] for item in near],
                       "same_lines": [item["number"] for item in near
                                      if found["lines"][0] <= item["lines"][1] and item["lines"][0] <= found["lines"][1]],
                       "is": None, "mechanism": None, "note": ""})
    return {"how": HOW, "case": record["case"], "kind": case.get("kind"), "label": record["label"],
            "review": eval_corpus.digest(os.path.join(folder, REVIEW)), "expect": label.get("expect"),
            "known_defects": label.get("known_defects", []), "mechanisms": mechanisms, "findings": listed,
            "judged_by": "", "judged_on": ""}


def incomplete(judgment, record, entry, folder):
    """Why a judgment cannot be counted, or None."""
    if not isinstance(judgment, dict) or not isinstance(judgment.get("findings"), list):
        return "it cannot be read"
    if judgment.get("review") != eval_corpus.digest(os.path.join(folder, REVIEW)):
        return "the review is not the one it was written for"
    if judgment.get("label") != record.get("label"):
        return "it was written for another label"
    stated = judgment["findings"]
    # Each finding of the review, in its place and unchanged: report reads what a finding
    # is from the entry at the same position.
    listed = [dict(found, number=number)
              for number, found in enumerate(findings(read(os.path.join(folder, REVIEW))), start=1)]
    if len(stated) != len(listed) or not all(
            isinstance(said, dict) and all(said.get(key) == value for key, value in found.items())
            for found, said in zip(listed, stated)):
        return "it does not list the findings of the review"
    count = len(eval_corpus.parts(entry)[1].get("mechanisms", []))
    for number, found in enumerate(stated, start=1):
        what, which = found.get("is"), found.get("mechanism")
        if what is None and found["label"] not in MUST_FIX:
            continue
        if what not in IS:
            return f"finding {number} is not stated as one of: {', '.join(IS)}"
        if what == "mechanism" and not (type(which) is int and 1 <= which <= count):
            return f"finding {number} is stated as a mechanism and names none of the label"
    signer = judgment.get("judged_by")
    try:
        datetime.date.fromisoformat(judgment.get("judged_on"))
    except (TypeError, ValueError):
        signer = None
    if not (isinstance(signer, str) and signer.strip()):
        return "it is not signed with a name and a date"
    return None


def judgment_of(folder):
    try:
        return eval_corpus.read_json(os.path.join(folder, "judgment.json"))
    except Problem:
        return None


def judge(corpus, repository, results):
    """Writes a judgment file for each review that can be scored and has none. Returns
    the files written, and each judgment that cannot be counted yet with the reason."""
    places = guarded(corpus, repository)
    outside(results, places)
    cases = eval_corpus.load(corpus)
    written, waiting = [], []
    for folder, record in reviews(results):
        if standing(corpus, repository, cases, folder, record) is not None:
            continue
        path, entry = os.path.join(folder, "judgment.json"), cases[record["case"]]
        if not os.path.lexists(path):
            # The folder of a review can be a link that leads somewhere else.
            outside(folder, places)
            # "x" fails where a file stands: a judgment is never written over.
            with open(path, "x", encoding="utf-8", newline="\n") as handle:
                json.dump(draft(record, entry, folder), handle, indent=2, ensure_ascii=False)
                handle.write("\n")
            written.append(path)
        why = incomplete(judgment_of(folder), record, entry, folder)
        if why:
            waiting.append((path, why))
    return written, waiting


def spread(counts):
    return ", ".join(f"{NAMED[word]} {counts[word]}" for word in IS)


def report(corpus, repository, results):
    """The figures of the reviews that are usable and judged, as text."""
    cases = eval_corpus.load(corpus)
    left, rows, total, dry = collections.Counter(), [], 0, 0
    groups = {kind: {"reviews": 0, "cases": set(), "must_fix": 0, "is": collections.Counter(), "clean": 0,
                     "mechanisms": 0, "found": 0, "p3_only": 0, "severity": collections.Counter(),
                     "tag": collections.Counter()} for kind in eval_corpus.KINDS}
    for folder, record in reviews(results):
        where = os.path.relpath(folder, results).replace(os.sep, "/")
        out = standing(corpus, repository, cases, folder, record)
        if out and out[0] == "dry run":
            dry += 1
            continue
        total += 1
        entry = cases[record["case"]] if out is None else None
        if out is None and not os.path.isfile(os.path.join(folder, "judgment.json")):
            out = ("not judged", "it has no judgment file; judge writes one")
        judgment = judgment_of(folder) if out is None else None
        if out is None:
            why = incomplete(judgment, record, entry, folder)
            out = ("judgment not complete", why) if why else None
        if out:
            left[out[0]] += 1
            rows.append(f"  {where}: left out, {out[0]}: {out[1]}")
            continue
        case, label = eval_corpus.parts(entry)
        group = groups[case["kind"]]
        # Label and tag are read from the review; the judgment says what each finding is.
        stated = [(found, said) for found, said in zip(findings(read(os.path.join(folder, REVIEW))), judgment["findings"])
                  if said.get("is") in IS]
        must = collections.Counter(said["is"] for found, said in stated if found["label"] in MUST_FIX)
        group["reviews"] += 1
        group["cases"].add(record["case"])
        group["must_fix"] += sum(must.values())
        group["is"].update(must)
        group["clean"] += 0 if must["false alarm"] else 1
        row = f"  {where}: {case['kind']}, must-fix findings {sum(must.values())}"
        if sum(must.values()):
            row += f" ({spread(must)})"
        mechanisms, found_here = label.get("mechanisms", []), 0
        for number, item in enumerate(mechanisms, start=1):
            group["mechanisms"] += 1
            hits = [found for found, said in stated if said["is"] == "mechanism" and said["mechanism"] == number]
            if not hits:
                continue
            # The most severe finding stated as this mechanism speaks for the reviewer.
            best = min(hits, key=lambda found: SEVERITIES.index(found["label"]))
            if best["label"] in MUST_FIX:
                group["found"] += 1
                found_here += 1
            else:
                group["p3_only"] += 1
            gap = SEVERITIES.index(best["label"]) - SEVERITIES.index(item["severity"])
            group["severity"]["same" if gap == 0 else "more severe" if gap < 0 else "less severe"] += 1
            group["tag"]["same" if best["tag"] == item["tag"] else "other"] += 1
        if mechanisms:
            row += f"; mechanisms found by a must-fix finding {found_here} of {len(mechanisms)}"
        rows.append(row)
    scored = groups["defect"]["reviews"] + groups["control"]["reviews"]
    lines = [PRIVATE, "", f"Results: {results}", f"Reviews: {total}. Scored: {scored}. Left out: {total - scored}."]
    lines += [f"  {word}: {count}" for word, count in sorted(left.items())]
    if dry:
        lines.append(f"Dry runs, which are no reviews: {dry}")
    if rows:
        lines += ["", "Each review:"] + rows
    group = groups["defect"]
    lines.append("")
    if not group["reviews"]:
        lines.append("Defect cases: no review scored.")
    else:
        count, any_found = group["mechanisms"], group["found"] + group["p3_only"]
        lines += [f"Defect cases: {group['reviews']} review(s) of {len(group['cases'])} case(s), "
                  f"{count} labeled mechanism(s)",
                  f"  found by a must-fix finding: {group['found']} of {count}",
                  f"  found by a P3 finding only: {group['p3_only']} of {count}",
                  f"  not found: {count - any_found} of {count}",
                  "  severity of the finding against the label: " + ", ".join(
                      f"{word} {group['severity'][word]}" for word in ("same", "more severe", "less severe"))
                  + f", of {any_found} found",
                  "  tag of the finding against the label: " + ", ".join(
                      f"{word} {group['tag'][word]}" for word in ("same", "other")) + f", of {any_found} found",
                  f"  must-fix findings: {group['must_fix']}, of which {spread(group['is'])}"]
    group = groups["control"]
    if not group["reviews"]:
        lines.append("Controls: no review scored.")
    else:
        lines += [f"Controls: {group['reviews']} review(s) of {len(group['cases'])} case(s)",
                  f"  must-fix findings: {group['must_fix']}, of which {spread(group['is'])}",
                  f"  reviews without a false alarm: {group['clean']} of {group['reviews']}"]
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Runs a Codex review on a case of the evaluation corpus and scores reviews against labels.")
    parser.add_argument("--corpus", default=os.path.join(HERE, "eval"), help="the corpus folder")
    parser.add_argument("--repository", default=HOME, help="the repository whose history is read")
    parser.add_argument("--results", default=None, help="the folder reviews are kept in, outside this repository")
    commands = parser.add_subparsers(dest="command", required=True)
    one = commands.add_parser("run")
    one.add_argument("case")
    one.add_argument("--dry-run", action="store_true", help="do everything but start Codex")
    one.add_argument("--web", choices=WEB, default="off", help="the web search mode of the review; off by default")
    commands.add_parser("judge")
    commands.add_parser("report")
    options = parser.parse_args(argv)
    try:
        corpus, repository = os.path.abspath(options.corpus), eval_corpus.checkout(os.path.abspath(options.repository))
        results = (os.path.abspath(options.results) if options.results
                   else default_results(options.command != "report", guarded(corpus, repository)))
        if options.command == "run":
            folder, record = run(corpus, repository, results, options.case, options.dry_run, options.web)
            print(f"review: {folder}")
            if options.dry_run:
                print("dry run: Codex was not started. The review would start with: "
                      "codex exec review -c 'sandbox_mode=\"read-only\"' " + record["flags"])
                return 0
            print(f"seconds: {record['seconds']}")
            print("usable: " + ("yes" if record["usable"] else "no"))
            for why in record["unusable"]:
                print(f"  {why}")
            return 0 if record["usable"] else 1
        if options.command == "judge":
            written, waiting = judge(corpus, repository, results)
            for path in written:
                print(f"written: {path}")
            for path, why in waiting:
                print(f"to complete: {path}: {why}")
            print(f"{len(written)} judgment(s) written, {len(waiting)} to complete")
        else:
            print(report(corpus, repository, results))
    except (Problem, ValueError, OSError) as error:
        # Also a file that cannot be written, and a bash or a git that is not installed.
        print(f"eval-review: {error}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("eval-review: stopped", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
