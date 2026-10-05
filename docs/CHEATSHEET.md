# Codex review loop: cheat sheet

Claude Code writes the code and a task file: your request word for word, the
acceptance criteria, its decisions, and its handoff. Codex reviews the change
read-only against that file. Claude verifies every finding, fixes P0-P2 with a
regression test, holds P3 for you, and re-reviews, at most three rounds. The loop
never commits. Full guide: [GUIDE.md](GUIDE.md).

## Daily workflow

1. Open Claude Code at the repository root, never at a parent folder.
2. Check the branch: `git branch --show-current`, `git status --short`.
3. Give Claude the task. Read the acceptance criteria it prints and correct them if
   they are wrong.
4. Claude implements, runs the checks, and starts the loop. Say "skip review" to
   skip it.
5. Read the rounds and the final report. Decide on the P3 items.
6. Read the diff, then commit yourself.

## Commands

| Command | What it does | When to use |
|---|---|---|
| `/codex-loop` | Reviews all uncommitted changes: staged, unstaged, and new files. Fixes P0-P2, re-reviews, up to 3 rounds. | After a task. Claude runs it on its own once the checks pass; run it yourself after editing code by hand. |
| `/codex-loop --report-only` | One round, findings only, no edits. | To see what Codex thinks before anything is changed. |
| `/codex-loop <path> ...` | Reviews those files or folders as they are on disk, plus uncommitted changes in them. A path with no changes is an audit. | One module at a time, or an audit of existing code: one top-level folder at a time, `--report-only` first. |
| `/codex-loop --base main` | Reviews every commit on the branch since `main`, plus uncommitted changes. | Before a pull request. |
| `/codex-loop --focus "text"` | Adds a focus for the reviewer. Combines with any mode. | Risky areas, for example `"token audience, replay, open redirects"`. |
| `/codex-loop --rounds N` | Caps the rounds. Default 3. | Small changes or a tight usage budget: `--rounds 2`. |
| `/codex-loop --model <slug>` | Another review model, this review only. | Authentication, authorization, payments, migrations, secrets, and the last pass before a pull request. |
| `/codex-loop --effort <level>` | Another reasoning effort, this review only. | A harder look at risky code, for example `--effort xhigh`. |
| `/codex-review-loop:setup` | Installs or updates the rule blocks in your global files, showing each change first. | Once per computer, and again after a plugin update. |
| `/codex-review-loop:setup repo` | Adds `docs/reviews/decisions.md` and an `AGENTS.md` starter to the current repository. | Once per repository, before its first review. |
| `/codex-review-loop:setup check` | Reports what is installed. Changes nothing. | When the loop does not start or something looks wrong. |

`/codex-loop` is short for `/codex-review-loop:codex-loop`. Paths and `--base` are
separate modes; the other options combine with either.

## Plugin and Codex commands

| Command | Where | What it does | When to use |
|---|---|---|---|
| `claude plugin marketplace update codex-review-loop` | Terminal | Refreshes the list of available versions. Does not update the installed plugin. | First step of an update. |
| `claude plugin update codex-review-loop@codex-review-loop` | Terminal | Installs the newest version from that list. | Second step of an update. Then restart Claude Code or run `/reload-plugins`, and run `/codex-review-loop:setup`. |
| `claude plugin list` | Terminal | Shows installed plugins and their versions. | To confirm an update; compare with the newest entry in `CHANGELOG.md`. |
| `/reload-plugins` | Claude Code | Loads installed or updated plugins into the running session. | Right after installing or updating, instead of starting a new session. |
| `/plugin` | Claude Code | Shows installed plugins, marketplaces, and plugin errors. | A command is missing, or to turn on auto-update under **Marketplaces**. |
| `claude plugin uninstall codex-review-loop@codex-review-loop` | Terminal | Removes the plugin. | To uninstall. The README lists the remaining cleanup. |
| `codex login` | Terminal | Signs in to Codex with your ChatGPT account. | First setup, or when the loop reports that you are not logged in. |
| `codex login status` | Terminal | Shows whether Codex is signed in. | Before a first review, or when a review fails to start. |
| `codex resume <session-id>` | Terminal | Opens Codex's full session for a review round. The loop's report prints the id. | To see exactly what Codex read and ran. |
| `codex update` | Terminal | Updates the Codex CLI, where the install supports self-update. On Windows, run it from PowerShell, not Git Bash. | Now and then, or when a model or option you expect is missing. |

## Severity

| Label | Meaning | Loop action |
|---|---|---|
| P0 | Exploitable flaw, data loss, feature unusable | Fixed first, with test |
| P1 | Definite bug or weakness, or an unmet criterion | Fixed, with test |
| P2 | Probable bug, missing guard or test, contract break, false handoff claim | Fixed, with test |
| P3 | Improvement or style | Listed for your decision |
| Rejected | Disproved with evidence | Row in `docs/reviews/decisions.md` |
| Disputed twice | Same finding after a rejection | Escalated to you |

## Where things live

| Item | Path |
|---|---|
| Claude's loop rules | `~/.claude/CLAUDE.md`, block `claude-rules` |
| Codex's reviewer rules | `~/.codex/AGENTS.md`, block `codex-reviewer` |
| Review defaults | `~/.codex/config.toml`: `review_model`, `model_reasoning_effort`, `web_search` |
| Per-repository model | `<repo>/.codex/config.toml`, only for trusted repositories |
| Check commands | `<repo>/AGENTS.md` |
| Rejected findings | `<repo>/docs/reviews/decisions.md` |
| Task file and logs | `~/.claude/codex-reviews/<repo>/` |
| Codex sessions | `~/.codex/sessions/`; open one with `codex resume <session-id>` |

## Model choice, first match wins

`--model` on the command, then the trusted repository's `.codex/config.toml`, then
`~/.codex/config.toml`, then the account default. Use a stronger model or higher
effort for authentication, authorization, tenant scope, payments, migrations, and
secrets.

## Quick fixes

| Symptom | Fix |
|---|---|
| Claude skips the loop | New session at the repository root; then `/codex-review-loop:setup check`. |
| Wrong request in the review | `task.md` was stale. Ask Claude to rewrite it and rerun. |
| Not logged in | `codex login`, then `codex login status`. |
| `sandbox: workspace-write` in a hand-run log | Add `-c 'sandbox_mode="read-only"'`. The loop always does. |
| Hangs on `Reading additional input from stdin...` | Hand-run only: add `< /dev/null`. |
| Usage limit | Wait for the window, use a cheaper model, or `--rounds 2`. |
| `1385` in the log on Windows | https://learn.chatgpt.com/docs/windows/windows-sandbox |
