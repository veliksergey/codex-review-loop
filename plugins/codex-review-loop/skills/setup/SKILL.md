---
name: setup
description: Set up or check the Claude-writes, Codex-reviews loop on this computer, or prepare the current git repository for it. Backs up each file, shows the exact change, and writes only after the user approves. Never commits.
argument-hint: "[machine | repo | check]"
disable-model-invocation: true
allowed-tools: Bash(git --version), Bash(git rev-parse *), Bash(git status *), Bash(claude --version), Bash(codex --version), Bash(codex login status), Bash(date *), Bash(ls *), Bash(cat *), Bash(grep *), Bash(cp *), Bash(mkdir *), Read, Glob, Grep
---

# Set up the Codex review loop

Arguments received: `$ARGUMENTS`

| Argument | What it does |
|---|---|
| `machine` (default, also when empty) | Checks prerequisites, then installs the rule blocks in the global files on this computer. |
| `repo` | Prepares the git repository in the current working directory. |
| `check` | Reports the state of the computer and the current repository. Changes nothing. |

Templates live in `${CLAUDE_SKILL_DIR}/templates/`. Read each template from there
when you need it; never retype one from memory.

## Rules for every change

These apply to every file this skill writes, in every mode.

1. Read the target file first. It may not exist yet.
2. Show the user the target path and the exact text that will be added, replaced,
   or removed, in a fenced block. For `~/.codex/config.toml`, show only the lines
   you change, never the whole file: it can hold tokens for MCP servers.
3. Ask before writing. Use the AskUserQuestion tool with the options "Apply",
   "Skip", and, where the user already has their own text, "Keep mine". Without the
   tool, ask in plain text and wait for the answer. Write only after "Apply".
4. Back up an existing file before its first write in this run:
   `cp "<file>" "<file>.bak-codex-review-loop-$(date +%Y%m%d-%H%M%S)"`. A file
   that did not exist needs no backup.
5. Write with Edit for an existing file, Write for a new one. Never change text
   outside the block you showed.
6. Re-read the file and confirm the block appears exactly once.

### Blocks and markers

Each template is one block, fenced by markers so a rerun finds it:

- Markdown: `<!-- codex-review-loop:begin <id> -->` to `<!-- codex-review-loop:end <id> -->`
- TOML: `# codex-review-loop:begin <id>` to `# codex-review-loop:end <id>`

For each block, decide by the first case that matches:

| Found in the target | Action |
|---|---|
| Both markers, content identical to the template | Report "up to date". No question. |
| Both markers, content differs | Show the difference. Ask "Update to the template" or "Keep mine". |
| No markers, but the block's heading already exists (see the table below) | An earlier manual install or the user's own text. Show the existing section and the template side by side. Ask "Replace with the template", "Keep mine", or "Skip". Never insert a second copy. |
| Nothing | Insert at the position given for the block. |

| Block id | Template | Target | Heading that signals an unmarked copy | Position |
|---|---|---|---|---|
| `shared-import` | `shared-import.md` | `~/.claude/CLAUDE.md` | a line that is exactly `@~/.codex/AGENTS.md` | first line of the file |
| `claude-rules` | `claude-rules.md` | `~/.claude/CLAUDE.md` | `# Claude Code responsibilities` or `## Codex review loop` | end of the file, after one blank line |
| `shared-invariants` | `shared-invariants.md` | `~/.codex/AGENTS.md` | `# Shared engineering invariants` | first line of the file |
| `codex-reviewer` | `codex-reviewer.md` | `~/.codex/AGENTS.md` | `## Reviewing code` | end of the file, after one blank line |
| `codex-config` | `codex-config.toml` | `~/.codex/config.toml` | any of its keys at top level, see machine step 5 | before the first line that starts with `[`, or at the end when there is none |

When the user keeps an unmarked copy of `claude-rules` and it lacks a
`## Codex review loop` section, say plainly that Claude will not run the loop on
its own until that section exists.

## Machine mode

### Step 1. Prerequisites

Read-only. Report each item as a table row: item, result, what to do.

1. `git --version`.
2. `claude --version`.
3. `codex --version`. If missing, tell the user to install the Codex CLI from
   https://learn.chatgpt.com/docs/codex/cli, open a new terminal, and rerun this
   command. Stop.
4. `codex login status` must report that the user is logged in. If not, tell the
   user to run `! codex login` and rerun this command. Stop.
5. On Windows, this session must have the Bash tool, which needs Git for Windows.
   The review skill runs bash commands. If only PowerShell is available, point to
   https://git-scm.com/downloads/win, ask the user to install it and restart Claude
   Code, and stop.
6. If `~/.claude/skills/codex-loop/SKILL.md` exists, tell the user that this
   personal copy takes the short `/codex-loop` command and loads alongside the
   plugin's copy, so the two can drift apart. Suggest renaming or deleting that
   folder once the plugin works. Do not touch it yourself.

### Step 2. Choose the parts

The blocks `claude-rules` and `codex-reviewer` are always offered; the loop does not
work without them. Ask one multi-select question for the optional parts:

- **Shared engineering invariants (recommended).** Blocks `shared-invariants` in
  `~/.codex/AGENTS.md` and `shared-import` in `~/.claude/CLAUDE.md`, so Claude and
  Codex follow the same rules on honesty, security, change quality, and research.
- **Codex review defaults.** Block `codex-config` in `~/.codex/config.toml`: the
  review model, the reasoning effort, and live web search for the reviewer.

### Step 3. `~/.claude/CLAUDE.md`

Apply `shared-import` (if chosen), then `claude-rules`, following the rules above.
Create the file if it does not exist.

### Step 4. `~/.codex/AGENTS.md`

Apply `shared-invariants` (if chosen), then `codex-reviewer`. Create the file if it
does not exist.

### Step 5. `~/.codex/config.toml` (if chosen)

TOML has two traps. A key written after a `[table]` header belongs to that table,
so the block must sit above the first header. A key may appear only once, so a
second `review_model` line breaks the file.

1. Collect the values:
   - `review_model`. Read `~/.codex/models_cache.json` if it exists and offer the
     `slug` and `description` of each entry under `models`. The list depends on the
     ChatGPT plan and the Codex version. The user may also choose "account
     default", which leaves the key out.
   - `model_reasoning_effort`. Offer the `effort` values that the chosen model's
     `supported_reasoning_levels` lists; without the cache, offer `low`, `medium`,
     `high`, and `xhigh`. Suggest `high`.
   - `web_search = "live"` lets the reviewer check current documentation. Keep it
     unless the user declines.
2. For each key, look for it at top level outside the block, meaning before the
   first `[` header. If it is there, do not add it again: show its current value
   and ask whether to change that line in place.
3. Fill `{{REVIEW_MODEL}}` and `{{EFFORT}}` in the template, drop the lines for
   keys the user left unset or that already exist elsewhere, and apply the block.
4. Never touch `[windows]`, `[projects.*]`, or any other table.

### Step 6. Log folder

`mkdir -p ~/.claude/codex-reviews`. Review logs and task files live there, outside
every repository.

### Step 7. Report

One table: file, block, result (added, updated, up to date, kept the user's
version, or skipped), backup path. Then the next steps:

1. Start a new Claude Code session. `CLAUDE.md` is read at session start.
2. Open a terminal at the root of a git repository and run
   `/codex-review-loop:setup repo`.
3. Make a small change and run a first review without fixes:
   `/codex-review-loop:codex-loop --report-only`.

## Repo mode

1. `git rev-parse --show-toplevel` must succeed. If not, stop: the loop needs a git
   repository. Work at that root.
2. `docs/reviews/decisions.md`: if missing, create it from `repo-decisions.md`.
   Codex reads it and does not raise a rejected finding again.
3. `AGENTS.md` at the root:
   - Missing: build it from `repo-AGENTS.md`. Fill the Commands table only from
     what the repository states explicitly: `package.json` scripts, run with the
     package manager its lockfile implies (`pnpm-lock.yaml` pnpm, `yarn.lock` yarn,
     `package-lock.json` npm, `bun.lock` bun), or explicit targets in a
     `Makefile`, `pyproject.toml`, `Cargo.toml`, or `go.mod` project. Never invent a
     command; write `none` for a check the repository lacks and tell the user. Fill
     `{{BRANCHES}}` with what the user tells you, or with "Not stated yet." Leave the
     Invariants paragraph for the user.
   - Present: if neither `AGENTS.md` nor `CLAUDE.md` names the check commands,
     offer to add a `## Commands` section built the same way. Otherwise leave it.
4. Optional per-repository review model: ask whether this repository should review
   with a different model than the global default. If yes, create
   `.codex/config.toml` from `repo-codex-config.toml`. Codex reads it only when the
   repository is trusted: look for a `[projects.'<path>']` table with
   `trust_level = "trusted"` in `~/.codex/config.toml` and report what you find. To
   trust it, the user runs `codex` once in the repository and accepts the prompt.
   Recommend not committing this file unless the whole team wants that default.
5. Never `git add` or commit. List the files you created as untracked, for the user
   to read and commit.

## Check mode

Read-only: run nothing that writes and ask no write question.

1. The prerequisites table from machine step 1.
2. For each block in the table above: marked and up to date, marked but different
   from the template, unmarked copy found, or missing.
3. `~/.codex/config.toml`: the top-level values of `review_model`,
   `model_reasoning_effort`, and `web_search`, and the `[windows]` `sandbox` value
   on Windows. Print only those lines.
4. If the working directory is inside a git repository: whether
   `docs/reviews/decisions.md` exists, whether `AGENTS.md` or `CLAUDE.md` names the
   check commands, and whether the repository is trusted in `~/.codex/config.toml`.
5. End with the one command that fixes the first gap, for example
   `/codex-review-loop:setup` or `/codex-review-loop:setup repo`.

## Guardrails

- Never edit Claude Code `settings.json` files, never install or upgrade software,
  and never run `codex login` for the user.
- Never print tokens, keys, or other secret values from any file.
- Never commit, push, or change git state.
