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

| Command | What it does |
|---|---|
| `/codex-loop` | Reviews all uncommitted changes, fixes P0-P2, re-reviews, up to 3 rounds. |
| `/codex-loop --report-only` | One round, findings only, no edits. |
| `/codex-loop <path> ...` | Reviews those files or folders as they are on disk. A path with no changes is an audit. |
| `/codex-loop --base main` | Reviews the branch since `main`, plus uncommitted changes. |
| `/codex-loop --focus "text"` | Adds a focus for the reviewer. Combines with any mode. |
| `/codex-loop --rounds N` | Caps the rounds. Default 3. |
| `/codex-loop --model <slug>` | Another review model, this review only. |
| `/codex-loop --effort <level>` | Another reasoning effort, this review only. |
| `/codex-review-loop:setup` | Installs or updates the rule blocks in your global files. |
| `/codex-review-loop:setup repo` | Adds `decisions.md` and an `AGENTS.md` starter to the current repository. |
| `/codex-review-loop:setup check` | Reports what is installed. Changes nothing. |

`/codex-loop` is short for `/codex-review-loop:codex-loop`. Paths and `--base` are
separate modes; the other options combine with either.

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
