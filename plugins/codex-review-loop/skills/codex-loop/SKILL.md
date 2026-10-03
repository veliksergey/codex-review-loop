---
name: codex-loop
description: Run the Codex (ChatGPT) code-review loop on the current uncommitted changes, on a branch compared with a base, or on specific files and folders; a target with no uncommitted changes is audited as existing code without a task file. Codex reviews read-only against the user's request in the task file; Claude verifies every finding, fixes valid P0-P2 findings with regression tests, lists P3 items for the user, and re-reviews, up to 3 rounds. Use after finishing an implementation task in a git repository, or when the user asks for a Codex review, a ChatGPT review, a second opinion, or a review loop.
argument-hint: "[paths...] [--base <ref>] [--focus \"text\"] [--rounds N] [--model <slug>] [--effort <level>] [--report-only]"
allowed-tools: Bash(codex exec review *), Bash(codex login status), Bash(git status *), Bash(git diff *), Bash(git rev-parse *), Bash(git branch *), Bash(git hash-object *), Bash(git -c core.quotePath=false ls-files *), Bash(mkdir *), Bash(date *), Bash(grep *), Bash(wc *), Bash(ls *), Read, Write, Edit, Grep, Glob
---

# Codex review loop

You are the implementer. Codex, signed in with the user's ChatGPT account, is the
independent reviewer and runs read-only. This skill sends Codex the change together
with the user's request, verifies every finding, fixes what the policy allows, and
repeats until the change is clean or the round limit is reached. The user watches
the terminal: show them everything Codex says, verbatim.

Arguments received: `$ARGUMENTS`

## 1. Parse the arguments

| Argument | Meaning | Default |
|---|---|---|
| `paths...` | Files or folders to review, relative to the repository root. Their current contents on disk are reviewed, plus the uncommitted changes touching them. A target with no uncommitted changes and no task file that names it is an audit of existing code (step 2, item 5). | none: review all uncommitted changes |
| `--base <ref>` | Review every change on the current branch relative to `<ref>`, for example `main`, plus the uncommitted changes. | off |
| `--focus "text"` | Extra focus for the reviewer, for example `"open redirects and token audience"`. | none |
| `--rounds N` | Maximum review rounds. | 3 |
| `--model <slug>` | Model for this review. Passed to Codex as both `-m <slug>` and `-c review_model="<slug>"`, so it beats the `review_model` default in any config file. | `review_model` from the repository's `.codex/config.toml` if the repository is trusted, else from `~/.codex/config.toml`, else the Codex account default |
| `--effort <level>` | Reasoning effort for this review, passed as `-c model_reasoning_effort="<level>"`. One of `low`, `medium`, `high`, `xhigh`; some models accept more levels such as `max` or `ultra`. | `model_reasoning_effort` from config, else the Codex default |
| `--report-only` | One round, show the findings, change nothing. | off |

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
   Keep the output as `REPO_ROOT`; its basename is `REPO`.
2. `codex login status` must print `Logged in`. Otherwise tell the user to run
   `!codex login` and stop.
3. The repository's documented checks must pass on the current tree. Read the
   repository's `AGENTS.md` and `CLAUDE.md` for the exact commands, for example
   `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm build`. Do not send failing code
   to review. If no checks are documented, say so and continue.
4. If `git status --short --untracked-files=all` shows a new secret-bearing file
   such as `.env` or a key file, stop and ask before reviewing.
5. The task file `$LOG_DIR/task.md` (see step 3 for `LOG_DIR`) must describe the
   change under review. It is the user's request, the acceptance criteria, the
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
   - Before round 1, when a task file is used, its `## Handoff` section must be
     complete: files changed, tests added and what each proves, assumptions, check
     results, risks.
6. Uncommitted mode with nothing to review: if `git status --short --untracked-files=all`
   prints nothing, stop and tell the user so. Suggest paths for an audit of existing
   code, or `--base <ref>` for a branch.

## 3. Prepare the log directory outside the repository

Logs never go inside the repository: untracked files there become part of the next
uncommitted review.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"; REPO="$(basename "$REPO_ROOT")"
RUN="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$HOME/.claude/codex-reviews/$REPO"; mkdir -p "$LOG_DIR"; echo "$LOG_DIR/$RUN"
```

Files in `LOG_DIR`:

- `task.md`: the current task file, written at task start and updated until the
  loop ends. Overwritten when the next task starts.
- `<RUN>-task.md`: archived copy of the task file as it stood at the final report.
  In audit mode: a one-line note naming the target and stating that no task file
  was used.
- Per round `N` (substitute the round number yourself):
  - `<RUN>-round<N>-prompt.md`: the exact prompt sent to Codex.
  - `<RUN>-round<N>-codex.md`: Codex's final review, written by Codex through `-o`.
  - `<RUN>-round<N>-codex.log`: Codex's progress log and session id (stderr).
  - `<RUN>-round<N>-claude.md`: your triage table and requirement checklist.

## 4. Run a round

Estimate the size first with `git status --short --untracked-files=all | wc -l`, or
`git diff --stat <ref>...HEAD` in branch mode, or the number of target files in
paths mode. Up to 10 files: run in the foreground with the Bash tool and
`timeout: 600000`. More than 10 files, a whole folder, or unknown size: run with
`run_in_background: true` and continue when the completion notification arrives.
Tell the user which you chose and that a review usually takes one to several minutes.

### Build the prompt

Read `${CLAUDE_SKILL_DIR}/review-prompt.md` and replace three placeholders:

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

Branch (substitute `<ref>`):

```text
Target: all changes on the current branch relative to `<ref>`, plus any uncommitted
changes. Collect them yourself:
1. `git diff <ref>...HEAD --stat`, then `git diff <ref>...HEAD`, for the committed
   changes since the merge base.
2. `git status --short --untracked-files=all`, `git diff`, `git diff --cached`, and
   every untracked file in full, for the uncommitted changes.
3. Read the whole of each changed file, not only the hunks, because a defect in
   unchanged lines that the change relies on still counts.
```

Paths (one repository-relative path per line):

```text
Target files and folders, relative to the repository root:
<paths>
Review the current contents of the target as it exists on disk. Start with
`git status --short --untracked-files=all -- <target>`, `git diff -- <target>`, and
`git diff --cached -- <target>` to see what changed recently, then read the whole
files, because a defect in unchanged lines that the change relies on still counts.
```

`{{FOCUS}}`: the focus text, or `none`.

`{{TASK}}`: the full contents of `$LOG_DIR/task.md`, or, in audit mode or when the
user chose to proceed without one, the single line
`No task file was provided. Review the scope only and say so in your summary.`

Write the result to `$LOG_DIR/$RUN-round$N-prompt.md` with the Write tool. Confirm
no `{{` remains.

### Run Codex

```bash
codex exec review -c 'sandbox_mode="read-only"' -o "$LOG_DIR/$RUN-round$N-codex.md" - < "$LOG_DIR/$RUN-round$N-prompt.md" 2> "$LOG_DIR/$RUN-round$N-codex.log"
```

Codex layers this prompt on top of its own built-in review guidelines: the prompt
arrives as the task message, the guidelines stay as base instructions. Verified
2026-09-08 from the review thread transcript.

Rules for the command:

- When `--model` was given, add `-m <slug> -c review_model="<slug>"` directly after
  `review`. Both are needed: a `review_model` line in a config file would otherwise
  decide the review model.
- When `--effort` was given, add `-c model_reasoning_effort="<level>"`.
- Know which model and effort the review really used. The `.log` header line
  `model:` shows the session model, which can differ from the review model when
  `review_model` is set in config. The review model is the `--model` value if given,
  else `review_model` from the repository's `.codex/config.toml`, else from
  `~/.codex/config.toml`. Read those lines with `grep` when you report.
- Do not add `--ephemeral`; it would prevent `codex resume` later.
- Always keep `-c 'sandbox_mode="read-only"'`. In a repository marked trusted in
  `~/.codex/config.toml`, Codex defaults to `workspace-write`, which would let the
  reviewer edit files; the override forces read-only regardless of trust. After the
  run, confirm the `.log` header line `sandbox:` says `read-only`, and report it if
  it does not.
- Never add `-s workspace-write`, `-a`, `--approve-for-me`, or
  `--dangerously-bypass-approvals-and-sandbox`.
- Check that the reviewer changed nothing. Before the run, record a baseline of four
  hashes: `git status --porcelain --untracked-files=all | git hash-object --stdin`,
  `git diff | git hash-object --stdin`,
  `git diff --cached | git hash-object --stdin`, and, for the contents of untracked
  files,
  `git -c core.quotePath=false ls-files --others --exclude-standard | git hash-object --stdin-paths | git hash-object --stdin`.
  These need nothing beyond git, so the same commands work on every platform. After
  the run, recompute them. If any differs, stop the loop, show `git status --short`,
  and tell the user that Codex wrote to the working tree. Files git ignores are not
  covered; the read-only sandbox is the guarantee for those.
- If the `.log` contains `CreateProcessWithLogonW failed: 1385`, Codex could not
  start its persistent Windows sandbox shell and is retrying command by command.
  The review normally still completes. Mention it in the report and point to
  OpenAI's Windows sandbox page: https://learn.chatgpt.com/docs/windows/windows-sandbox
- If the exit code is not 0, read the `.log` file, quote its last meaningful lines to
  the user, and stop the loop. A usage-limit message means the ChatGPT allowance is
  exhausted: report it and stop.

## 5. Show the review verbatim

Read `<RUN>-round<N>-codex.md` and print it to the user unchanged inside a fenced
block headed `Codex review, round N of M (review model: <slug>, effort: <level>)`,
using the model and effort determined in step 4. Do not summarize, soften, or
reorder it. Add the session id from the `.log` (`grep "session id:"`) so the user
can open the full transcript with `codex resume <session-id>`.

Codex renders its result as a short summary followed by `Full review comments:`,
one finding per bullet as `[Pn] Title — <absolute path>:<lines>` with a
one-paragraph body. That shape comes from Codex's own output schema and the prompt
cannot change it. Requirement findings carry `(criterion N)`, `(beyond request)`, or
`(handoff)` at the start of the title.

Completeness check, uncommitted and branch modes: for every untracked file in scope
(from `git status --porcelain --untracked-files=all`, lines starting with `??`,
excluding `docs/reviews/`), confirm its file name appears in the round's `.log` or
`.md`. A name that appears nowhere means Codex never looked at it. List any such
file in the report and, if the loop continues, add it as a path in a targeted
paths-mode round.

## 6. Triage every finding

Treat each finding as a testable claim. Open the cited file and lines, trace the
code path, or reproduce it with a test before deciding. Convert Codex's absolute
paths to repository-relative paths in your table. Codex's severity label is a
proposal: in testing the same fact was rated P1 in one run and P2 in another. Set
the severity yourself from the scale in `review-prompt.md`, and note in the triage
table when you changed it.

| Outcome | Rule |
|---|---|
| Valid, P0 / P1 / P2 | Fix it now with the smallest cohesive change. Add or extend a regression test that fails before the fix and passes after. |
| Valid, P3 | Do not fix unasked. Put it on the "awaiting your decision" list in the final report. |
| Invalid | Reject only with concrete evidence: a code path, test output, or primary documentation. Add a row to `docs/reviews/decisions.md` in the repository; if it is missing, create it from the setup skill's template, `${CLAUDE_SKILL_DIR}/../setup/templates/repo-decisions.md`. |
| Outside the task's scope | Do not implement. List it for the user as a follow-up. |
| Already recorded in `docs/reviews/decisions.md` | Do not fix. Mark it "disputed twice" and escalate to the user in the final report. |

Requirement findings follow the same table with these specifics:

- `(criterion N)` not met: a valid one is P1. Fix the code, not the criterion.
- `(beyond request)`: valid when the change adds behavior the request and the
  task file's decisions do not cover. Remove the addition, or, if the user asked for
  it in conversation, quote the user's words in the task file's Decisions section
  and reject the finding with that evidence.
- `(handoff)` claim not supported: fix the thing the claim was about, for example
  add the missing test. If the claim was wrong but the code is right, correct the
  Handoff section and say so in the triage table.
- Never edit the task file to make a finding disappear. It changes only to record a
  user decision or to correct a factual claim about the code.

With `--report-only`, skip fixing and go to the final report after one round.

Write `<RUN>-round<N>-claude.md`: one row per finding with severity, decision, and
the evidence or the change made, followed by a requirement checklist: one row per
acceptance criterion with met, not met, fixed this round, or not verifiable, based
on your own verification and Codex's findings. In audit mode the checklist is the
single line "no acceptance criteria: audit of existing code".

## 7. Close the round

- If you changed code, rerun the repository's documented checks and fix any failure
  before the next round.
- Update the task file: append decisions made while fixing, and bring the Handoff
  section up to date so the next round reviews current claims, not stale ones.
  Not in audit mode: `task.md` belongs to another task, so record the decisions
  made while fixing in the round's `-claude.md` instead.
- Start the next round when something was fixed and `N` is below `--rounds`.
- Stop when the review reported no P0-P2 findings, when nothing changed this round,
  when `N` reached `--rounds`, when a finding was disputed twice, when Codex failed,
  or when the user interrupts.

Never commit, push, tag, or run release scripts as part of the loop.

## 8. Final report

Archive the task file first: read `$LOG_DIR/task.md` and write its contents unchanged
to `$LOG_DIR/$RUN-task.md` with the Write tool. Leave `task.md` in place; the next
task overwrites it. In audit mode do not copy it: write
`$LOG_DIR/$RUN-task.md` with one line, "Audit of <paths>, <date>: no task file used;
task.md on disk described another task and was left untouched".

Lead with the verdict: clean, stopped with open findings, or stopped on an error.
Then:

1. Rounds table: round, model, findings by severity, fixed, rejected, deferred.
2. Requirement checklist: each acceptance criterion with its final state, and
   whether the change stayed within the request. If no task file was used, say so.
3. Files changed, tests added, and what each test proves.
4. Checks run with exact pass, fail, or skip results.
5. P3 items awaiting the user's decision.
6. Rejected findings recorded in `docs/reviews/decisions.md`.
7. Log paths under `$LOG_DIR` and the `codex resume <session-id>` command for the
   last round.
8. State that nothing was committed, and remind the user to read the diff before
   committing.

## Guardrails

- Codex reviews; it never edits. Only Claude edits.
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
/codex-loop src/ui/dialogs --report-only
/codex-loop app/sso features/sso --focus "token audience, replay, open redirects"
/codex-loop --base main
/codex-loop --rounds 2 --model <slug>
/codex-loop --effort xhigh
/codex-loop features/auth --model <slug> --effort xhigh
```
