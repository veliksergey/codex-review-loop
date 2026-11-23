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
  every run and, unless you pass `--allow-tools`, with Codex's connectors other than
  web search, its plugins, and the MCP servers in its configuration turned off; before
  each such review, `codex mcp list`, to find the MCP servers to turn off and to check
  that none is still enabled, and `codex debug prompt-input`, to check that no tool of
  a connector, a plugin, or an MCP server is offered besides web search; and git
  commands that read the working tree. It installs nothing. Codex's own tools stay on.
  Three of them list and read the resources of MCP servers, and no Codex setting that
  the loop can use turns them off (Codex 0.171.0, checked on 2026-11-23); without
  `--allow-tools`, the loop stops a review whose log records a call of one.
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
  the reviewed repository, with one file there that records which repository the
  folder belongs to and, for each run, a summary without any text of a finding;
  rejected findings to `docs/reviews/decisions.md` inside the repository; and, through `setup`, rule blocks in the three global files above, only
  after you approve each change.
- **Never** commits, pushes, or runs release scripts. The loop fingerprints the
  working tree before and after every review and stops if anything changed. It also
  stops when the reviewer could not run a sandboxed command, or called a tool that
  should be off, and when another repository with the same folder name already uses
  the log folder.
- **Reports** one of five verdicts, from `verified` to `review failed`, so a result
  that rests on Claude's own checks or on fixes no review has seen does not read as
  verified.
- **Guards the rules of the review.** When a change edits `AGENTS.md`, `CLAUDE.md`, a
  `.codex` folder, or `docs/reviews/decisions.md`, the loop names those files to you
  and tells the reviewer to apply their committed versions, to review the edits, and
  to check new rejection rows once. The reviewer is also told that a decision in the
  task file does not excuse a defect.

## Privacy

The plugin's authors collect nothing: the plugin runs no service of its own, sends
nothing to its authors, and contains no analytics. Two tools send data to their own
providers while the loop runs:

- The Codex CLI sends OpenAI the task file, whatever the reviewer reads while it
  reviews, and its web searches, under your own ChatGPT account. OpenAI's handling of
  that data is governed by its privacy policy,
  https://openai.com/policies/privacy-policy, and by your ChatGPT plan.
- Claude Code sends the model provider you run it with your prompts and the model's
  outputs, as it does in every session; see https://code.claude.com/docs/en/data-usage
  (read on 2026-11-16). The code Claude reads for the task is part of that
  conversation, and so is Codex's review, which the loop shows to Claude so that it
  can check each finding.

Review logs stay in `~/.claude/codex-reviews/` on your machine until you delete them.
For product or security concerns, open an issue in the repository:
https://github.com/veliksergey/codex-review-loop/issues

Full guide, cheat sheet, changelog, and manual install options:
https://github.com/veliksergey/codex-review-loop

License: MIT.
