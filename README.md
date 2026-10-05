# Codex review loop for Claude Code

Claude Code writes the code. OpenAI's Codex CLI reviews it, read-only, against what
you asked for. Claude checks every finding, fixes the valid ones with a regression
test, and asks Codex to look again, up to three rounds. You watch the whole exchange
in the terminal, and nothing is committed until you commit it.

The point is an independent second opinion on every change: a reviewer from a
different vendor does not share the author's blind spots, and it judges the code
against your request, not against what the author claims about it.

This repository is a Claude Code plugin. It installs two commands:

| Command | What it does |
|---|---|
| `/codex-review-loop:codex-loop` (short: `/codex-loop`) | Runs the review loop on your uncommitted changes, a branch, or chosen files and folders. Claude also runs it on its own at the end of each implementation task. |
| `/codex-review-loop:setup` | Adds the rules both tools follow to your global files, after showing you each change. `setup repo` prepares a repository; `setup check` reports what is in place. |

## How it works

1. You give Claude a task. Claude copies your request word for word into a task
   file, writes acceptance criteria, and shows them to you before coding.
2. Claude writes the code, runs the repository's checks, and fills in a handoff:
   files changed, tests and what each proves, assumptions, risks.
3. Claude starts Codex in a read-only sandbox with the change and the task file.
   Codex reports findings labeled P0 (worst) to P3. Claude prints them verbatim.
4. Claude verifies each finding against the code. Valid P0-P2 findings are fixed
   with a regression test. P3 items wait for your decision. Rejected findings are
   recorded with evidence in the repository's `docs/reviews/decisions.md`, so Codex
   does not raise them again.
5. Claude re-runs the checks and the review, at most three rounds, then reports.

Codex is the second opinion, not the judge: Claude must prove or disprove each
finding in the code, and the final decision and the commit are yours.

## What you need

| Requirement | Notes |
|---|---|
| Claude Code | Needs a Pro, Max, Team, Enterprise, or Console account. Install: https://code.claude.com/docs/en/setup |
| Codex CLI, signed in | Needs a ChatGPT plan that includes Codex. Install: https://learn.chatgpt.com/docs/codex/cli. Sign in with `codex login`. |
| git | Every reviewed project must be a git repository. |
| Windows only: Git for Windows | Gives Claude Code its Bash tool, which the review command needs. https://git-scm.com/downloads/win |
| Stored git credentials | Only if you install from a private fork of this repository; the public repository needs none. See [Install from a private fork](#install-from-a-private-fork). |

## Install

1. In Claude Code, add this repository as a plugin marketplace and install the
   plugin.

   ```text
   /plugin marketplace add veliksergey/codex-review-loop
   /plugin install codex-review-loop@codex-review-loop
   /reload-plugins
   ```

2. Run the setup command. It checks the prerequisites, then shows each change to
   `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, and `~/.codex/config.toml` and writes
   it only after you approve. Every file is backed up first.

   ```text
   /codex-review-loop:setup
   ```

3. Start a new Claude Code session, because `CLAUDE.md` is read at session start.
   Open it at the root of a git repository and prepare that repository:

   ```text
   /codex-review-loop:setup repo
   ```

4. Make a small change and run a first review that changes nothing:

   ```text
   /codex-loop --report-only
   ```

The step-by-step guide with expected output is [docs/GUIDE.md](docs/GUIDE.md).

**Prefer not to install straight from GitHub?**
[docs/manual-install/](docs/manual-install/README.md) shows how to review the plugin
first and install it from your own copy, or set everything up by hand without the
plugin system.

### Install from a private fork

This repository is public, so the install above needs no credentials. If you run
the loop from a private fork or an internal mirror instead, Claude Code clones it
with your own git credentials and never asks for a password, so they must already
be stored. Pick one:

- **HTTPS with the GitHub CLI**: run `gh auth login`, then `gh auth setup-git`.
- **SSH**: a GitHub SSH key loaded in `ssh-agent`, with github.com in `known_hosts`.

Then run the commands in step 1 with your fork's `owner/repo`. Source:
https://code.claude.com/docs/en/plugins/host-marketplace#grant-access-to-a-private-marketplace

## Everyday use

| You want | Do this |
|---|---|
| Normal work | Ask Claude for the change. It writes the task file, shows the criteria, and runs the review loop when the checks pass. |
| Review now | `/codex-loop` |
| Look before anything is fixed | `/codex-loop --report-only` |
| Review a folder or files | `/codex-loop src/auth src/session` |
| Review a branch before a pull request | `/codex-loop --base main` |
| A sharper focus | `/codex-loop --focus "token audience, open redirects"` |
| A different model or effort, once | `/codex-loop --model <slug> --effort xhigh` |
| No review this time | Say "skip review" in your request. |

The short `/codex-loop` works unless you also have a personal skill named
`codex-loop`; the full name `/codex-review-loop:codex-loop` always works.
More in [docs/CHEATSHEET.md](docs/CHEATSHEET.md).

## Update

1. In a terminal, refresh the list of versions, then update the plugin:

   ```bash
   claude plugin marketplace update codex-review-loop
   claude plugin update codex-review-loop@codex-review-loop
   ```

   The first command alone does not update the installed plugin.

2. Restart Claude Code, or run `/reload-plugins` in a session that is already open.

3. Update the rule blocks in your global files:

   ```text
   /codex-review-loop:setup
   ```

   It reports "up to date" when the templates did not change.

Check the installed version with `claude plugin list`: the line under
`codex-review-loop@codex-review-loop` should match the newest version in
[CHANGELOG.md](CHANGELOG.md).

To update automatically, open `/plugin`, go to **Marketplaces**, select
`codex-review-loop`, and choose **Enable auto-update**.

## Uninstall

```text
claude plugin uninstall codex-review-loop@codex-review-loop
claude plugin marketplace remove codex-review-loop
```

Then delete the blocks between the `codex-review-loop:begin` and
`codex-review-loop:end` markers in `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, and
`~/.codex/config.toml`, or restore the `.bak-codex-review-loop-*` backups that setup
made. Review logs stay in `~/.claude/codex-reviews/` until you delete them.

## Safety properties

- Codex always runs with a read-only sandbox, forced on every run, because Codex
  defaults to a writable sandbox in repositories you have marked as trusted.
- Claude fingerprints the working tree before and after every review and stops if
  anything git can see changed: file status, staged and unstaged diffs, and the
  contents of untracked files. Files git ignores are covered by the sandbox alone.
- The loop never commits, pushes, or runs release scripts.
- Review logs and task files live in `~/.claude/codex-reviews/<repo>/`, outside the
  repository, so they never become part of the next review.
- Codex runs on your ChatGPT account, so the code it reads and the full task file
  are sent to OpenAI. Claude starts the loop on its own after each implementation
  task; say "skip review" for code that must not be sent. Keep secrets out of your
  requests.

## Repository layout

| Path | Contents |
|---|---|
| `.claude-plugin/marketplace.json` | The marketplace catalog: one plugin. |
| `plugins/codex-review-loop/skills/codex-loop/` | The review loop: `SKILL.md`, the review prompt sent to Codex, and the task file template. |
| `plugins/codex-review-loop/skills/setup/` | The setup command and the rule templates it installs. |
| `tests/` | Shell tests for this repository; not part of the installed plugin. |
| `docs/GUIDE.md` | Full setup and usage guide. |
| `docs/CHEATSHEET.md` | One-page reference. |
| [`docs/manual-install/`](docs/manual-install/README.md) | Installing from a copy you have reviewed, or by hand. |
| `CHANGELOG.md` | What changed in each version. |
| `AGENTS.md` | Rules and checks for working on this repository. |

## License

MIT. See [LICENSE](LICENSE).
