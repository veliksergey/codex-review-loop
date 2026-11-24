---
name: codex-loop
description: Run the Codex (ChatGPT) code-review loop on the current uncommitted changes, on a branch compared with a base, or on specific files and folders; a target with no uncommitted changes is audited as existing code without a task file. Codex reviews read-only against the user's request in the task file; Claude verifies every finding, fixes valid P0-P2 findings with regression tests, lists P3 items for the user, and re-reviews, up to 3 rounds. Use after finishing an implementation task in a git repository, or when the user asks for a Codex review, a ChatGPT review, a second opinion, or a review loop.
argument-hint: "[paths...] [--base <ref>] [--focus \"text\"] [--rounds N] [--model <slug>] [--effort <level>] [--web cached|live|off] [--allow-tools] [--report-only]"
allowed-tools: Bash(codex login status), Bash(git rev-parse --show-toplevel), Bash(git status --short --untracked-files=all), Bash(git diff), Bash(git diff --cached), Bash(bash "${CLAUDE_SKILL_DIR}/fingerprint.sh"), Bash(bash "${CLAUDE_SKILL_DIR}/tool-flags.sh"), Bash(bash "${CLAUDE_SKILL_DIR}/tool-flags.sh" live), Bash(bash "${CLAUDE_SKILL_DIR}/tool-flags.sh" off), Bash(bash "${CLAUDE_SKILL_DIR}/round-facts.sh"), Bash(bash "${CLAUDE_SKILL_DIR}/log-dir.sh"), Bash(bash "${CLAUDE_SKILL_DIR}/instruction-changes.sh"), Bash(bash "${CLAUDE_SKILL_DIR}/task-hash.sh"), Bash(date +%Y%m%d-%H%M%S), Bash(wc -l), Read, Edit(~/.claude/codex-reviews/**), Edit(docs/reviews/decisions.md), Grep, Glob
---

# Codex review loop

You are the implementer. Codex, signed in with the user's ChatGPT account, is the
independent reviewer and runs read-only. This skill sends Codex the change together
with the user's request, verifies every finding, fixes what the policy allows, and
repeats until a review finds nothing to fix or the round limit is reached. The user
watches the terminal: show them everything Codex says, verbatim.

This file is long, and after a compaction Claude Code can keep only its start (observed
2026-11-23: the copy it kept ended in step 4). If your copy of this skill ends before
step 8, read `${CLAUDE_SKILL_DIR}/SKILL.md` in full before you go on: steps 6 to 8 hold
the rules for triage, the second look, the rebuttal, and the final report.

Arguments received: `$ARGUMENTS`

## 1. Parse the arguments

| Argument | Meaning | Default |
|---|---|---|
| `paths...` | Files or folders to review, relative to the repository root. Their current contents on disk are reviewed, plus the uncommitted changes touching them. A target with no uncommitted changes and no task file that names it is an audit of existing code (step 2, item 5). | none: review all uncommitted changes |
| `--base <ref>` | Review every change on the current branch relative to `<ref>`, for example `main`, plus the uncommitted changes. | off |
| `--focus "text"` | Extra focus for the reviewer, for example `"open redirects and token audience"`. | none |
| `--rounds N` | Maximum review rounds. | 3 |
| `--model <slug>` | Model for this review. Passed to Codex as both `-m <slug>` and `-c review_model="<slug>"`, so it beats the `review_model` default in any config file. | `review_model` from the repository's `.codex/config.toml` if the repository is trusted, else from `~/.codex/config.toml`, else the session model: the effective `model` setting (a trusted repository's `.codex/config.toml` outranks `~/.codex/config.toml`), else the account default |
| `--effort <level>` | Reasoning effort for this review, passed as `-c model_reasoning_effort="<level>"`. One of `low`, `medium`, `high`, `xhigh`; some models accept more levels such as `max` or `ultra`. | `model_reasoning_effort` from config, else the Codex default |
| `--web <mode>` | Web search for this review: `cached`, `live`, or `off`. `off` leaves the reviewer without a web tool. | `cached` |
| `--allow-tools` | Let the reviewer use the connectors, plugins, and MCP servers of the user's own Codex setup in this review. | off: those tools are turned off |
| `--report-only` | One round, show the findings, change nothing. | off |

`--web off` and `--allow-tools` cannot be combined: the user's own connectors include
web search. If both are given, stop and ask the user to drop one. Never add `--web` or
`--allow-tools` yourself; use them only when the user gave them for this run.

Scope modes, all built from [review-prompt.md](review-prompt.md) in this skill's
directory (`${CLAUDE_SKILL_DIR}/review-prompt.md`):

- **uncommitted** (default): no paths, no `--base`.
- **branch**: `--base` given. The scope block asks for the committed changes since
  the merge base plus the uncommitted changes, so fixes can stay uncommitted between
  rounds.
- **paths**: paths given.

`--focus` combines with any mode. Never pass `--uncommitted` or `--base` to Codex:
it rejects those flags together with a prompt. Scope is expressed in the prompt.

## 2. Preconditions

Stop and tell the user if one fails.

1. `git rev-parse --show-toplevel` must succeed. Codex review needs a git repository.
   Keep the output as `REPO_ROOT`; its basename is `REPO`. Then run
   `bash "${CLAUDE_SKILL_DIR}/log-dir.sh"` exactly as written. It must succeed too, and
   the one line it prints is the log folder, `LOG_DIR`. It fails when another
   repository with the same folder name already uses that folder, because the two
   would share one task file and one set of logs. Show its message and stop, without
   reading or writing anything in that folder.
2. `codex login status` must print `Logged in`. Otherwise tell the user to run
   `!codex login` and stop.
3. The repository's documented checks must pass on the current tree. Read the
   repository's `AGENTS.md` and `CLAUDE.md` for the exact commands, for example
   `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm build`. Do not send failing code
   to review. If no checks are documented, say so and continue.
4. If `git status --short --untracked-files=all` shows a new secret-bearing file
   such as `.env` or a key file, stop and ask before reviewing.
5. The task file `$LOG_DIR/task.md` (`LOG_DIR` is the folder from item 1) must
   describe the change under review. It is the user's request, the acceptance criteria, the
   decisions made while implementing, and the handoff, in the shape of
   [task-template.md](task-template.md) (`${CLAUDE_SKILL_DIR}/task-template.md`).
   Codex judges the change against it.
   Decide the task basis with the first rule that matches. Rules that match need
   no question to the user.
   - **Audit mode**, paths mode only: `git status --short --untracked-files=all -- <paths>`
     prints nothing, and `task.md` is missing or mentions none of the target paths
     (`grep -F` each path against it). The user is reviewing existing code, not a
     change. Print one line: "Audit of <paths>: no task file applies, Codex reviews
     the code as it stands on disk; valid P0-P2 findings will be fixed unless
     --report-only". Use the no-task line for `{{TASK}}` in step 4. Leave `task.md`
     on disk untouched; it belongs to another task.
   - Present, and it names the target or describes the uncommitted changes: print
     its `## Request` section and its modification time (`ls -l`) so the user can
     see which task is being reviewed, then continue.
   - Present, but it plainly describes a different change than the working tree
     holds: ask before continuing, with "no requirement" as one of the answers.
   - Missing, and you implemented the change in this session: create it now from
     the conversation. The request goes in verbatim, not paraphrased.
   - Missing otherwise, with changes in scope: ask the user for the request in one
     or two lines, or to say "no requirement". Without a task file, the prompt says
     so and Codex reviews scope only; the report must state this.

   Audit mode, a "no requirement" answer, and a missing task file all make this a
   **no-task run**: the whole loop uses the no-task line for `{{TASK}}` and never
   writes to or archives `task.md`, which is absent or belongs to another task.
   Steps 7 and 8 say what to do instead.
   - Before round 1, when a task file is used, its `## Handoff` section must be
     complete: files changed, tests added and what each proves, assumptions, check
     results, risks.
6. Uncommitted mode with nothing to review: if `git status --short --untracked-files=all`
   prints nothing, stop and tell the user so. Suggest paths for an audit of existing
   code, or `--base <ref>` for a branch.

## 3. Prepare the log directory outside the repository

Logs never go inside the repository: untracked files there become part of the next
uncommitted review. `LOG_DIR` is the folder `log-dir.sh` printed in step 2,
`~/.claude/codex-reviews/<REPO>`; the script has created it. Take the run id once, for
all rounds, with `date +%Y%m%d-%H%M%S`. It is `RUN`.

Files in `LOG_DIR`:

- `repository-root.txt`: which repository this folder belongs to. Leave it alone.
- `task.md`: the current task file, written at task start and updated until the
  loop ends. Overwritten when the next task starts.
- `<RUN>-task.md`: archived copy of the task file as it stood at the final report,
  or a one-line note when no task file was used.
- Per round `N` (substitute the round number yourself):
  - `<RUN>-round<N>-prompt.md`: the exact prompt sent to Codex.
  - `<RUN>-round<N>-codex.md`: Codex's final review, written by Codex through `-o`.
  - `<RUN>-round<N>-codex.log`: Codex's progress log and session id (stderr).
  - `<RUN>-round<N>-claude.md`: your triage table, the overrides with their second
    looks, the requirement checklist, and the judge record.
  - `<RUN>-round<N>-rebuttal-prompt.md`, `-rebuttal-codex.md`, and
    `-rebuttal-codex.log`: the same three files for the round's rebuttal, when step 6
    runs one.
- `<RUN>-summary.json`: the run in a fixed shape, written at the final report.

## 4. Run a round

Estimate the size first with `git status --short --untracked-files=all | wc -l`, or
`git diff --stat <ref>...HEAD` in branch mode, or the number of target files in
paths mode. Up to 10 files: run in the foreground with the Bash tool and
`timeout: 600000`. More than 10 files, a whole folder, or unknown size: run with
`run_in_background: true` and continue when the completion notification arrives. Say
which you chose.

When a task file is used, run `bash "${CLAUDE_SKILL_DIR}/task-hash.sh"` exactly as
written before every round and before the final report. It prints a hash of the request
and the acceptance criteria. Keep the first value. A later value that differs means one
of the two changed during this run: tell the user at once, show both sections as they
now stand, and name the change in the final report. If it exits non-zero, stop.

### Build the prompt

Read `${CLAUDE_SKILL_DIR}/review-prompt.md` and replace four placeholders:

`{{SCOPE}}`, by mode:

Uncommitted:

```text
Target: all uncommitted changes in this repository: staged, unstaged, and untracked
files. Collect them yourself:
1. `git status --short --untracked-files=all` lists every changed and untracked file.
2. `git diff` and `git diff --cached` show the tracked changes.
3. Read every untracked file from step 1 in full. It is new code under review.
4. Read the whole of each changed file, not only the hunks, because a defect in
   unchanged lines that the change relies on still counts.
```

Branch (substitute `<base>` and `<ref>`):

```text
Target: all changes on the current branch since `<base>`, its merge base with `<ref>`,
plus any uncommitted changes. Collect them yourself:
1. `git diff <base>...HEAD --stat`, then `git diff <base>...HEAD`, for the committed
   changes since the merge base.
2. `git status --short --untracked-files=all`, `git diff`, `git diff --cached`, and
   every untracked file in full, for the uncommitted changes.
3. Read the whole of each changed file, not only the hunks, because a defect in
   unchanged lines that the change relies on still counts.
```

`<base>` is the commit that `git merge-base <ref> HEAD` prints, resolved once per round
before its prompt is built; if the command fails, stop and report its message. The
round's prompt, `instruction-changes.sh`, the second looks, and the rebuttal all use
that commit, so a `<ref>` that moves during the round changes nothing they judge.

Paths (one repository-relative path per line):

```text
Target files and folders, relative to the repository root:
<paths>
Review the current contents of the target as it exists on disk. Start with
`git status --short --untracked-files=all -- <target>`, `git diff -- <target>`, and
`git diff --cached -- <target>` to see what changed recently, then read the whole
files. Defects that already exist in the target are in scope, and a finding does not
have to overlap a recent change: the rules in your built-in guidelines against
flagging existing bugs, and for findings that overlap the diff, do not apply to this
review.
```

`{{FOCUS}}`: the focus text, or `none`.

`{{TASK}}`: the full contents of `$LOG_DIR/task.md`, or, in audit mode or when the
user chose to proceed without one, the single line
`No task file was provided. Review the scope only and say so in your summary.`

`{{INSTRUCTIONS}}`: the output of `bash "${CLAUDE_SKILL_DIR}/instruction-changes.sh"`,
run exactly as written before every round, pasted unchanged; in branch mode run it with
the round's `<base>` as its one argument. It lists the instruction files the change
edits: `AGENTS.md`, `AGENTS.override.md`, and `CLAUDE.md` in any folder, anything
under a `.codex` folder, and `docs/reviews/decisions.md`. It prints `none` when there
are none.
The prompt tells the reviewer to apply the committed version of each listed file, to
review the edit, and to check once every new row of `docs/reviews/decisions.md`. When
files are listed, name them to the user before the round. If the script exits non-zero,
stop and report its message.

Write the result to `$LOG_DIR/$RUN-round$N-prompt.md` with the Write tool. Confirm
no `{{` remains.

### Run Codex

One command runs Codex and then prints the working-tree fingerprint, so nothing can
change the tree between the review and the second fingerprint:

```bash
date +%s; codex exec review -c 'sandbox_mode="read-only"' <tool flags> -o "$LOG_DIR/$RUN-round$N-codex.md" - < "$LOG_DIR/$RUN-round$N-prompt.md" 2> "$LOG_DIR/$RUN-round$N-codex.log"; echo "codex exit: $?"; date +%s; bash "${CLAUDE_SKILL_DIR}/fingerprint.sh"
```

The number it prints first and the number after the `codex exit:` line are times in
seconds. Their difference is the round's duration. Codex layers the prompt on top of its
own built-in review guidelines, which stay as base instructions (verified 2026-09-08).

`<tool flags>` decide which tools the reviewer has besides its sandboxed shell. Before
every round, not only the first, get them from the one command in this table that fits
the run, exactly as written:

| Run | Where `<tool flags>` come from |
|---|---|
| default | `bash "${CLAUDE_SKILL_DIR}/tool-flags.sh"` |
| `--web live` | `bash "${CLAUDE_SKILL_DIR}/tool-flags.sh" live` |
| `--web off` | `bash "${CLAUDE_SKILL_DIR}/tool-flags.sh" off` |
| `--allow-tools` | no command: use `-c 'web_search="cached"'`, or `"live"` with `--web live` |

The script prints one line and that line is `<tool flags>`: the flags that turn off
Codex's plugins, its connectors other than web search, and every configured MCP server.
Before it prints, it asks Codex which MCP servers are enabled and which tools a session
with those flags would be offered. It prints nothing if an MCP server is still enabled,
or if a tool whose name marks it as one of a connector, a plugin, or an MCP server,
`mcp__...`, is offered besides web search, for example by a connector that a
configuration file turns on by name. A connector that offers no tool is not seen, nor
a tool that Codex names without that prefix, as it can for some servers (source of
Codex 0.171.0, `codex-rs/codex-mcp/src/tools.rs`); Codex's own tools are not part of
the check: they stay on. Run it again before each round: a fix, or the user, can
change a Codex configuration file between rounds. If it exits non-zero, stop: the
reviewer's tools cannot be limited. Show the user its message and say that
`--allow-tools` runs the review with their own tools instead.

Web search reaches the reviewer as a Codex connector, which is why the default keeps
that one connector on. Observed 2026-11-13: with the apps feature disabled the reviewer
has no web tool, and `cached` and `live` made no difference to what the search tool
fetched. The script reads the tools Codex declares for a session, in each place it
declares them, and not the instructions printed beside them.

Rules for the command:

- When `--model` was given, add `-m <slug> -c review_model="<slug>"` directly after
  `review`. Both are needed: a `review_model` line in a config file would otherwise
  decide the review model.
- When `--effort` was given, add `-c model_reasoning_effort="<level>"`.
- Know which model and effort the review really used. The `.log` header line
  `model:` shows the session model, which can differ from the review model when
  `review_model` is set in config. The review model is the `--model` value if given,
  else `review_model` from the repository's `.codex/config.toml`, else from
  `~/.codex/config.toml`, else the session model from the `.log` header: without
  `review_model`, a review runs on the session model (OpenAI configuration
  reference, checked 2026-10-05). Read those lines with `grep` when you report.
- Do not add `--ephemeral`; it would prevent `codex resume` later.
- Always keep `-c 'sandbox_mode="read-only"'`. In a repository marked trusted in
  `~/.codex/config.toml`, Codex defaults to `workspace-write`, which would let the
  reviewer edit files; the override forces read-only regardless of trust. After the
  run, confirm the `.log` header line `sandbox:` says `read-only`, and report it if
  it does not.
- Never add `-s workspace-write`, `-a`, `--approve-for-me`, or
  `--dangerously-bypass-approvals-and-sandbox`.
- Check that the reviewer changed nothing. Before the run, record the output of
  `bash "${CLAUDE_SKILL_DIR}/fingerprint.sh"`, run exactly as written: four hashes,
  of the commit with the file status, the unstaged diff, the staged diff, and the
  bytes of tracked and of untracked files as they are on disk, with links recorded by
  where they point, and a submodule or another repository inside this one recorded by
  its own four hashes. The Codex
  command prints the second fingerprint at its end; edit nothing in the repository
  while it runs, and compare the two. If the second run printed an error in place of
  four hashes, stop the loop and report it: a fingerprint that failed proves nothing.
  If any hash differs, stop the loop, show `git status --short`, and tell the user
  that the working tree changed during the review.
  Files git ignores are not covered. For those the guarantee is the read-only
  sandbox, which limits the reviewer's shell commands, together with the other
  tools being off unless the user allowed them.
- If the `.log` contains `CreateProcessWithLogonW failed: 1385`, Codex could not
  start its persistent Windows sandbox shell and is retrying command by command.
  The review normally still completes. Mention it in the report and point to
  OpenAI's Windows sandbox page: https://learn.chatgpt.com/docs/windows/windows-sandbox
- If the `codex exit:` line shows a number other than 0, read the `.log` file, quote
  its last meaningful lines to the user, and stop the loop. A usage-limit message
  means the ChatGPT allowance is exhausted: report it and stop.

### Read the round's facts

Run `bash "${CLAUDE_SKILL_DIR}/round-facts.sh"` exactly as written. It reads the
newest round log of this repository, which is the round that just ended, and prints
what the reviewer ran: the Codex CLI version, model, effort, and sandbox from the log
header, the shell commands that started, ran, and failed to start, and each tool
called outside the shell. If it exits non-zero, stop the loop and report its error.
Its `log=` line must name `$RUN-round$N-codex.log`: when it names another log, such as
one that another review wrote into the same folder since, the facts are not this
round's, so stop the loop and report it.

Stop the loop and report the review as failed, without triaging its output, when:

- `shell_usable=no`. No sandboxed shell command ran, so the reviewer did not read the
  code through the sandbox, whatever it wrote. Report `shell_started` and
  `shell_start_failed`, suggest `codex update`, and on Windows point to
  https://learn.chatgpt.com/docs/windows/windows-sandbox.
- `other_tool_calls` is not 0 in a run without `--allow-tools`, and at least one of
  those calls is real. A tool that should be off was called. Show the `tool=` lines.
  That includes the three tools of Codex's own for the resources of MCP servers,
  `list_mcp_resources`, `list_mcp_resource_templates`, and `read_mcp_resource`: no
  setting that the loop can use turns them off (Codex 0.171.0, checked 2026-11-23),
  and a call of one that the log records stops the review all the same. Observed
  2026-11-20: `round-facts.sh` printed such a call as `tool=codex/list_mcp_resources`.
  A call that Codex rejects before it runs, such as a read from a server that does not
  exist, leaves no such line and reaches no server (source of Codex 0.171.0, read
  2026-11-23).
- `web_search_calls` is not 0 in a run with `--web off`, and at least one of those
  calls is real.

The facts are read from Codex's log, whose format is not documented, and the log also
holds the text of every command the reviewer ran and everything those commands
printed. A line there with the exact shape of a log event is counted as an event.
Observed 2026-11-13: a reviewer testing a script against a made-up log produced such a
line. So before stopping for a tool call, read the log at every line number in the
`lines=` list of each `tool=` line concerned, not only the first: the same tool can
appear once as printed text and once as a real call. A real call stands on its own
between two commands. A line inside the text of a command, or inside what a command
printed, is not a call. Go on only when every listed line is such text, and say so in
the facts line. One real call, or one line you cannot place, stops the loop. The same
doubt applies to `shell_usable=yes` when the only lines that look like a command having
run sit inside the text of another command; treat that round as `shell_usable=no`.

## 5. Show the review verbatim

Read `<RUN>-round<N>-codex.md` and print it to the user unchanged inside a fenced
block headed `Codex review, round N of M (review model: <slug>, effort: <level>)`,
using the model and effort determined in step 4. Do not summarize, soften, or
reorder it. Add the session id from the `.log` (`grep "session id:"`) so the user
can open the full transcript with `codex resume <session-id>`.

Under the block, print the round's facts on one line, taken from step 4:
`Reviewer: Codex CLI <codex_cli>, sandbox <sandbox>, <shell_ran> of <shell_started>
shell commands ran, <web_search_calls> web searches, <other_tool_calls> other tool
calls`, followed by the tool names when there are other tool calls.

Codex renders its result as a short summary followed by `Full review comments:`,
one finding per bullet as `[Pn] Title — <absolute path>:<lines>` with a
one-paragraph body. That shape comes from Codex's own output schema and the prompt
cannot change it. Requirement findings carry `(criterion N)`, `(beyond request)`, or
`(handoff)` at the start of the title.

Mention check, uncommitted and branch modes: for every untracked file in scope
(from `git status --porcelain --untracked-files=all`, lines starting with `??`,
excluding `docs/reviews/`), look for its file name in the round's `.log` or `.md`.
A name that appears nowhere means Codex never looked at the file. List any such
file in the report and, if the loop continues, add it as a path in a targeted
paths-mode round. A name that does appear shows only that the file was mentioned,
not that it was read in full or reviewed.

## 6. Triage every finding

Treat each finding as a testable claim. Open the cited file and lines, trace the
code path, or reproduce it with a test before deciding. Convert Codex's absolute
paths to repository-relative paths in your table. Codex's severity label is a
proposal: in testing the same fact was rated P1 in one run and P2 in another, and on
2026-11-13 a defect that deleted stored data was rated P1 in every seeded review,
although the scale makes it P0 and the prompt says so. Set the severity yourself from the scale
in `review-prompt.md`. The triage table keeps both labels, Codex's and yours.

| Outcome | Rule |
|---|---|
| Valid, P0 / P1 / P2 | Fix it with the smallest cohesive change, once the round's second looks and rebuttal below are done. Add or extend a regression test that fails before the fix and passes after. |
| Valid, P3 | Do not fix unasked. Put it on the "awaiting your decision" list in the final report. When Codex labeled it P0 to P2, this is an override: take the second look below first. |
| Invalid | Reject only with concrete evidence: a code path, test output, or primary documentation. A rejection is an override: take the second look below first, and the rebuttal below when Codex labeled the finding P0 or P1, before you record it. Add a row to `docs/reviews/decisions.md` in the repository; if it is missing, create it from the setup skill's template, `${CLAUDE_PLUGIN_ROOT}/skills/setup/templates/repo-decisions.md`; when that path does not resolve because the skill was installed by hand, outside a plugin, create it with a `# Review decisions` heading and the table header `\| Date \| Finding \| Severity claimed \| Decision \| Evidence \|`. With `--report-only`, do not touch the repository: keep the rejection and its evidence in the round's `-claude.md` only. |
| Outside the task's scope | Do not implement. List it for the user as a follow-up. |
| Already recorded in `docs/reviews/decisions.md` | Do not fix. Mark it "disputed twice" and escalate to the user in the final report. |

Requirement findings follow the same table with these specifics:

- `(criterion N)` not met: a valid one is P1. Fix the code, not the criterion.
- `(beyond request)`: valid when the change adds behavior the request and the
  task file's decisions do not cover. Remove the addition, or, if the user asked for
  it in conversation, quote the user's words in the task file's Decisions section,
  marked `[user, <date>]`, and reject the finding with that evidence.
- `(handoff)` claim not supported: fix the thing the claim was about, for example
  add the missing test. If the claim was wrong but the code is right, correct the
  Handoff section and say so in the triage table.
- Never edit the task file to make a finding disappear. It changes only to record a
  user decision or to correct a factual claim about the code.

### Second look at an override

An override is a finding you reject, or one that Codex labeled P0 to P2 and you label
P3, unless you decide it `outside scope` or it is `disputed twice`: your judgment on
your own work, against the reviewer's. Before you record one, another Claude agent
checks the finding in a fresh context. Do this for each override, also with
`--report-only`, and before any rebuttal.

Decide every finding of the round, take each second look, and run the rebuttal before
you write anything in the repository: no fix and no row of
`docs/reviews/decisions.md`. The agent and the rebuttal judge the code on disk, which
must still be the code the review saw: a fix made first can close a finding that was
valid, and the rejection would then be recorded in place of the fix. So when the
second looks are done, and before the rebuttal or any write, run `fingerprint.sh` as
step 4 does: it must print the fingerprint that the round's command printed at its
end. If it differs, the repository changed after the review: stop the loop, show
`git status --short`, and tell the user, as step 4 does.

Call the Agent tool once per override, with `subagent_type` set to
`codex-review-loop:finding-checker`, the plugin's agent that can only read files. Its
prompt holds these parts and nothing else:

1. `Repository root:` and `REPO_ROOT`, then `Scope of the review:` and the round's
   target, in the words a rebuttal gives it below (`<target of the round>`). Except in
   paths mode and in an audit, whose target is the files as they are on disk, when
   some changes are staged, that is, when
   `git -C "$REPO_ROOT" diff --cached --name-only` prints a path, add the line
   `The staged version of <path> differs from the file on disk.` for each path where
   the two differ, whichever files the finding names: each path that
   `git -C "$REPO_ROOT" diff --name-only` or
   `git -C "$REPO_ROOT" ls-files --others --exclude-standard` prints, and each path
   that `git -C "$REPO_ROOT" diff --cached --name-only --no-renames --diff-filter=D`
   prints and that is still on disk, such as a file removed from the index and ignored
   since. A finding about what is staged can turn on any of them. Run from the root,
   these commands name each file by its path from the root.
2. `Finding:` and the finding as Codex wrote it in the round's `-codex.md`: its title
   with the path and the line range that follow it, and its body, without its label
   `[P0]` to `[P3]`.
3. `Severity scale:` and the `<severity>` section of
   `${CLAUDE_SKILL_DIR}/review-prompt.md`, copied unchanged.
4. Only for a requirement finding in a run with a task file: `The user's request:` and
   the task file's `## Request (verbatim)` and `## Acceptance criteria` sections,
   copied unchanged, and of each decision marked `[user, <date>]`, that mark and the
   user's quoted words only. The text after the quote is yours: it says what you made
   of the user's words.
5. Only when `instruction-changes.sh` listed files for the round:
   `Instruction files the change edits:` and the lines it printed, then, for each
   listed `AGENTS.md`, `AGENTS.override.md`, or `CLAUDE.md` that the change does not
   add, `Committed version of <path>:` and what `git show <base>:<path>` prints, with
   the base it printed, copied unchanged. The agent starts without your and the
   project's `CLAUDE.md` files, and the files on disk hold the change's own version of
   these rules.

Add nothing else: not your decision, your evidence, Codex's label, the handoff, or
your own decisions. The agent judges the finding, not your argument about it, and a
checker that sees the implementer's reasoning tends to agree with it. Do not reword or
shorten the finding either, even where it quotes the handoff, a decision, or a row of
`docs/reviews/decisions.md`: rewording would let you reshape the claim the agent
judges. The agent gives such quoted text no weight as evidence.

The first line of its answer must be `Instruction files: none`. Any other first line
means that your or the project's instruction files reached the agent: at its start, as
under a Claude Code older than 2.1.271, which ignores `omitClaudeMd`, or while it
worked in a folder that has its own `CLAUDE.md` or rules, which Claude Code adds even
with `omitClaudeMd`; or that a line of your records reached it, from
`docs/reviews/decisions.md` or this loop's log folder, as a search can bring one. Write
`not run` for its second look; the final report says why.
Otherwise read the rest. The answer is complete when it has the `Verdict:`,
`Severity:`, and `Evidence:` lines of the agent's shape, its severity fits its verdict,
`none` for `does not hold` and P0 to P3 for `holds`, and its evidence names at least
one place in the code as `path:line`. A complete answer decides the second look:

| Override | The second look agreed | It disagreed |
|---|---|---|
| Rejected | `does not hold` | `holds`, at any severity |
| Labeled P3 | `does not hold`, or `holds` at `P3` | `holds` at P0 to P2 |

Any other answer, `cannot tell` or one that is not complete among them, is
`could not tell`.

- Agreed, or could not tell: keep the override, and take the rebuttal below when it
  applies. The final report names each `could not tell`.
- Disagreed: open the files and lines the agent names and trace its code path. If its
  evidence changes your judgment, decide again by the table above: fix a finding that
  holds at P0 to P2 with a regression test, and list one that holds at P3 when the
  agent found P3 too. A new decision that the agent's answer contradicts is still an
  override against it: a rejection, or P3 for a finding it found at P0 to P2. If you
  hold such an override, the decision is `escalated`: do not fix it, add no row to
  `docs/reviews/decisions.md`, put the agent's evidence beside yours in the triage
  file, and stop the loop after this round. An escalated finding gets no rebuttal: the
  user decides it.

When the Agent tool does not offer `codex-review-loop:finding-checker`, as when the
skill was installed by hand outside the plugin, or when the call fails, keep the
override and write `not run` for its second look; the final report says so. Never ask
another agent instead: only this one is limited to reading.

### Rebuttal of a rejected P0 or P1

A finding that Codex labeled P0 or P1 and that is still rejected after its second look
gets one rebuttal before its row in `docs/reviews/decisions.md` is written. A round
has at most one rebuttal: run it after every finding of the round is triaged, covering
each such finding. It does not count toward `--rounds`. With `--report-only` there is
none; write `not run` for the rebuttal of each such finding.

1. Build its prompt as step 4 builds a round's. `{{SCOPE}}` is the rebuttal scope
   below. `{{FOCUS}}` and `{{TASK}}` are the texts that the round's own prompt,
   `$LOG_DIR/$RUN-round$N-prompt.md`, held in their places: the focus after
   `Extra focus from the user:`, and the task between `<task>` and `</task>`.
   `{{INSTRUCTIONS}}` is what `instruction-changes.sh` printed for the round,
   unchanged. The rebuttal judges what the review judged: a change you made to the
   task file since, such as a corrected handoff claim, goes into your evidence.
   Write the prompt to `$LOG_DIR/$RUN-round$N-rebuttal-prompt.md`.
2. Run it as step 4 runs a round, under the same rules: record the fingerprint first,
   get the tool flags again, add what `--model` and `--effort` add to a round, and
   write `round$N-rebuttal` where the command's three file names have `round$N`. The
   fingerprint recorded first must equal the one the round's command printed at its
   end, as must the one the rebuttal's command prints: the rebuttal judges the code
   the review saw.
3. Read its facts with `round-facts.sh` as step 4 does. It reads the newest log, so
   its `log=` line must name `$RUN-round$N-rebuttal-codex.log`. Show the rebuttal's
   review verbatim, as step 5 shows a round's.
4. The rebuttal has failed when step 4 would stop it as a failed review, when it exits
   non-zero, when one of its fingerprints differs from the round's, when the `log=`
   line names another log, or when its review file is missing or holds nothing but
   whitespace: there is then no answer to read. Mark each finding it covered
   `escalated` and stop the loop.

Rebuttal (substitute the round's target, and write one numbered entry per finding):

```text
Target: a rebuttal, not a new review. Your last review of this change reported the
findings below, and the implementer rejected each of them with the evidence that
follows it. The change is the one that review covered: <target of the round>.
For each finding, decide whether it still holds, by checking the finding and the
evidence against the version of the code it is about: the file on disk, or the
staged version that `git diff --cached` shows, where the finding is about that one.
A change given as files as they are on disk is judged on disk, whatever version a
finding names.
- The implementer of the change wrote the evidence. It is a claim to verify, not a
  fact: do not defer to it.
- In your summary, name each finding by its number and say `withdrawn` or
  `maintained`. Withdraw a finding only when you verified that the evidence is right:
  in the code, in the output of a command you ran, in primary documentation, or, for
  what was asked, in a decision of the task that quotes the user.
- Report each finding you maintain again, as a finding with its label, and answer the
  evidence in its body with the code path or the output that shows it still holds.
- Report nothing else: apply <requirement_check> and <rubric> only as far as they
  bear on these findings.

<N>. <the finding as Codex wrote it: label, title, path and line range, and body>
Implementer's evidence: <the evidence in its row of the findings table>
```

`<target of the round>`, by the round's mode:

- Uncommitted: `all uncommitted changes in this repository`.
- Branch: `all changes on the current branch since <base>, its merge base with <ref>,
  plus any uncommitted changes`, with the round's `<base>` from step 4, which stays put
  if `<ref>` moves before the rebuttal.
- Paths, and an audit: `the files and folders <paths>, as they are on disk. Defects
  that already exist in them are in scope, and a finding does not have to overlap a
  recent change: the rules in your built-in guidelines against flagging existing
  bugs, and for findings that overlap the diff, do not apply`. The paths scope text
  of step 4 says the same to a round.

Read the answer for each finding:

- `withdrawn`: the summary says so, and the review does not report the finding again.
  Record the rejection, and say in its `docs/reviews/decisions.md` row what the second
  look and the rebuttal found.
- `maintained`: any other answer. Trace the reviewer's answer as you traced the
  finding. If it shows that the finding holds, decide again by the table above;
  otherwise the decision is `escalated`, and the loop stops after this round.

A finding that the rebuttal reports without being asked is not triaged in this round:
list it in the triage file and in the final report as reported by the rebuttal.

### The triage file

With `--report-only`, the repository is not written at all: no fixes and no
`docs/reviews/decisions.md` row. Triage into the round's `-claude.md` as usual, with
the second look and without a rebuttal, then go to the final report after one round.

Write `<RUN>-round<N>-claude.md` in the shape of
[triage-template.md](triage-template.md) (`${CLAUDE_SKILL_DIR}/triage-template.md`),
and keep its headings, table columns, and decision words as they are. It has four
parts:

- The findings table: one row per finding, with Codex's label, your label, one
  decision word, the evidence, and the proof. Proof is the test with its failing and
  passing result, or the reason no test is possible.
- The overrides table: one row per finding you rejected or moved from P0-P2 to P3
  before its second look, also when the second look changed your decision, with what
  the second look and the rebuttal found.
- The requirement checklist: one row per acceptance criterion, with its state and
  who verified that state: the reviewer, the implementer, or nobody. Take `reviewer`
  only from what the review says it checked, and only for a criterion you have not
  changed since. A criterion you fixed this round is in a state no reviewer has seen.
  It, and a criterion the review could not check or does not mention, is
  `implementer` when a test or check you ran shows it, and `nobody` otherwise.
- The judge record: the plugin's version, every line `round-facts.sh` printed in
  step 4, the web search mode, whether `--allow-tools` was given, and the four hashes
  of the round's fingerprint. The version is the `version` in
  `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`; write `unknown` when that path
  does not resolve because the skill was installed by hand. A round with a rebuttal
  has a second judge record, of the rebuttal.

## 7. Close the round

- If you changed code, rerun the repository's documented checks and fix any failure
  before the next round.
- Update the task file: append decisions made while fixing, and bring the Handoff
  section up to date so the next round reviews current claims, not stale ones.
  In a no-task run, leave `task.md` alone and record the decisions made while
  fixing in the round's `-claude.md` instead.
- Start the next round when something was fixed and `N` is below `--rounds`.
- Stop when the review reported no P0-P2 findings, when nothing changed this round,
  when `N` reached `--rounds`, when a finding was disputed twice or escalated, when
  Codex failed, when the round's facts in step 4 made the review a failed one, when
  the rebuttal failed, or when the user interrupts.

Never commit, push, tag, or run release scripts as part of the loop.

## 8. Final report

Archive the task file first: read `$LOG_DIR/task.md` and write its contents unchanged
to `$LOG_DIR/$RUN-task.md` with the Write tool. Leave `task.md` in place; the next
task overwrites it. In a no-task run do not copy it: write `$LOG_DIR/$RUN-task.md`
with one line naming the scope and the reason, for example "Audit of <paths>,
<date>: no task file used; task.md on disk belongs to another task and was left
untouched" or "<date>: reviewed without a task file at the user's choice; task.md
did not exist".

Then write `$LOG_DIR/$RUN-summary.json` with the Write tool, in the shape of
[summary-template.json](summary-template.json)
(`${CLAUDE_SKILL_DIR}/summary-template.json`): the same keys, each `<...>` replaced by
one of the values it names. It has one entry per round that ran, with its seconds, its
fingerprint, the lines `round-facts.sh` printed, and one entry per row of that round's
findings table: tag, both labels, and decision word, copied from the triage file, and
what its second look and its rebuttal found, from its row of the overrides table, or
`not run` for each when it has no row there or one did not run. `reviewed` is false,
and the findings empty, for a round whose review failed or did not run. A round whose
rebuttal failed keeps `reviewed` true and its findings: each one the rebuttal covered
is `escalated`, with `rebuttal` `failed`. `unverified` is true when the review said it
could not run or verify something. Put no text of a finding into it. Without a task
file, `task_file` is false, both hashes are `none`, and the checklist is empty. Write
it for every run that reached step 4.

Lead with one verdict: the first row of this table that fits the run.

| The run ended like this | Verdict |
|---|---|
| The last round gave no usable review: Codex exited with an error or was stopped, the facts in step 4 made the review a failed one, a fingerprint failed or differed, or the tool flags could not be built. Its rebuttal failing counts the same. | `review failed` |
| A finding's decision is `not fixed`, `disputed twice`, or `escalated`: a valid P0-P2 finding that belongs to the task is still open, or the user has to decide whether one is valid. A finding decided as `outside scope` does not count here. | `open findings` |
| Code changed after the last review that completed: fixes were made in the last allowed round, or the loop was stopped before another round. | `fixes not re-reviewed` |
| No row above fits, and something stands unverified: a checklist row that does not say `reviewer`, something the review says it could not check, a file listed by the mention check in step 5, an implementer override, or a finding decided as `outside scope`. | `clean with unverified items` |
| No row above fits. The last review saw the final code and reported no P0-P2 finding, the reviewer verified every criterion, and nothing was overridden. | `verified` |

Say in one sentence which facts decided the verdict. A review that cannot run the
tests leaves the criteria they prove to your own run, so that run is `clean with
unverified items`, not `verified`. In a run without a task file there are no criteria:
say so beside the verdict.

Then, in this order:

1. Implementer overrides: every row of the rounds' overrides tables, also those whose
   decision the second look or the rebuttal changed, each with both outcomes of its
   row, the second look and the rebuttal, `not run` and `failed` included. First each
   `escalated` finding, with Codex's evidence, the second look's, the rebuttal's when
   it answered, and yours: the user decides it. Then each other row, with what you
   decided before the second look, the decision that stands, its evidence, and its row
   in `docs/reviews/decisions.md` when it stands rejected. These are your judgments on
   your own work. A second look that agreed is another Claude agent's view, not the
   reviewer's; only a finding withdrawn in a rebuttal has the reviewer's agreement.
   Write "Implementer overrides: none" when no round has a row.
2. Rounds table: round, model, findings by severity, fixed, rejected, deferred, and
   what the reviewer used: shell commands that ran, web searches, other tool calls.
   Say which tools the run allowed: the default, `--web <mode>`, or `--allow-tools`.
   List a rebuttal under its round, with what it used and how each of its findings
   ended.
3. Requirement checklist: each acceptance criterion with its final state and who
   verified that final state, and whether the change stayed within the request. A
   criterion fixed after the last review is not verified by the reviewer. If no task
   file was used, say so.
4. Files changed, tests added, and what each test proves.
5. Checks run with exact pass, fail, or skip results.
6. P3 items awaiting the user's decision, and each finding that a rebuttal reported
   without being asked.
7. Log paths under `$LOG_DIR` and the `codex resume <session-id>` command for the
   last round.
8. State that nothing was committed, and remind the user to read the diff before
   committing.

## Guardrails

- Codex reviews, and the agent of the second look reads; neither edits. Only Claude
  edits.
- The reviewer gets its sandboxed shell and the tools built into Codex. The loop also
  asks Codex for web search, except with `--web off`; a review goes ahead without it
  when Codex does not offer it. Connectors other than web search, plugins, and the MCP
  servers in Codex's configuration stay off unless the user passed `--allow-tools` for
  this run. Never drop a tool flag to make a review work. Three of Codex's own tools
  list and read the resources of MCP servers, and no setting that the loop can use
  turns them off; in a run without `--allow-tools`, a call of one that the log records
  stops the review, as step 4 says.
- Never weaken tests, types, validation, or lint rules to satisfy a finding.
- Never paste `.env` values, tokens, or connection strings into a prompt, log, or
  report. The task file is sent to Codex in full: keep secrets out of it.
- Keep the prompt, the task file, and the logs outside the repository.
- If a finding conflicts with a rule in the repository's `AGENTS.md`, follow
  `AGENTS.md`, record the rejection, and say so.

## Examples

Installed from the plugin, the full command is `/codex-review-loop:codex-loop`; the
short `/codex-loop` also works unless a personal skill of the same name exists.

```text
/codex-loop
/codex-loop --report-only
/codex-loop src/mail
/codex-loop app/sso features/sso --focus "token audience, replay, open redirects"
/codex-loop --base main
/codex-loop features/auth --rounds 2 --model <slug> --effort xhigh
/codex-loop --web off
/codex-loop --allow-tools
```
