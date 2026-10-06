# codex-review-loop

Claude Code writes the code. OpenAI's Codex CLI reviews it, read-only, against what
you asked for. Claude verifies every finding, fixes the valid P0-P2 ones with a
regression test, holds P3 items for your decision, and asks Codex to look again, up
to three rounds. Nothing is committed until you commit it.

The plugin is built for Claude Code: it needs a terminal with git and the Codex CLI.
The repository around this folder holds the full documentation:
https://github.com/veliksergey/codex-review-loop

## Commands

| Command | What it does |
|---|---|
| `/codex-review-loop:codex-loop` (short: `/codex-loop`) | Runs the review loop on your uncommitted changes, a branch (`--base main`), or chosen files and folders. `--report-only` shows findings without changing anything. |
| `/codex-review-loop:setup` | Adds the rules both tools follow to your global files, after showing you each change. `setup repo` prepares a repository; `setup check` reports what is in place. |

## Requirements

- Claude Code, and the Codex CLI signed in with a ChatGPT plan that includes Codex.
- Every reviewed project must be a git repository.
- On Windows, Git for Windows, which gives Claude Code the Bash tool the loop needs.

## First run

1. Install the plugin, then run `/codex-review-loop:setup` and approve the changes
   it shows for `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, and `~/.codex/config.toml`.
   Every file is backed up first.
2. Start a new session at the root of a git repository and run
   `/codex-review-loop:setup repo`. It adds `docs/reviews/decisions.md` and an
   `AGENTS.md` starter to that repository.
3. Make a small change and run `/codex-loop --report-only`.

## What the plugin runs, sends, and writes

- **Runs** the Codex CLI (`codex exec review`) with a read-only sandbox forced on
  every run, and git commands that read the working tree. It installs nothing.
- **Sends** the code under review and the task file to OpenAI through your own
  ChatGPT account, because that is where Codex runs. Say "skip review" for code that
  must not leave your machine, and keep secrets out of your requests.
- **Writes** review logs and task files to `~/.claude/codex-reviews/<repo>/`, outside
  the reviewed repository; rejected findings to `docs/reviews/decisions.md` inside
  it; and, through `setup`, rule blocks in the three global files above, only after
  you approve each change.
- **Never** commits, pushes, or runs release scripts. The loop fingerprints the
  working tree before and after every review and stops if anything changed.

Full guide, cheat sheet, changelog, and manual install options:
https://github.com/veliksergey/codex-review-loop

License: MIT.
