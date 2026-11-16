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

### What leaves your computer

Codex runs on your ChatGPT account, so every review sends data to OpenAI: the whole
task file, and whatever the reviewer reads while it works. Read-only means the reviewer
cannot change your files. It does not mean your files stay on your computer: the
sandbox blocks writing, not reading, so the reviewer can read files outside the change
and outside the repository, and what it reads is sent as well. Its web searches, and
the public pages it opens, are requests it composes itself. Claude starts the loop on
its own after each implementation task. Say "skip review" for code that must not be
sent, and keep secrets out of your requests. The plugin's authors receive nothing.

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

   Then run `claude` once and sign in through the browser.
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

**Private fork or mirror.** The repository above is public, so the install needs no
GitHub credentials. Only if you install from a private fork or an internal mirror:
Claude Code clones it with the git credentials already stored on your computer and
never prompts for a password, so before the commands above, set up one of:

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
     model list your Codex install has cached. The review model applies to reviews
     only. The effort setting applies to every Codex session on your computer, so
     leave it unset if you only want it for reviews, and pass `--effort` instead.
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
   those findings again. A row that is not committed yet is Claude's own claim: the
   next review checks it once against the code.
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
5. Read the final report. It starts with one verdict from the table below, then
   lists the findings Claude rejected or moved below the must-fix line, then the
   requirement checklist with who verified each criterion, what was fixed, P3 items
   awaiting your decision, checks run, and log paths.
6. Decide on the P3 items, for example "fix P3 items 1 and 3".
7. Read the diff (`git diff`, `git diff --cached`) and commit it yourself, including
   `docs/reviews/decisions.md` when rows were added.

The verdict is one of five. The first that fits the run is used:

| Verdict | What happened | What to do |
|---|---|---|
| `review failed` | The last round gave no usable review: Codex failed or was stopped, no sandboxed command ran, a tool that should be off was called, the working tree changed during the review, or the reviewer's tools could not be limited. | Fix the cause the report names and rerun. Nothing was judged. |
| `open findings` | A valid P0-P2 finding that belongs to the task is not fixed, or Claude and Codex disagree on a finding for the second time. A defect outside the task does not count here; see two rows down. | Read those findings and decide. |
| `fixes not re-reviewed` | Claude fixed findings in the last allowed round, or the loop was stopped, so no review has seen the latest code. | Rerun the loop, or read the last fixes yourself. |
| `clean with unverified items` | No finding is open, but something rests on Claude alone: a criterion the reviewer could not check, a finding Claude rejected or moved to P3, a new file the review never mentioned, or a defect left as outside the task. | Read the listed items. This is the usual result when Codex cannot run your tests. |
| `verified` | The last review saw the final code and found nothing to fix, the reviewer checked every criterion, and Claude overrode nothing. | Read the diff and commit. |

The checklist names who verified each criterion: the reviewer, the implementer, which
is Claude's own test or check, or nobody. A criterion that Claude fixed counts as
verified by the reviewer only once a later review has seen the fix. "Implementer
overrides" at the top of the report lists every finding Claude rejected and every
finding Codex rated P0 to P2 that Claude rated P3. No reviewer has confirmed those
calls; they are yours to check.

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
| `/codex-loop --web off` | Any of the above, with no web search for the reviewer | Code you do not want described in a search query |
| `/codex-loop --web live` | Any of the above, asking Codex for live web search | See [What the reviewer can use](#what-the-reviewer-can-use) before relying on the difference |
| `/codex-loop --allow-tools` | Any of the above, with your own Codex connectors, plugins, and MCP servers available to the reviewer | A review that needs one of those tools |

Paths and `--base` are separate modes; use one of them. `--focus`, `--rounds`,
`--model`, `--effort`, and `--web` combine with either. `--allow-tools` does too, but
not together with `--web off`.

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
4. The session model: the effective `model` setting — in a trusted repository's
   `.codex/config.toml` first, else in `~/.codex/config.toml` — and with no `model`
   anywhere, your Codex account's default. OpenAI's configuration reference states
   that without `review_model` a review runs on the current session model, and that
   a trusted project's config outranks the user config (checked 2026-10-05).

`review_model` applies to reviews only; your interactive Codex sessions keep their
own `model` setting.

Effort is `model_reasoning_effort`, in config or with `--effort <level>` for one
review. Unlike `review_model`, the config setting is not limited to reviews: it sets
the effort of every Codex session. The common levels are `low`, `medium`, `high`, and `xhigh`; some models
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
folder and overwrite each other's `task.md`. Rename one of the folders. The loop
catches the mix-up before it sends anything: the first repository to use a log folder
leaves its path in `repository-root.txt` there, and the loop stops when that file
names another repository. By then the second task may already have overwritten
`task.md`. If you moved a repository, delete `repository-root.txt` and run again.

## 11. What Codex is told

Every review receives three layers:

| Layer | Content |
|---|---|
| Codex's built-in review guidelines | Compiled into the Codex CLI. They give way to more specific instructions. |
| The loop's review prompt | `plugins/codex-review-loop/skills/codex-loop/review-prompt.md`, filled per round with the scope, your `--focus`, the whole task file, and the list of instruction files the change edits. It puts security first, asks for unmet criteria as at least P1, additions beyond the request as P2 or P3, and unsupported handoff claims as P2. |
| `AGENTS.md` | `~/.codex/AGENTS.md` and the repository's own `AGENTS.md`. |

The output format is Codex's own: a summary, then `Full review comments:` with one
`[Pn]` finding per item. A prompt cannot change that format.

The prompt also keeps the change from deciding how it is judged:

- **A decision does not excuse a defect.** The task file lists the decisions made
  while implementing, each marked as yours, with the date and your words quoted, or as
  the implementer's. The reviewer is told that a decision explains what was intended,
  and to report one that contradicts your request, a criterion, or a repository rule,
  or that creates a security, data-loss, or correctness defect.
- **A change must not rewrite the rules it is judged by.** Before each round the loop
  lists the instruction files the change edits: `AGENTS.md`, `AGENTS.override.md`, and
  `CLAUDE.md` in any folder, anything under a `.codex` folder, and
  `docs/reviews/decisions.md`. It names them to you, and the prompt tells the reviewer
  to apply the committed version of each, to review the edit like code, and to check
  each new row of `decisions.md` once against the code.
- **One severity scale.** The prompt says that its P0 to P3 scale replaces the one
  built into Codex, and that P0 covers an exploitable flaw or data loss even when a
  specific input is needed.
- **Existing defects count in an audit.** When you review chosen files or folders, the
  reviewer is told that defects already in them are in scope, changed recently or not.
- **The request and the criteria are watched.** Before every round, and before the
  final report, the loop takes a hash of your request and the acceptance criteria in
  the task file: everything from the request heading to the out-of-scope heading, so a
  request you pasted with headings of its own counts as a whole. If the value changes
  during a run, Claude tells you at once and shows both sections. Rewording a criterion
  to make a finding go away is against the rules; this makes it visible.

Observed on 2026-11-13 in seeded reviews of a made-up repository, one run each: the
reviewer reported a defect that a decision excused, one that an edited `AGENTS.md`
allowed, one that a false row in `decisions.md` covered, and an existing defect in an
unchanged file. One run is not a measurement.

### What the reviewer can use

Codex's read-only sandbox limits the commands the reviewer runs. A Codex installation
can also have connectors to outside services, plugins, and MCP servers, and OpenAI's
security documentation says the sandbox's network controls do not cover those. So the
loop decides which of them a review gets:

| Tool | Default review | How to change it |
|---|---|---|
| Sandboxed shell, read-only | On | Always on. A review in which no sandboxed command ran is stopped as failed. |
| Web search, and opening public pages | On | `--web off` removes it for one review. |
| Connectors other than web search | Off | `--allow-tools` |
| Codex plugins and the MCP servers they bring | Off | `--allow-tools` |
| MCP servers in your Codex configuration | Off | `--allow-tools` |

After each review the loop prints one line of facts read from Codex's log: the CLI
version, the sandbox mode, how many shell commands ran, how many web searches were
made, and any other tool that was called. It stops when a tool that should be off
appears there.

Three things to know, each observed on 2026-11-13:

- **Web search is itself a connector.** That is why the loop keeps one connector on
  and turns the rest off. The connector is named by an identifier that OpenAI does not
  document. If a Codex update renames it, reviews lose web search and the reviewer
  says so in its summary.
- **`cached` and `live` made no difference.** The loop passes `cached` by default and
  `live` with `--web live`, as the Codex configuration reference describes. In a test
  the search tool fetched a live page in both modes. Treat web search as on or off.
- **Codex's built-in tools stay.** Besides the shell there are tools such as its patch
  and image tools. The read-only sandbox and the before-and-after fingerprint are the
  guard for those.

A connector that any Codex configuration turns on by name stays on when the loop turns
the default off, and an entry for a connector turns it on even without an `enabled`
key. The loop does not read your configuration files to find such entries. Before
every round it asks Codex itself which connectors and MCP servers a session with the
review's flags would have, and it does not start the review if anything besides web
search is on. It reads the tools Codex declares for that session, not the instructions
printed beside them, so an `AGENTS.md` that only mentions a connector does not stop a
review. A tool that a configuration hides from Codex's tool lists with
`omit_tools_from` and leaves to the scripts Codex runs counts as on, and that holds
for web search too if a configuration moves it there. To review anyway, turn that
connector off in your configuration, or pass `--allow-tools`.

## 12. Reading the logs

Everything is in `~/.claude/codex-reviews/<repo>/`:

| File | Contents |
|---|---|
| `repository-root.txt` | The path of the repository this folder belongs to. The loop stops when another repository with the same folder name tries to use the folder. |
| `task.md` | The current task file. Overwritten when the next task starts. |
| `<run>-task.md` | The task file as it stood at the final report. |
| `<run>-summary.json` | The run in a fixed shape, written at the final report: the mode and options, a hash of the request and criteria at the start and at the end, the verdict, the checklist, and for each round its duration, its fingerprint, whether it gave a usable review, what the reviewer ran, and each finding's tag, labels, and decision. It holds no text of a finding. |
| `<run>-round<N>-prompt.md` | The exact prompt sent to Codex. |
| `<run>-round<N>-codex.md` | Codex's review. |
| `<run>-round<N>-codex.log` | Codex's progress, the commands it ran, and the session id. |
| `<run>-round<N>-claude.md` | Claude's triage of the round, in a fixed shape: one table row per finding with Codex's label, Claude's label, the decision, the evidence, and the proof; the requirement checklist; and a judge record that identifies the review: plugin version, prompt hash, commit, fingerprint, web search mode, and what the reviewer ran. |

In the `.log` header, `sandbox:` must read `read-only`. The header's `model:` line
is the session model; the review itself runs on the review model, which the report
names. The line of facts the loop prints under each review is read from this log.

Watch a review live from a second terminal:

```bash
tail -f ~/.claude/codex-reviews/<repo>/<run>-round1-codex.log
```

```powershell
Get-Content -Wait -Tail 30 "$HOME\.claude\codex-reviews\<repo>\<run>-round1-codex.log"
```

`codex resume <session-id>` opens Codex's full session afterwards. The raw records
are in `~/.codex/sessions/<yyyy>/<mm>/<dd>/`, named `rollout-*.jsonl`. Codex stores
older ones compressed, as `rollout-*.jsonl.zst` (observed 2026-11-12). A review
writes two records, and the review thread's first line contains
`"subagent":"review"`.

### Figures about your own reviews

The logs answer questions about how the loop works for you: how many rounds a run
takes, how often the first round is clean, which checks produce findings, how often
Claude overrides the reviewer, what the reviewer ran, and how long a round takes. A
script in this repository prints them. It is not part of the installed plugin, so run
it from a clone, with Python 3.8 or newer:

```bash
python tests/loop_stats.py ~/.claude/codex-reviews/<repo>
```

Give it one log folder or several; without one it reads the folder of the repository
you are in. A run that has a `<run>-summary.json` is read from that file. A summary
that does not fit its shape or contradicts itself, for example by calling a round
reviewed in which no sandboxed command ran, is named with the reason and not used.
Such a run, and every older run, is read from its review files, logs, and triage
notes, which give fewer answers: what the reviewer reported comes from the review file,
and decisions and final labels are known only from a summary or from a triage note in
the fixed shape that lists the same findings. A round that gave no usable review,
because Codex failed, its review is missing, its log cannot be read, or no sandboxed
command ran, is counted on its own line and enters no figure about findings: an unknown
result is not a clean one. The script prints to the terminal and writes no file. The
figures describe your own work; keep them out of any repository.

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
| The loop stops: no sandboxed shell command ran | Codex could not start its sandboxed shell, so the reviewer could not read your code through the sandbox, whatever it wrote. Run `codex update` and rerun. On Windows, see the Windows sandbox page above. `--allow-tools` does not get around this: the loop stops then too. |
| The loop stops: the reviewer's tools cannot be limited | The message says which of three causes applies. A tool is still offered to the reviewer: some Codex configuration turns a connector on by name, or an MCP server stayed on, and the message names the tool; turn it off there. Or an MCP server cannot be turned off: `codex mcp list --json` failed, printed something the loop cannot read in full, or printed a server name with a character other than letters, digits, `_`, `-`, and `.`. Or Codex could not show which tools a session would have, or showed a list the loop cannot read or one without any tool: update Codex. `--allow-tools` runs the review with your own tools instead. |
| The loop stops: a tool that should be off was called | A connector, plugin, or MCP tool appeared in Codex's log although the loop turned them off. A Codex update may have changed how they are disabled. Report it in the repository's issues with your Codex version. |
| The loop stops: the log folder belongs to another repository | Two repositories whose folders have the same name would share one task file and one set of logs. Rename one of the folders. If you moved the repository, delete `repository-root.txt` in the log folder the message names, and rerun. Do the same when the message says that file is empty or cannot be read, after checking that no other repository uses the folder. |
| The loop stops: the request and the criteria cannot be found in the task file | The task file needs a `## Request` heading and, below it, a `## Acceptance criteria` heading. A fenced block or an HTML comment that never closes hides every heading under it: close it, or quote the request line by line with `>`. |
| The reviewer says it has no web search tool | You passed `--web off`, or a Codex update renamed the search connector. See [What the reviewer can use](#what-the-reviewer-can-use). |

## 15. Known limits

- **Tested on Windows only.** The commands were chosen to work in bash on macOS and
  Linux too, but no review has run there yet.
- **Codex may not run your tests.** Its read-only sandbox can block a test runner
  from starting child processes. Codex then checks test claims by reading the code;
  Claude's own test run is the proof that the suite passes.
- **The fingerprint check covers git's view of the tree:** file status, the
  unstaged diff, the staged diff, and the contents of untracked files, with untracked
  links recorded by where they point rather than followed. Diff tools set in your git
  config do not affect it. It does not
  hash files git ignores, such as `.env` or build output. For those the guard is
  Codex's read-only sandbox, which limits the reviewer's commands, together with the
  other tools being off.
- **The reviewer can read outside the repository.** The read-only sandbox blocks
  writing, not reading. Observed on 2026-11-12: its policy grants read access from
  the root of the file system. What it reads is sent to OpenAI with the rest of the
  review: see [What leaves your computer](#what-leaves-your-computer).
- **The facts under each review come from an undocumented log.** Codex's log format
  can change with any release. A change that hides the shell commands would make the
  loop stop every review as failed until the plugin is updated. The log also holds
  what the reviewer's commands printed, so a printed line can look like a tool call.
  The loop lists the log line of every call it counted, and Claude reads each one
  before deciding that a tool that should be off was not called.
- **Severity labels vary between runs, and the reviewer avoids P0.** Observed on
  2026-11-13: in every seeded review that tried it, the reviewer rated a defect that
  deleted stored data, and one that let a user delete another user's data, P1, although
  the prompt's scale makes both P0 and says so. Claude assigns the final label from the scale, and
  the triage note keeps both labels.
- **A change to the criteria before the loop starts is not seen.** The loop takes its
  first hash of the request and the criteria when it starts, not when Claude first
  showed them to you. Read the criteria Claude prints at the start of a task, and the
  request the loop prints before round 1.
- **The run summary is written by Claude.** It copies labels and decisions from its
  own triage notes into `<run>-summary.json`. The statistics script checks the shape of
  that file and that it does not contradict itself, not whether it matches the notes.
  The summary keeps the hash of the request and the criteria at the start and at the
  end of a run: a change that was undone in between is reported by the loop when it
  happens, and does not show in the summary.
- **Codex still loads the instruction files from disk.** The loop cannot change which
  `AGENTS.md` Codex reads. It tells the reviewer which instruction files the change
  edits and to apply their committed versions; whether the reviewer does so is up to
  the reviewer.
- **Three rounds is a hard cap.** Fixes made in the last round have passed the
  checks but not another review. The final report's verdict is then `fixes not
  re-reviewed`.
- **Who verified a criterion is read from the review's text.** Claude marks a
  criterion as verified by the reviewer when the review says it checked it and Claude
  has not changed it since. That is Claude's reading of a summary, not a record of
  what Codex did.
