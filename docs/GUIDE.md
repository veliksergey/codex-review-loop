# Codex review loop: setup and usage guide

This guide takes you from a computer with neither tool installed to a working
review loop, then explains daily use, options, and fixes for common problems. It
assumes you can open a terminal and run a command; nothing else.

## Contents

1. [What you are setting up](#1-what-you-are-setting-up)
2. [Accounts and tools](#2-accounts-and-tools)
3. [Install the plugin](#3-install-the-plugin)
4. [Set up your computer](#4-set-up-your-computer)
5. [Prepare each repository](#5-prepare-each-repository)
6. [First review](#6-first-review)
7. [Daily workflow](#7-daily-workflow)
8. [Models and effort](#8-models-and-effort)
9. [Usage limits](#9-usage-limits)
10. [Several reviews at once](#10-several-reviews-at-once)
11. [What Codex is told](#11-what-codex-is-told)
12. [Reading the logs](#12-reading-the-logs)
13. [Updating and removing](#13-updating-and-removing)
14. [Troubleshooting](#14-troubleshooting)
15. [Known limits](#15-known-limits)

## 1. What you are setting up

Two AI tools with fixed roles:

- **Claude Code** is the implementer. It writes the code, runs your checks, and
  makes every edit.
- **Codex** (OpenAI's coding agent, used through its command-line tool) is the
  independent reviewer. It reads the change and reports problems. It never edits:
  the loop starts it with a read-only sandbox every time.

The loop, in order:

1. You describe a task. Claude copies your words into a **task file** together with
   acceptance criteria, shows you the criteria, and starts coding once you have seen
   them.
2. Claude writes the code, runs the repository's checks, and completes the task
   file's **handoff** section: files changed, tests and what each proves,
   assumptions, risks.
3. Claude runs Codex with a review prompt, the scope, and the whole task file.
   Codex checks the code against your request and reports findings labeled P0 to P3.
4. Claude prints the findings verbatim, verifies each one in the code, fixes valid
   P0-P2 findings with a regression test, lists P3 items for you, and records each
   rejected finding with its evidence.
5. Claude re-runs the checks and the review, up to three rounds, and reports.

Where each piece lives after setup:

| Piece | Location | Installed by |
|---|---|---|
| Review command, review prompt, task template | The plugin, in Claude Code's plugin cache | `/plugin install` |
| Claude's rules, including when to run the loop | `~/.claude/CLAUDE.md`, block `claude-rules` | `/codex-review-loop:setup` |
| Shared engineering rules for both tools (optional) | `~/.codex/AGENTS.md`, block `shared-invariants`, imported into `CLAUDE.md` by block `shared-import` | `/codex-review-loop:setup` |
| Codex's reviewer rules | `~/.codex/AGENTS.md`, block `codex-reviewer` | `/codex-review-loop:setup` |
| Review model and effort defaults (optional) | `~/.codex/config.toml`, block `codex-config` | `/codex-review-loop:setup` |
| Per-repository check commands | `AGENTS.md` at the repository root | `/codex-review-loop:setup repo`, or you |
| Per-repository memory of rejected findings | `docs/reviews/decisions.md` in the repository | `/codex-review-loop:setup repo` |
| Task files and review logs | `~/.claude/codex-reviews/<repo>/`, outside the repository | The loop |

`~` is your home folder: `/Users/<you>` on macOS, `/home/<you>` on Linux,
`C:\Users\<you>` on Windows.

## 2. Accounts and tools

### Accounts

- **Claude Code** needs a Pro, Max, Team, Enterprise, or Console account. The free
  claude.ai plan does not include it.
- **Codex** needs a ChatGPT plan that includes Codex. Reviews count against that
  plan's Codex usage allowance; see [Usage limits](#9-usage-limits).

### Tools

Install in this order. Open a new terminal after each install so the command is
found.

1. **git.** On Windows, install **Git for Windows** (https://git-scm.com/downloads/win).
   It also gives Claude Code its Bash tool; the review command runs bash commands
   and does not work with PowerShell alone.
2. **Claude Code.** Official instructions: https://code.claude.com/docs/en/setup.
   The recommended installers, from that page:

   ```bash
   # macOS, Linux, WSL
   curl -fsSL https://claude.ai/install.sh | bash
   ```

   ```powershell
   # Windows PowerShell
   irm https://claude.ai/install.ps1 | iex
   ```

   Then run `claude` once and sign in in the browser.
3. **Codex CLI.** Official instructions, including Windows, npm, and Homebrew:
   https://learn.chatgpt.com/docs/codex/cli. The macOS and Linux installer from that
   page:

   ```bash
   curl -fsSL https://chatgpt.com/codex/install.sh | sh
   ```

   Then sign in:

   ```bash
   codex login
   codex login status
   ```

   `codex login status` must report that you are logged in.

Check all three:

```bash
git --version
claude --version
codex --version
```

## 3. Install the plugin

Start Claude Code in any folder and run:

```text
/plugin marketplace add veliksergey/codex-review-loop
/plugin install codex-review-loop@codex-review-loop
/reload-plugins
```

**Private repository.** Claude Code clones it with the git credentials already
stored on your computer and never prompts for a password. Before the commands
above, set up one of:

- HTTPS: `gh auth login`, then `gh auth setup-git` (needs the GitHub CLI,
  https://cli.github.com).
- SSH: a GitHub SSH key loaded in `ssh-agent`.

**Check it worked.** Type `/codex-review-loop:` in Claude Code: the menu offers
`codex-loop` and `setup`. Or run `/codex-review-loop:setup check`, which reports
what is installed and changes nothing.

**A personal copy already exists?** If you set this loop up by hand earlier, a
personal skill at `~/.claude/skills/codex-loop/` keeps the short `/codex-loop` name
and loads next to the plugin's copy. Once the plugin works, rename or delete that
folder so only one copy is in use. Run `/codex-review-loop:setup` first: an older
hand-written rule in `CLAUDE.md` may point at a file in that folder, and setup offers
to replace it.

## 4. Set up your computer

```text
/codex-review-loop:setup
```

What it does, in order:

1. **Prerequisites.** Checks git, Claude Code, the Codex CLI, the Codex sign-in, and
   on Windows the Bash tool. It stops with the fix if one is missing.
2. **Choice of parts.** The Claude rules and the Codex reviewer rules are always
   offered. It asks whether you also want:
   - **Shared engineering invariants (recommended):** one set of rules both tools
     follow: honesty about what was run, security basics such as server-side
     authorization and tenant scope, change quality, and research habits.
   - **Codex review defaults:** the review model and reasoning effort, read from the
     model list your Codex install has cached, plus live web search so the reviewer
     can check current documentation.
3. **One change at a time.** For each block it shows the file, the exact text, and
   asks **Apply**, **Skip**, or, if you already have your own version, **Keep mine**.
   It backs up each file before the first write, as
   `<file>.bak-codex-review-loop-<date>-<time>`.
4. **Markers.** Every block it writes sits between `codex-review-loop:begin` and
   `codex-review-loop:end` markers. Running setup again updates those blocks in
   place, or reports "up to date". It never adds a second copy.
5. **Report.** A table of what changed, with backup paths, and the next steps.

Start a new Claude Code session afterwards: `CLAUDE.md` is read when a session
starts.

## 5. Prepare each repository

Open Claude Code at the root of the repository, not at a parent folder that holds
several repositories, so the right `AGENTS.md` loads for both tools. Then run:

```text
/codex-review-loop:setup repo
```

It offers three things, each shown before it is written:

1. **`docs/reviews/decisions.md`.** The table where Claude records findings it
   rejected, with the evidence. Codex reads it before each review and does not raise
   those findings again.
2. **`AGENTS.md`.** Both tools read this file. The loop needs it to name the check
   commands: typecheck, lint, test, build. Setup fills them only from what the
   repository states, such as `package.json` scripts, and writes `none` for a check
   the repository does not have. Add your branch policy and the rules a change must
   never break; Codex reviews against them.
3. **A per-repository review model (optional).** `.codex/config.toml` with its own
   `review_model`. Codex reads this file only when the repository is trusted: run
   `codex` once inside the repository and accept the trust prompt. Do not commit
   this file unless the whole team wants that default.

Setup never stages or commits. Read the new files and commit them yourself.

A folder that is not yet a git repository: run `git init` and commit a baseline
first. Any folder inside a repository needs no preparation:
`/codex-loop path/to/folder` reviews it.

## 6. First review

Make a small change in a prepared repository, then:

```text
/codex-loop --report-only
```

What you see:

1. Claude confirms the repository root and the Codex sign-in, runs the documented
   checks, and shows which task file it will use, or says there is none.
2. Codex runs. A small change takes from under a minute to a few minutes; larger
   ones take longer and run in the background.
3. A block headed `Codex review, round 1 of 1`, with the model and effort used,
   holding Codex's output word for word: a short summary, then one finding per line
   as `[P2] Title — <path>:<lines>` with a paragraph of explanation.
4. Claude's triage of each finding, the log folder, and a
   `codex resume <session-id>` command that opens Codex's full session.

With `--report-only`, nothing is edited. Without it, Claude goes on to fix valid
P0-P2 findings and runs another round.

## 7. Daily workflow

1. Open Claude Code at the repository root. Check the branch:
   `git branch --show-current`, `git status --short`.
2. Describe the task. Claude writes the task file and prints the acceptance
   criteria. Correct them now if they are wrong: Codex judges the change against
   them.
3. Claude implements, runs the checks, completes the handoff, and starts the loop.
   Say "skip review" in your request if you do not want one.
4. Watch the rounds. Requirement findings start with `(criterion N)`,
   `(beyond request)`, or `(handoff)`.
5. Read the final report: requirement checklist, what was fixed, what was rejected
   and why, P3 items awaiting your decision, checks run, log paths.
6. Decide on the P3 items, for example "fix P3 items 1 and 3".
7. Read the diff (`git diff`, `git diff --cached`) and commit it yourself, including
   `docs/reviews/decisions.md` when rows were added.

Commands and options:

| Command | Reviews | When |
|---|---|---|
| `/codex-loop` | All uncommitted changes: staged, unstaged, and new files | After any task. Claude runs it on its own. |
| `/codex-loop --report-only` | Same, one round, no edits | To look before anything changes |
| `/codex-loop <path> [<path> ...]` | Those files or folders as they are on disk, plus uncommitted changes in them | One module. A path with no uncommitted changes is an audit of existing code. |
| `/codex-loop --base main` | Every commit on the branch since it left `main`, plus uncommitted changes | Before a pull request |
| `/codex-loop --focus "text"` | Any of the above, with a focus for the reviewer | `"token audience, replay, open redirects"` |
| `/codex-loop --rounds 2` | Any of the above, at most two rounds | Small change or tight budget |
| `/codex-loop --model <slug> --effort <level>` | Any of the above, with another model or effort | Riskier code |

Paths and `--base` are separate modes; use one of them. `--focus`, `--rounds`,
`--model`, and `--effort` combine with either.

**Auditing existing code.** The default mode only covers changed files. To review
code that has not changed, name it: `/codex-loop src/billing --report-only`, one
top-level folder at a time. Claude then says it is an audit, uses no task file, and
asks nothing.

**Severity**, set by Claude after it verifies the finding; Codex's label is a
proposal and the same issue can come back P1 in one run and P2 in the next:

| Label | Meaning | What the loop does |
|---|---|---|
| P0 | Exploitable security flaw, data loss, or the feature unusable | Fixed first, with a test |
| P1 | Definite bug or security weakness in realistic use, or an unmet acceptance criterion | Fixed, with a test |
| P2 | Probable bug, missing guard or test, contract break, or a handoff claim the code does not support | Fixed, with a test |
| P3 | Improvement, simplification, or style | Listed for your decision |
| Rejected | Disproved by code, test output, or documentation | Row in `docs/reviews/decisions.md` |
| Disputed twice | Raised again after a recorded rejection | Escalated to you |

## 8. Models and effort

The review model is chosen in this order, first match wins:

1. `--model <slug>` on the command, for one review.
2. `review_model` in the repository's `.codex/config.toml`, if the repository is
   trusted.
3. `review_model` in `~/.codex/config.toml`.
4. Your Codex account's default model.

`review_model` applies to reviews only; your interactive Codex sessions keep their
own `model` setting.

Effort is `model_reasoning_effort`, in config or with `--effort <level>` for one
review. The common levels are `low`, `medium`, `high`, and `xhigh`; some models
accept more, such as `max` or `ultra`. Low effort is cheap but misses things: in
testing, a low-effort review missed an SQL injection that a focused review found.

Model names change as OpenAI releases and retires models, and the list depends on
your plan and your Codex version. `~/.codex/models_cache.json` lists the models
your installation knows, with the effort levels each supports; setup reads it when
it asks you.

A sensible default: a strong model at `high`. Raise the effort, or switch to the
most capable model, for authentication, authorization, sessions, tenant scope,
payments, migrations, and secrets, and for the last pass before a pull request.

## 9. Usage limits

Each review round is one heavy request against your ChatGPT plan's Codex allowance,
which has short (hours) and weekly windows. A full loop is up to three rounds plus
Claude's own usage on your Claude plan. Current limits per plan:
https://learn.chatgpt.com/docs/pricing

To stay inside them:

- Let the loop run once per finished task, not after every edit.
- Use `--rounds 2` for small changes.
- Keep the expensive model and high effort for risky code.
- When Codex reports a usage limit, the loop stops and says so. Wait for the window
  to reset, or rerun with a cheaper model.

## 10. Several reviews at once

Reviews in **different repositories** at the same time are fine. Each repository
has its own log folder, its own task file, and its own `decisions.md`, and two Codex
reviews have run side by side without interfering. They do share your usage
allowances and your computer's CPU and memory, so parallel test runs can be slow,
and two test suites that start a server on the same port can collide.

Two tasks in the **same repository** at the same time are not fine. They share one
working tree and one `task.md`: each review would see the other task's edits, judge
them against the wrong request, and the before/after fingerprint would stop the
loop with a false alarm. Put the second task in its own worktree under a different
folder name, for example `git worktree add ../myrepo-task2 -b task2`. The folder name
decides the log folder.

Two repositories with the **same folder name** in different places share one log
folder and overwrite each other's `task.md`. Rename one of the folders.

## 11. What Codex is told

Every review receives three layers:

| Layer | Content |
|---|---|
| Codex's built-in review guidelines | Compiled into the Codex CLI. They give way to more specific instructions. |
| The loop's review prompt | `plugins/codex-review-loop/skills/codex-loop/review-prompt.md`, filled per round with the scope, your `--focus`, and the whole task file. It puts security first, asks for unmet criteria as P1, additions beyond the request as P2 or P3, and unsupported handoff claims as P2. |
| `AGENTS.md` | `~/.codex/AGENTS.md` and the repository's own `AGENTS.md`. |

The output format is Codex's own: a summary, then `Full review comments:` with one
`[Pn]` finding per item. A prompt cannot change that format.

## 12. Reading the logs

Everything is in `~/.claude/codex-reviews/<repo>/`:

| File | Contents |
|---|---|
| `task.md` | The current task file. Overwritten when the next task starts. |
| `<run>-task.md` | The task file as it stood at the final report. |
| `<run>-round<N>-prompt.md` | The exact prompt sent to Codex. |
| `<run>-round<N>-codex.md` | Codex's review. |
| `<run>-round<N>-codex.log` | Codex's progress, the commands it ran, and the session id. |
| `<run>-round<N>-claude.md` | Claude's triage table and requirement checklist. |

In the `.log` header, `sandbox:` must read `read-only`. The header's `model:` line
is the session model; the review itself runs on the review model, which the report
names.

Watch a review live from a second terminal:

```bash
tail -f ~/.claude/codex-reviews/<repo>/<run>-round1-codex.log
```

```powershell
Get-Content -Wait -Tail 30 "$HOME\.claude\codex-reviews\<repo>\<run>-round1-codex.log"
```

`codex resume <session-id>` opens Codex's full session afterwards. The raw records
are in `~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-*.jsonl`; a review writes two,
and the review thread's first line contains `"subagent":"review"`.

## 13. Updating and removing

**Update the plugin.** In a terminal, refresh the list of versions, then update:

```bash
claude plugin marketplace update codex-review-loop
claude plugin update codex-review-loop@codex-review-loop
```

The first command alone only refreshes the list; the installed plugin keeps its old
version until the second one runs. Then restart Claude Code, or run
`/reload-plugins` in an open session, and run `/codex-review-loop:setup`, which
updates the rule blocks in your global files when the templates changed.
`claude plugin list` shows the installed version; compare it with the newest entry
in `CHANGELOG.md`.

For automatic updates: `/plugin`, **Marketplaces**, `codex-review-loop`,
**Enable auto-update**. With a private repository, automatic updates need a stored
credential (section 3) and otherwise fail quietly, leaving the installed version in
place.

**Update Codex:** `codex update` updates installs that support it; otherwise use the
method you installed with. On Windows, run `codex update` from PowerShell rather
than Git Bash: from Git Bash the updater has failed to unpack the download.

**Remove everything:**

```text
claude plugin uninstall codex-review-loop@codex-review-loop
claude plugin marketplace remove codex-review-loop
```

Then delete the marked blocks from `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, and
`~/.codex/config.toml`, or restore the backups setup made. Delete
`~/.claude/codex-reviews/` if you no longer want the logs.

## 14. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `/codex-review-loop:` offers nothing | The plugin is not loaded. Run `/reload-plugins`, or check `/plugin` for errors. With a private repository, check the stored git credential (section 3). |
| Claude does not run the loop after a task | `~/.claude/CLAUDE.md` lacks the `claude-rules` block, or the session started before setup. Run `/codex-review-loop:setup check`, then start a new session at the repository root. |
| Setup stops at the Bash check on Windows | Git for Windows is missing. Install it and restart Claude Code. |
| `Not logged in` | Run `codex login`, then `codex login status`. |
| Codex judged the change against the wrong request | `task.md` was stale. Claude prints the request before each run so you can catch it. Ask Claude to rewrite the task file from your request, then rerun. |
| Codex reported files from the log folder | Logs were written inside the repository. They belong in `~/.claude/codex-reviews/`. Move them out. |
| Log header says `sandbox: workspace-write` | Only possible in a hand-run command: in a trusted repository Codex defaults to a writable sandbox. The loop always forces read-only. By hand, add `-c 'sandbox_mode="read-only"'`. |
| `the argument '--uncommitted' cannot be used with '[PROMPT]'` | Only from a hand-run `codex review`. Codex rejects scope flags together with a custom prompt; the loop puts the scope in the prompt instead. |
| `codex exec` hangs on `Reading additional input from stdin...` | Codex reads standard input until it ends, even with a prompt argument. By hand, add `< /dev/null` or pass the prompt as `-` from a file, as the loop does. |
| `warning: unable to access '.../.config/git/ignore': Permission denied` | Harmless: the read-only sandbox blocks git from reading a global ignore file. |
| The review takes longer than ten minutes and times out | Ask Claude to rerun it in the background, or narrow the scope with paths. |
| Codex rejects the model or effort | Check the slug and the levels in `~/.codex/models_cache.json`. Retired models disappear from that list. |
| A repository's `.codex/config.toml` is ignored | The repository is not trusted. Run `codex` once in it and accept the trust prompt. |
| `CreateProcessWithLogonW failed: 1385` in the log (Windows) | Windows policy denies the Codex sandbox accounts the logon they need. The review usually still completes, more slowly. See OpenAI's Windows sandbox page: https://learn.chatgpt.com/docs/windows/windows-sandbox |

## 15. Known limits

- **Tested on Windows only.** The commands were chosen to work in bash on macOS and
  Linux too, but no review has run there yet.
- **Codex may not run your tests.** Its read-only sandbox can block a test runner
  from starting child processes. Codex then checks test claims by reading the code;
  Claude's own test run is the proof that the suite passes.
- **The fingerprint check covers git's view of the tree:** file status, the
  unstaged diff, the staged diff, and the contents of untracked files. It does not
  hash files git ignores, such as `.env` or build output. Codex's read-only sandbox
  is the main guarantee.
- **Severity labels vary between runs.** Claude assigns the final label.
- **Three rounds is a hard cap.** Fixes made in the last round have passed the
  checks but not another review. The final report says so.
