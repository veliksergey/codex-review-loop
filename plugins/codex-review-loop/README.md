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
| `/codex-review-loop:codex-loop` (short: `/codex-loop`) | Runs the review loop on your uncommitted changes, a branch (`--base main`), or chosen files and folders. `--report-only` shows findings without changing anything. `--web off` and `--allow-tools` change which tools the reviewer has. |
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
  every run and with Codex's connectors, plugins, and MCP servers turned off;
  `codex mcp list` and `codex debug prompt-input` before each review, to turn the
  MCP servers off and to check that no other tool is still on; and git commands that
  read the working tree. It installs nothing.
- **Sends** the task file, and whatever the reviewer reads, to OpenAI through your
  own ChatGPT account, because that is where Codex runs. The sandbox blocks writing,
  not reading, so the reviewer can read files outside the change. It can also search
  the web and open public pages unless you pass `--web off`. Say "skip review" for
  code that must not leave your machine, and keep secrets out of your requests.
- **Web search has two limits**, both observed on 2026-11-13. Codex's `cached` and
  `live` settings made no difference to what the search tool fetched, so treat web
  search as on or off. And the plugin keeps web search by naming Codex's search
  connector with an identifier OpenAI does not document: if a Codex update renames
  it, reviews lose web search, and the reviewer says so in its summary.
- **Writes** review logs and task files to `~/.claude/codex-reviews/<repo>/`, outside
  the reviewed repository; rejected findings to `docs/reviews/decisions.md` inside
  it; and, through `setup`, rule blocks in the three global files above, only after
  you approve each change.
- **Never** commits, pushes, or runs release scripts. The loop fingerprints the
  working tree before and after every review and stops if anything changed. It also
  stops when the reviewer could not run a sandboxed command, or called a tool that
  should be off.

## Privacy

The plugin's authors collect nothing: the plugin runs no service of its own, sends
nothing to its authors, and contains no analytics. The only data that leaves your
machine is what the Codex CLI sends to OpenAI under your own ChatGPT account: the
task file, whatever the reviewer reads while it reviews, and its web searches.
OpenAI's handling of that data is governed by
its privacy policy, https://openai.com/policies/privacy-policy, and by your ChatGPT
plan. Review logs stay in `~/.claude/codex-reviews/` on your machine until you delete
them. For product or security concerns, open an issue in the repository:
https://github.com/veliksergey/codex-review-loop/issues

Full guide, cheat sheet, changelog, and manual install options:
https://github.com/veliksergey/codex-review-loop

License: MIT.
