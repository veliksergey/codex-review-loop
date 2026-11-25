# Parallel tasks: plan

Prepared on 2026-11-24 against plugin 0.7.0, `main` at `2a99609`, and updated on
2026-11-25 with the maintainer's decisions. It plans a feature that is not built yet:
several tasks in one repository at the same time, each in its own folder and branch,
each reviewed by the loop, each merged back into a base branch, automatically when the
task ends clean and the user allowed it, otherwise after the user's OK. Section 10
records the decisions, and section 7 starts with the experiments that must pass
before any code is written.

Terms used throughout:

- **Main folder**: the repository's own checkout, where the user normally works.
- **Task**: one request, taken from the user's words to a merge.
- **Task folder**: a git worktree beside the main folder that holds one task's branch.
- **Base**: the branch a task starts from and merges into.
- **Control session**: the user's ordinary Claude Code session in the main folder.
- **Task session**: a Claude Code session whose working directory is a task folder.
- **Agent view**: Claude Code's screen for background sessions, opened with
  `claude agents`.
- **The prototype**: `worktree-task` 0.3.0, a separate plugin by this repository's
  owner, at commit `3a7a44b`. It runs one task per terminal in a worktree beside the
  main folder, reviews it, and merges it after the user's OK.

## Summary

**The design (decision D1): one terminal for the user, one background session per
task, and the review state in text files that one command turns into a table.**

- **Not everything in one conversation.** Running every task inside one session, as
  subagents, keeps each task's work in its own context, but every exchange with the
  user has to pass through that one session: Claude Code removes `AskUserQuestion`
  from every subagent, and background subagents raise every permission prompt in the
  main session. With several tasks, that session becomes a switchboard for all their
  questions and approvals, which is the request's worry, "too much text in one place",
  in another form.
- **The user keeps one terminal: the control session in the main folder, on `dev`.**
  From there, one command creates a task: its folder and branch, its task file, and a
  background Claude Code session that works in that folder. Claude Code's agent view
  already shows one row per background session, grouped as needs input, working, and
  completed, with a one-line summary, a peek panel to answer without leaving the list,
  and a full conversation one key away. It opens from the control session with `←` on
  an empty prompt. Claude Code's own comparison of its parallel features recommends
  agent view when "you hand off independent tasks and check back later", and
  worktrees when the tasks touch the same files.
- **The plugin adds what agent view cannot know: where each review stands.** Each
  task keeps its record outside the repository, in the loop's log folder for that
  task folder: the task file, a status file, every review round, and the final
  report. `/codex-review-loop:task status` prints one table of every task of the
  repository, in progress and done: its phase, its review round and verdict, its open
  findings, what it waits for, and the user's next step.
- **Folders, branches, base.** A task folder is `../<repo>-<slug>` on the new branch
  `task/<slug>`, started from the base. The base is the branch checked out in the main
  folder when the task starts, which the user chooses before giving tasks, usually
  `dev`. A task for `main` or `master` asks the user to confirm first, and offers to
  switch to `dev` (decision D3).
- **Approvals.** One is planned for every task: the OK that starts it, after the user
  has seen the acceptance criteria, which also shows whether the task merges on its
  own when it ends clean. A second OK, to commit and merge, comes when the task does
  not end clean, when the user set it to ask, or when its base is `main` or `master`.
  Two more come in the control session: one retires the folders of merged tasks,
  moving them aside and deleting nothing of them, only the task's session, and one
  purges retired folders later, deleting only what it listed. Everything else asks
  only when it must: a question the request leaves open, a permission prompt, a
  finding the loop escalates, a conflict, or the user giving a task up. In between,
  the work runs on its own: folder, branch, local files, dependencies, tests written
  first when they help, implementation, checks, review rounds with their fixes,
  report, commit, rebase, checks again after a rebase and a review again when it is
  needed, and a fast-forward merge.
- **A clean task merges on its own (decision D5).** It merges without asking only
  when every condition of 4.7, step 2 holds: the latest review found nothing at all,
  P3 included; no finding was rejected or overridden; nothing is left for the user to
  answer or decide; the reviewer confirmed every acceptance criterion; no locked test
  changed; and the checks pass on the commit that lands. It never merges on its own
  into `main` or `master`, and it gets a new review after any rebase onto a moved base
  (decision D13). The board shows every automatic merge with its time and commit.
- **Reuse the prototype's git steps.** Its `worktree.sh` creates, commits, rebases,
  merges, and removes task folders, with guards that its 973-line test file checks. The
  prototype's workflow runs that file on Linux, macOS, and Windows, and its run at
  `3a7a44b` passed. This plan ports them and adds what they lack for tasks that run at
  the same time: one merge at a time, from the exact base commit to the exact commit
  that was checked; a guarded way to resolve a conflict and to give a task up; guards
  for files git does not show, which a rebase or a removal would otherwise overwrite
  or delete without asking; and a cleanup that moves folders aside and deletes only in
  a later purge. The prototype's tests-first stage comes too: for a bug fix or
  behavior a test can check, a separate test-author agent writes the tests from the
  request before the code exists, and they are locked. Its Claude review stage stays
  out of the first release (decision D7).
- **Experiments first.** Several facts the design needs are undocumented, such as
  whether a session can start a background session from its shell. Phase 0 checks
  them before any plugin code exists, those that could overturn the most first, and
  stops at the first failure (decision D10).

## 1. The request and where this plan answers it

| The request asks | Short answer | Section |
|---|---|---|
| Work on several tasks with Codex reviews in one repository at the same time | One task folder, branch, and task session per task. The loop runs inside each task folder with that folder's own task file and logs. | 3, 4.2, 4.6 |
| A new folder and branch per task, merged back into `dev` by default, or `main` | `../<repo>-<slug>` on `task/<slug>`. The base is the branch checked out in the main folder, usually `dev`; `main` needs the user's confirmation first, and a repository without `dev` uses the branch checked out. One commit per task, rebased and fast-forwarded into the base: on its own when the task ends clean and the user allowed it, never into `main`; otherwise after the user's OK. | 4.1, 4.7 |
| Everything in one terminal, or one terminal on `dev` that creates folders and branches and keeps the work, the review results, and the status in text files | The second, with Claude Code's agent view in that same terminal for the sessions, and the record in text files outside the repository. | 2, 3, 4.4 |
| Easy to use, and clear what happens in every task, in progress or done | Agent view for what each session is doing now; the board for review state and next steps; the task's files for the full record. | 4.5 |
| Automate as much as possible, with the user's approval when needed | Ten approval points: three come with every task, its start, the retirement of its folder, and its purge; the merge approval comes unless the task ends clean and merges on its own; the others only when something needs the user or the user gives a task up. | 4.3, 4.7 |

## 2. Ways to watch and steer several tasks

Read on 2026-11-24: Claude Code's pages on running agents in parallel, agent view,
worktrees, subagents, agent teams, cross-session messaging, and permissions, and the
help of Claude Code 2.1.331; the prototype's code; and current third-party tools
(section 12).

| Option | What the user watches | Who can ask the user | Verdict |
|---|---|---|---|
| A. Every task in one conversation: the control session starts one subagent per task, each in its own worktree | The control session: each subagent works in its own context and returns a summary | Only the main conversation. `AskUserQuestion` is removed from every subagent, and background subagents raise every permission prompt in the main session, so the control session relays every question and approval of every task. | Rejected |
| B. One interactive terminal per task, as in the prototype | One terminal per task, with no overview | Each terminal | Not built: the design only if spike S1 or S2 fails (decision D1) |
| C. One control session; every task a background session in its own task folder; agent view for sessions, a board for reviews | Agent view: one row per task with its state and a summary. The board: review state and next steps. The files: the full record. | Each task session, reached from agent view by peek or attach | **Chosen** (decision D1) |
| D. An agent team: the control session leads, each task is a teammate | Split panes, or an in-process panel | The lead and the teammates | Rejected: experimental and off by default, and agent teams "don't isolate teammates in worktrees" |
| E. A third-party manager of sessions and worktrees | Its own screen | Its own screen | Not chosen; see below |
| F. Claude Code on the web: each task a cloud session | A browser | A browser | Not chosen: the loop runs the user's local Codex CLI against a local checkout, and a cloud session has neither |
| G. Projects: one conversation at claude.ai/code or in the desktop app that starts parallel threads, in the cloud or, through Remote Control, on the user's computer, and shows which need the user | That conversation | The project's conversation | Not chosen for the first release: a public beta on some plans, outside the terminal this plugin runs in; whether a thread on the user's computer loads this plugin and runs the loop is not verified |
| H. A dynamic workflow: a script that runs many subagents, with their progress in `/workflows` | `/workflows` in one session | Only the main conversation: its workers are subagents | Rejected for option A's reasons: it suits one job split into many parts, not separate tasks with their own questions and approvals |

Why C over B: B works, and the prototype proves its git steps, but the user has to
open, arrange, and remember one terminal per task, and nothing shows all tasks at
once. C keeps one terminal and adds two overviews, agent view for sessions and the
board for reviews. Each task still has its full conversation, one key away. B is not
built alongside C: it becomes the design only if phase 0 shows that C cannot work,
because spike S1 or S2 fails (decision D1). Until then, a user whose organization
turns agent view off cannot run parallel tasks, and the review loop works for that
user as before.

Why C over E: a survey of current tools (section 12) found that the purpose-built ones
converge on the shape agent view has: one list with a state per task, a way to peek at
or attach to one task, and a notification when a task needs input. Several of them are
built on tmux, which does not run natively on Windows; several changed status in 2026,
such as Crystal, deprecated for its successor, Vibe Kanban, which announced its sunset,
and git-worktree-runner, archived; the desktop apps are separate products; and none of
them runs this plugin's review loop or knows its review state. Agent view comes with
Claude Code, runs on Windows, and needs nothing else installed.

The request's two options are closer than they look. The tools converge on one view
that lists every task in one line and opens one task at a time. That is the request's
second option, one terminal on `dev`, without a terminal for each task.

What C relies on, from Claude Code's documentation (agent view page, read
2026-11-24):

- `claude --bg --name "<name>" "<prompt>"` starts a background session in the current
  directory and prints its short id. `claude agents --json` is "the supported way to
  read session state from outside Claude Code": for each session its `cwd`, `kind`,
  `id`, `name`, `state` (`working`, `blocked`, `done`, `failed`, `stopped`), and while
  its process runs, `status` (`busy`, `waiting`, `idle`) and `waitingFor`
  (`permission prompt`, `input needed`, and others).
- Agent view groups sessions as pinned, ready for review, needs input, working, and
  completed. A row shows the name, a one-line summary written by a small model, and
  the age. `Space` opens a peek panel to read the latest output or question and to
  reply; `Enter` attaches for the full conversation; `←` detaches. While agent view
  is open, Claude Code notifies the terminal when a session starts needing input,
  finishes, or fails. In a regular session the footer counts the background
  sessions waiting for input, such as `← 2 agents`.
- Background sessions keep running when agent view or the terminal closes: a
  supervisor process hosts them. They stop when the computer shuts down, and
  `claude respawn <id>` restarts one.
- Limits: agent view is a research preview, so its screen and keys may change; every
  background session uses the subscription's quota on its own; the `--cwd` filter and
  the `@<repo>` picker leave out worktrees created outside the repository, such as
  `../feature`, although their sessions are listed in the default view.

## 3. The design in one picture

```text
main folder, on dev                        task folder ../<repo>-<slug>, on task/<slug>
control session                            task session (background)
─────────────────────────────────────      ─────────────────────────────────────────────
/codex-review-loop:task new "<request>"
  questions, criteria, slug, base,
  merge: automatic when clean, or ask
  user's OK ──▶ folder + branch from dev,
               listed local files copied,
               task file + status file,
               session started  ─────────▶ install dependencies, baseline checks
                                          tests first when they help: written by
                                            the test-author agent, failing, locked
                                          implement until the checks pass
                                          review loop: Codex rounds, fixes, report
                                          clean: no question; otherwise
                                          "Commit and merge into dev?" ◀── user's OK
                                          one commit, rebase onto dev
                                          checks again when dev moved; review again
                                            before an automatic merge, or when dev
                                            changed the same files
  dev fast-forwarded  ◀───────────────── merge (fast-forward only, guarded)
/codex-review-loop:task status   the board: every task, any time
/codex-review-loop:task clean    ends merged tasks' sessions, moves their folders aside
/codex-review-loop:task purge    later: deletes retired folders, only what it listed
← or claude agents               agent view: what each session does, what needs you
```

## 4. Design

### 4.1 Folders, branches, and the base

- **Task folder:** `../<repo>-<slug>`, beside the main folder, created with
  `git worktree add --no-track -b task/<slug> <folder> <base commit>`, as the
  prototype's `create` does.
- **Why beside the main folder, not under `.claude/worktrees/`** where
  `claude --worktree` puts its worktrees:
  1. The loop names its log folder after the folder name of the repository root
     (`log-dir.sh`), and the task-file rule that setup installs in
     `~/.claude/CLAUDE.md` says the same. Beside the main folder that name is
     `<repo>-<slug>`, so each task gets its own task file and logs with no change to
     the loop or to the installed rules. Under `.claude/worktrees/<slug>` it would be
     `<slug>` alone, and two repositories with a task of the same name would claim one
     log folder, which `log-dir.sh` refuses.
  2. A folder inside the main folder is seen by tools that scan it, such as test
     runners, type checkers, and an IDE's index, unless each repository ignores it.
     Claude Code's own page advises adding `.claude/worktrees/` to `.gitignore`.
  3. `claude --worktree` cannot start from a named branch: `worktree.baseRef` takes
     only `fresh` or `head`, and the page says to create the worktree with git to
     start from a specific branch.
- **Branch:** `task/<slug>`. The slug is `--name`, or a short name derived from the
  request: lowercase letters, digits, and inner hyphens, at most 40 characters.
  `task new` refuses a slug whose folder or branch exists, and one whose log folder
  `~/.claude/codex-reviews/<repo>-<slug>/` names another repository in its
  `repository-root.txt`, before it creates anything.
- **Task id:** each task also gets an id, its start time and slug as
  `<yyyymmdd-hhmmss>-<slug>`, so that a slug used again after a cleanup names a new
  task, not the old one. `task new` allocates it under the lock of `tasks.md`
  (4.7, rule 9) and refuses an id that `tasks.md` already holds, so two tasks started
  in the same second get different ids, and the second of two with the same slug
  stops. Under the same lock it also refuses a slug that a line of `tasks.md` holds
  for a task in any phase but `purged`, whatever its id, so that two control
  sessions that approve the same slug a second apart cannot both reach that slug's
  folder, branch, and log folder: the second stops before it creates anything. The id is in `tasks.md` and in the status file. When the log folder holds an earlier task with
  the same slug, `task new` first moves that task's task file, status file, and report
  into a subfolder named after its id, so that nothing is overwritten. The loop's
  round files stay where they are. The status file lists the ids of the loop runs the
  task started, so the board reads each task's review from its own runs only (4.5).
- **Base:** the branch checked out in the main folder when `task new` runs (decision
  D3). The user chooses it as any branch is chosen, with `git switch`, before giving
  tasks; every merge lands in the main folder, so the base has to be checked out
  there anyway. `task new` reads it with `git symbolic-ref HEAD`, shows it with its
  commit in the start approval, such as `base: dev at a1b2c3d`, and records it for
  the task. There is no `--base` option and no lookup in `AGENTS.md`.
  - **`dev`**, the usual base, needs no extra question.
  - **`main` and `master`** are for production, which gets only what the user
    promotes from `dev`. `task new` first asks the user to confirm that the task
    really goes there, and the task's merge question names the branch again; such a
    task never merges on its own (4.7, step 2). It also offers `dev` instead: when
    `dev` exists and the main folder has no uncommitted change, it switches the main
    folder there with `git switch dev` on the user's word; otherwise it stops, so that
    the user switches. Promoting `dev` to `main` stays the user's own step, which no
    task command takes.
  - **Any other branch** is the base as it is, shown in the start approval. In a
    repository without `dev`, that is the branch checked out, `main` after the
    confirmation, unless the user creates `dev` first.
  - **No branch checked out,** because `HEAD` is detached or a rebase is in progress
    there: `task new` refuses and asks the user to check one out.
  - **Open tasks on another base:** a task keeps the base it started with. When the
    user switched the main folder to another branch since, `task new` says so before
    it starts a task on the new one, and the earlier tasks' merges wait until the
    main folder is back on their base; the board says so.

  A branch name is always resolved as `refs/heads/<name>`, so a tag of the same name
  never wins (prototype). When the base's `AGENTS.md` forbids merging into it, or says
  that changes reach it only through pull requests, the task still runs, and approval
  5 offers only to keep the reviewed branch; the start approval says so.
- **The main folder** stays on the base while tasks run, because every merge lands
  there. The user can keep using the control session for questions and small edits,
  but a merge refuses to overwrite uncommitted changes in the main folder (4.7), and
  the board says so.

### 4.2 Who does what

**The control session** runs `/codex-review-loop:task`, which only the user can start
(`disable-model-invocation: true`):

- `new "<request>" [--name <slug>] [--from <file>] [--rounds N]
  [--tests-first auto|on|off] [--permission-mode <mode>]`: reads the request, or one
  item of a file as the prototype's `--from` does; asks about anything that would
  change the result; drafts the acceptance criteria; and shows the slug, the base
  (4.1), folder, criteria, the dependency install command it expects, the permission
  mode the task session will run in, whether tests come first, and how the task
  merges: `merge: automatic when clean`, which the user can switch to `ask me`, or
  `ask me` alone when the base is `main` or `master` (4.7, step 2). A base of `main`
  or `master` is confirmed before this approval (4.1). On the user's OK it first
  writes the task's line in `tasks.md` with the
  phase `starting`, and the approved task file in the main folder's log folder under
  the task's id, so that the board knows of the task, and a resume or a cancellation
  has its approved request, criteria, and install command, before anything exists on
  disk. Then it creates the folder and branch and claims the task's log folder.
  Before it copies anything, it writes the list of the files it will copy, the
  gitignored files that the main folder's `.worktreeinclude` lists, to
  `copied-files.txt` there; then it copies them, writes the task file and the status
  file, and starts the task session. The prototype copies a file before it lists it,
  and skips a destination that already exists without listing it (`cmd_copy_local`
  in its `worktree.sh`), so a copy cut short there can leave a copied file unlisted,
  which the check of rule 8 would then miss. Here a copy cut short leaves every
  planned file listed, copied or not, and a resume lists every destination that
  already exists as copied. When a step
  fails, the line stays at `starting`, and `task new` for the same slug then shows
  what exists and offers to continue from there, or to give the task up with
  `task abandon`.

  The permission mode is one of `manual`, `acceptEdits`, and `auto`, three of the
  choices that `claude --help` lists in Claude Code 2.1.331: `--permission-mode` when
  given, else the one the user picks in the start approval, where `auto`, the
  built-in default of a new terminal session (permission-modes page), is offered
  first (decision D12). In `acceptEdits` or `manual`, a task asks at nearly every
  command outside its edits, so it rarely reaches an automatic merge. The task
  session is started with the mode passed as `--permission-mode`,
  which takes precedence over `permissions.defaultMode` in any settings file, so a
  configured default such as `bypassPermissions` never applies to a task session.
  `task new` refuses the other three choices before it creates anything: `dontAsk`,
  which denies anything that would ask, `AskUserQuestion` included, so the task could
  not ask for its merge; `plan`, in which the task cannot edit; and
  `bypassPermissions`, for a session nobody watches.
- `status`, also when no argument is given: the board (4.5).
- `clean [<slug>...]`: retires each merged or kept task, after one OK for the list: it
  deletes the task's session and moves its folder aside, deleting nothing else
  (4.7, step 8). It also offers to purge the tasks retired more than seven days ago.
  It does not touch a task that is neither merged nor kept.
- `abandon <slug>`: the one way to give up a task that is not merged. After an
  explicit OK, it retires the task as `clean` retires a merged one: its session is
  deleted, and its folder and branch, with every commit and change, move aside,
  deleting nothing else. Like `stop`, it waits for the task session to pause at a step
  boundary first (4.7, rule 9).

  During a rebase stopped at a conflict, `abandon` retires the folder as it is
  (decision D15): the rebase stays stopped, and the conflict, the resolution so far,
  and every other file move aside with the folder, untouched. No task command aborts
  a rebase once the resolution of its conflict has started, because
  `git rebase --abort` does more than undo the conflict. Observed with git 2.56: it
  exited 0 after returning a file the user had edited outside the conflict to its
  version before the rebase, after replacing an ignored file at a path the task's tip
  tracks with that tip's version, and after deleting an ignored only copy inside a
  folder where the task's tip tracks a file; an untracked file that is not ignored,
  at such a path, made it refuse, exit 128, with the rebase still in progress. It
  resets the working tree hard (`ACTION_ABORT` in `builtin/rebase.c` at the tag
  `v2.56.0` uses `RESET_WORKING_TREE_HARD`), so it can also discard an edit git hides
  (rule 6). A rebase left stopped loses none of that. Also observed with git 2.56, on
  2026-11-25:
  - `git worktree move` and `git worktree lock` succeed while a rebase is stopped at
    a conflict, and the moved folder still shows the rebase, the partly resolved file,
    and an edit outside the conflict;
  - while the rebase is stopped, the task's branch still points at the task's commit,
    `HEAD` is detached, and `git worktree list --porcelain` shows that worktree as
    `detached`, not on the branch; the rebase's own state names the branch;
  - git refuses to delete the branch while that rebase is in progress, with
    `cannot delete branch ... used by worktree`;
  - `git worktree remove --force` removes such a folder, after which the branch can
    be deleted.

  These runs were on Windows; phase 1's tests repeat them on Linux and macOS.
  Retiring identifies such a folder by the rebase in progress (4.7, rule 1), the board
  shows it as retired during a conflict, and its purge lists the stopped rebase and
  the resolution so far with the folder's other changes (4.7, step 8). To drop the
  resolution and keep the task instead, the user runs `git rebase --abort` (4.7,
  step 5). A task that never got a folder or a branch, because `task new` stopped
  first, is cancelled by marking its line in `tasks.md`, after `abandon` has shown the
  request it held.
- `purge [<id>...]`: deletes retired folders and their branches: only what the user
  approves by name, and only when it is still as it was listed (4.7, step 8).
- `stop <slug>`: stops a task's session and keeps everything, to resume later. It
  waits for the session to pause at a step boundary first, so that no git step is
  cut in half (4.7, rule 9).

Every subcommand that reads `tasks.md` first checks that the main folder's log folder
belongs to this repository (4.4). Before it stops or deletes a session, it looks the
session up with `claude agents --json --all`, which also lists background sessions
that finished, and matches both the recorded session id and the task's recorded
folder, so that it never acts on a session of another repository. A session that has
already stopped is not stopped again, and a session missing from the list is
reported as missing, never taken for another.

**The task session** runs `/codex-review-loop:task-run`, its first prompt, also
user-invoked only. It reads the task's status file first, compares it with the
repository (4.8), and continues from there, so a restarted session resumes where it
stopped. It installs the dependencies, runs the baseline checks, writes the tests
first when they help, implements, runs the checks, runs the loop, writes the report,
asks for the merge unless the task merges on its own (4.7, step 2), commits,
rebases, merges, and then waits for the control session to clean up. It installs with the
command the user approved in `task new`, and asks before any other (4.7, step 5). It
edits only its task folder and its log folder;
it changes the main folder only through the guarded merge (4.7), apart from a lasting
permission answer of the user's, which Claude Code itself saves there (4.3). The task file exists
before the session starts, with the criteria the user approved in `task new`, so the
session does not write a new one, as the global rule for a new task would have it: it
adds its decisions and fills in the handoff.

**Tests first** (decision D7), as the prototype's start skill and its `test-author`
agent do them at `3a7a44b`. With `--tests-first auto`, the default, they come first
for a bug fix and for criteria that describe behavior a test can check, and not for a
change of documentation, configuration, or UI styling alone, or exploratory work
whose interface is not known yet; `on` and `off` force the choice, and the start
approval shows it. Then:

1. The task session writes only the interface: types, signatures, and stubs that
   throw "not implemented". A bug fix has none.
2. The `test-author` agent, a new agent of this plugin taken from the prototype,
   writes tests from the task file and that interface, at least one per criterion,
   plus the edge cases each implies; for a bug fix, a test that reproduces the bug. It
   creates and edits test files only, and gets no idea of the implementation. The
   task session records the other changed files before and compares them after, and
   stops when the agent changed one.
3. Each new test must fail, on an assertion or on the stub's error. A bug fix's test
   that already passes does not reproduce the bug, and goes back to the agent.
4. The tests are locked: `worktree.sh hash` records their hashes in the task's log
   folder. A locked test changes only when it misread the request, after a decision
   that quotes the criterion and gives the reason, and never to get a passing run.
   Before every review round the task session compares the hashes again, and passes
   the changed locked tests to the loop with `--focus`, so that the reviewer checks
   that each change is justified and that the test still proves what it proved; an
   unjustified or weakening change is a P1, as in the prototype. A task whose locked
   test changed never merges on its own (4.7, step 2).

The prototype's README gives the reason: tests written after the code tend to confirm
what the code does, bugs included, and agents sometimes edit a failing test instead
of fixing the code. With automatic merges, tests written first and locked are the
main guard between a wrong change and the base.

**How the task session starts.** `task new` runs this with the task folder as the
working directory:

```bash
claude --bg --name "<repo>/<slug>" --permission-mode <mode> "/codex-review-loop:task-run"
```

with the mode chosen in `task new`. Facts behind it, from Claude Code's pages read on
2026-11-24:

- In a worktree, Claude Code keys workspace trust on the main checkout's root
  (permissions page). A task folder of a repository the user has trusted therefore
  passes the trust check that `claude --bg` makes; from a script, an untrusted folder
  fails with `Workspace not trusted`.
- A background session that starts inside a linked worktree, "whether Claude created
  it under `.claude/worktrees/` or you created it with `git worktree add` somewhere
  else", is not moved into a worktree of its own (agent view page). Claude Code's
  isolation checks, which block git commands aimed at the main checkout, apply to a
  session started with `--worktree` or moved with `EnterWorktree` (worktrees page),
  so not to a task session. Such a session "still asks before committing or
  switching branches".
- Without the flag, the session would start in the mode a new session in that folder
  gets, which a settings file can set (agent view page); the flag comes first in the
  order that decides it (permission-modes page, "Which mode a session starts in").
  When `auto` is not available to a session, Claude Code starts it in Manual mode
  instead (same page).
- **Unverified, spike S1:** starting `claude --bg` from the Bash tool of another
  session. Claude Code sets `CLAUDE_CODE_CHILD_SESSION` in the processes it starts,
  and an interactive session that inherits it saves no transcript; the errors page
  names `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` to keep them. Whether this applies to
  a background session, and whether the first prompt runs the plugin's skill, is what
  S1 checks.

**No second way to start.** The first release has no one-terminal fallback
(decision D1). Background sessions are not available where the `disableAgentView`
setting or managed settings turn agent view off, and how `claude --bg` behaves there
is not verified. So `task new` goes on only when `claude agents --json` lists the
session it started, in the task folder and under the task's name (spike S1);
otherwise it shows what Claude Code printed and stops with the task at `starting`, as
for any failed step. The review loop works there as before. Option B of section 2, one
interactive terminal per task, becomes the design only if spike S1 or S2 fails, and
the plan is then rewritten before any code.

### 4.3 Approvals, and what runs between them

| # | When | What the user approves or answers | Where | What then runs without asking |
|---|---|---|---|---|
| 1 | `task new` | The criteria, slug, base, folder, expected install command, permission mode, whether tests come first, and how the task merges: automatically when it ends clean, or after the user's OK, in one OK. A base of `main` or `master` is confirmed first, and always merges after the user's OK (4.1) | Control session | Folder, branch, listed local files, task and status files, the task session's start |
| 2 | A command the user's permission settings do not allow, such as the first install | Claude Code's permission prompt | Task session, attached: `→` in agent view, or `claude attach` | Install, baseline checks |
| 3 | A choice the request leaves open | A question asked with `AskUserQuestion` | Task session | Implementation and checks |
| 4 | The loop escalates a finding, or one is disputed twice | The user decides the finding | Task session | The review rounds with their fixes |
| 5 | Checks and review done, unless the task merges on its own (4.7, step 2) | "Commit and merge into `<base>`?", with the report. When the base moved since the task's accepted base, the question says so, such as `dev +1`, because the merge rebases first. The question says that the merge is local and that no CI has run on its result, and it offers a second ending: keep the reviewed branch, committed but not merged, for the user to push and merge through the repository's own process, such as a pull request whose CI decides. When the repository's `AGENTS.md` says that changes reach the base only through pull requests, or forbids merging into it, that ending is the only one offered, with the reason (4.1). A task ended this way is `kept` (4.5): `task clean` retires it like a merged one, and its purge removes the folder and keeps the branch unless the user names the branch for deletion | Task session | One commit, rebase, checks again, review again when needed, then the fast-forward merge, or for a kept branch nothing more. A finding of that second review, or a failed check, asks again |
| 6 | A fix after the commit: a hook changed the content, or a review after the rebase needs a code change | A second commit | Task session | Its checks and review, then row 5's steps |
| 7 | The rebase conflicts, or would replace an ignored file | Resolve the conflict, or decide about the file, in the task session; or give the task up with `task abandon`, which retires the folder with the conflict as it is (decision D15) | Task session | The resolution (4.7, step 5), then the checks, the review, and approval 5 again |
| 8 | `task clean` | Retiring the folders of merged tasks: moving them aside, deleting nothing of the tasks'. Deleting each task's session also removes that session's scratch folder; its transcript stays | Control session | Deleting their sessions, moving their folders |
| 9 | `task abandon` | Retiring a task that is not merged: its folder and branch move aside with every commit and change. Deleting its session also removes the session's scratch folder; its transcript stays | Control session | Deleting its session, moving its folder |
| 10 | `task purge`, or its offer in `task clean` for tasks retired more than seven days ago | Deleting retired folders and branches, with everything git cannot restore listed by name: untracked, ignored, and hidden files, and for an abandoned task its commits not on the base and its uncommitted changes | Control session | Deleting what was approved, if it is still as listed, and nothing else |

Rows 1, 8, and 10 come with every task, from its start to the purge of its folder, and
row 5 with every task that does not merge on its own (4.7, step 2). Rows 2, 3, 4, 6,
and 7 appear only when something needs the user, and row 9 only when the user gives a
task up. Row 2 depends
on the user's permission mode and rules: a mode that allows the commands removes most
of those prompts, and that choice stays the user's. Every stop in 4.7 and 4.8 also
asks the user in the task session, for example when the base moved backwards or a
commit holds a copied file.

The task session asks rows 3 to 7 with `AskUserQuestion`. Agent view then lists the
session under needs input, its row shows the question, the terminal is notified, and
the peek panel answers it. A permission prompt, row 2, shows the same way, but a reply
in the peek panel does not answer it: the user attaches to the session to answer it
(agent view page, "Peek and reply"). The board's next-step line says which of the two
a task needs.

What a permission answer covers depends on the prompt (permissions page, read
2026-11-24). Some prompts offer only a one-time answer. An approval of a file edit
lasts until the session ends and is not saved. "Yes, and don't ask again" for a Bash
command or a web domain saves a rule in `.claude/settings.local.json` at the root of
the repository, which Claude Code resolves through a worktree to the main checkout,
so the rule applies to the main folder and to every other worktree of the repository
and outlives the task. On Windows, outside a git repository, and in the other cases
the settings page lists, Claude Code saves that rule elsewhere, such as with the
worktree (worktrees page, "What worktrees share with the main checkout"). The board
cannot see what a permission prompt asks: `claude agents --json` reports only that
the session waits on one (`waitingFor`: `permission prompt`), and the waiting
session cannot write to its status file. So the board's next-step line says
"permission requested: attach to see it", and adds that a lasting answer to a command
or a web domain can apply to the whole repository, so that the one-time answer fits
an approval meant for this task only.

A question written as plain text ends the turn, and agent view then shows the row as
completed. So the task session asks in plain text only when `AskUserQuestion` is
denied, for example by a permission rule: it first records in its status file what it
waits for, then asks and ends its turn. The board shows that the task waits for the
user, and a reply in the peek panel continues it.

Row 5 is the authorization that the user's global rules require before a commit and
a merge. The answer is copied into the task file's decisions, marked `[user, <date>]`
with the user's words. Rejected findings and P3 items are listed in that question, so
the OK covers them knowingly. A task that merges on its own skips row 5 (decision
D5): its authorization is the user's OK in row 1, which showed
`merge: automatic when clean`, and the task session copies that line into the task
file's decisions in the same way. It merges on its own only under every condition of
4.7, step 2, and a task with a rejected finding or a P3 item never does, so row 5
still covers those knowingly. If the user's own global rules make the task session
ask anyway, the merge waits for the user's answer, which is the safe direction; the
guide shows how to state in `~/.claude/CLAUDE.md` that the start approval authorizes
one commit on the task branch and the fast-forward, never a push, as the prototype's
README does for its `--auto`.

### 4.4 Where the record lives

For each task, in the loop's log folder for the task folder,
`~/.claude/codex-reviews/<repo>-<slug>/`:

| File | Written by | Contents |
|---|---|---|
| `task.md` | `task new`, then the task session | The loop's task file: the request verbatim, acceptance criteria, out of scope, decisions, handoff. One more line names the task folder, as in the prototype. |
| `status.md` | Both sessions, through one script | The task's current state (4.5) and a timeline of its phases. Each write replaces the file in one step: a temporary file, then a rename. |
| The loop's files | The loop, as today | Per round: prompt, Codex's review, Codex's log, triage. Per run: the archived task file and `<run>-summary.json`. |
| `report.md` | The task session | The final report, in the shape of the prototype's report template: criteria and results, how the change works, files, tests, checks, review rounds, items for the user, the commit, and, when the task merged on its own, each condition of 4.7, step 2 with its result. |
| `locked-tests.txt` | The task session | When tests came first, the hashes of the locked tests, as the prototype keeps them (4.2). |

For the repository, in the main folder's log folder `~/.claude/codex-reviews/<repo>/`:
`tasks.md`, one line for every task created: id, slug, folder, branch, base, log
folder, and, once the slug is used again, where the task's archived status file and
report are. Only `task new`, `task clean`, `task abandon`, and `task purge` write it,
each under the lock of 4.7, rule 9. The board reads it to list tasks whose folders
are retired or gone. That log folder is named after the main folder's name alone, so
before any `task` subcommand reads or writes `tasks.md`, it runs the loop's
`log-dir.sh` in the main folder. The script claims the folder for this repository, or
stops when another repository with the same folder name owns it, and then the
command stops too, before it reads a line or acts on one.

Retired task folders wait for their purge in `../<repo>.retired/`, beside the main
folder (4.7, step 8). They hold the task's files only; its record stays in the log
folders above.

Why not a file inside the task folder, as the request suggested: a file there belongs
to the uncommitted change, so the loop would review it, every status update would
change the fingerprint that the loop compares before and after a review, and the
commit would take it in unless it were ignored. It would also disappear with the
folder after the merge. The loop's rule that logs live outside the repository applies
here too.

### 4.5 What the user sees

**Phases**, one at a time in the status file's `phase:` line: `starting`, `setting up`,
`implementing`, `checking`, `reviewing`, `waiting for you`, `ready to merge`,
`merging`, `merged`, `kept`, `paused`, `stopped`, `retired`, and `purged`. Beside
`retired` and `purged`, the status file records how the task ended: `merged`, `kept`
(a reviewed branch left for the user's pull request, approval 5), `abandoned`, or
`already in the base` (4.7, step 6). The board shows a retired folder's size and
age.

**The status file** starts with one `key: value` line per field, so both a person and a
script can read it, and ends with the timeline. Fields: task id, task, title, main
folder, folder, branch, base and its commit at the start, accepted base, session id,
short id, and name, phase, detail, waiting for (`nothing`, `question`, `decision`,
`merge approval`, `conflict`, `main folder on <base>`), next step, the merge setting
(`automatic when clean` or `ask me`), tests first (on or off, with the reason), the
ids of the task's review runs, the rounds spent across them and the task's round
limit, verdict, open P0-P2 findings, P3 items, rejected or overridden findings,
checks, the result of each condition of an automatic merge (4.7, step 2), the
approved install command, the approved tree (4.7, step 1), commit, commit to merge,
the git step in progress with the state it expects before and after (4.8), merged
commit, whether it merged on its own or after approval 5, and the time of the last
update. A session waiting on a permission prompt cannot write while it
waits, so the board learns of that wait from `claude agents --json`, not from this
file.

**The board**, from `/codex-review-loop:task status`:

```text
Tasks of <repo>, base dev                                                         14:05
Task         Phase            Review              Session       Waits for        Changes
csv-export   ready to merge   3 rounds, verified  done          merge approval   6 files, dev +1
fix-login    reviewing        round 2 of 7        working       nothing          3 files
dark-mode    waiting for you  not started         needs input   permission       none yet
Next:
  csv-export  answer its merge question: peek in agent view, or claude attach 7c5dcf5d
  dark-mode   permission requested: attach to see it, with → in agent view, or claude attach 3b91e2a0
Done: 2 merged, last rename-api automatically at 11:20 as a1b2c3d. 0 abandoned.
```

`dev +1` says that the base gained one commit since the task's accepted base, so its
merge will rebase first, with a second review before it merges on its own, or, when
the user approves the merge, when the base changed a file the task changes (4.7,
step 4). A task whose merge waits because the main folder is on another branch says
`main folder on dev` (4.1), and a folder retired during a conflict reads
`retired during a conflict` (4.2, `abandon`). The commands name a session by
the short id its status file records, not by its name: `claude attach` also takes
part of a name, so one task's name could select another, and a name works only
while the session's process runs (agent view page). The name stays as the label.

It combines five sources, read each time it runs:

1. the status files and `tasks.md`;
2. the review's progress, from the runs that the task's status file lists as its
   own, never from other runs in the same log folder: the newest of them, its highest
   round with a prompt, and its rounds with a review; and the verdict from
   `<run>-summary.json` once the run has ended. A task with no run shows
   `not started`. A finished task shows the verdict its own status file recorded,
   also after its files were archived because its slug was used again;
3. `git worktree list --porcelain`: whether each folder still exists, and on which
   branch;
4. git, for each task folder: the files that differ from the base, counting the
   branch's commits, the staged and unstaged changes, and the untracked files that
   are not ignored, each file once, so that a task shows its work before its first
   commit, which comes only at approval 5; and how many commits the base gained since
   the task's accepted base (4.7, rule 3);
5. `claude agents --json --all`: each session's `state`, `status`, and `waitingFor`.

These are the fields the survey found in the tools that track parallel tasks well:
the state, what a task waits for, its last activity, the size of its change, how far
it is behind the base, and whether it is ready to merge. Agent view adds the question a
session waits on and how long it has waited.

When they disagree, the board says so. For example, a status file that says
`reviewing` beside a session that `failed` reads "session ended: reply 'continue' to
it in agent view, or run `claude attach <short id>` and ask it to continue", because
a restart alone does not pick the work back up (4.8). Agent view lists the same tasks
under the same names,
`<repo>/<slug>`, so the two views match.

A script prints the facts as `key=value` lines and the skill turns them into the
table, so the board's facts are tested and only its layout is written by Claude.

### 4.6 The Codex review in a task folder

- In a task session the loop runs as it does today. Its repository root is the task
  folder, so its log folder is `~/.claude/codex-reviews/<repo>-<slug>/`, its task file
  is that folder's `task.md`, and its scope is the task folder's changes. Each task's
  review therefore gets its own prompt, scope, task file, and output files, and is
  judged against its own request. That is separation of inputs, not of what the
  reviewer can read: the read-only sandbox blocks writing, not reading, as the guide's
  known limits say for every review, so a reviewer could still read a sibling task
  folder or another log folder if it chose to.
- The loop changes in one place. A task folder can hold copies of the user's local
  files, and a fix made between two rounds, such as one to an ignore rule, can bring a
  copy into what the next round reads in full. So before every Codex run, each round
  and each rebuttal, the loop reads `copied-files.txt` in its log folder when that
  file exists, as `task new` writes it in a task's log folder, and stops when one of
  the paths it lists is in the index, among the untracked files `git status` shows,
  or, in branch mode, in any commit of the range the review reads, `<base>..HEAD`,
  whose diff the review's prompt asks for. Without that file the loop runs as before.
- `log-dir.sh` already stops when another repository owns a log folder. `task new`
  checks the same marker before it creates anything (4.1).
- **Rounds.** The user's rule limits review rounds per task, and `--rounds` limits one
  run of the loop. A task can run the loop more than once: after the gate's extra
  round, after a hook changed its commit, after a rebase. So the status file counts
  the rounds the task has spent, across all its runs, and each run gets
  `--rounds <rounds left>`. When none are left, the task session asks the user before
  any further review, and stops when the user says no. The limit is the user's own
  rule, or `--rounds` when `task new` was given one. No other option is passed unless
  the user gave it, apart from the note on locked tests, which tests first adds to the
  `--focus` of every run (4.2).
- **Trust.** Codex treats a linked worktree of a trusted repository as trusted: its
  `resolve_root_git_project_for_trust` follows the worktree's `.git` file back to the
  main repository (source of Codex 0.171.0, `codex-rs/git-utils/src/trust.rs`), and
  OpenAI's configuration reference says that `trust_level` marks "a project or
  worktree as trusted or untrusted". A reading of the source of 0.172.0, not run, says
  a trusted worktree's own `.codex/config.toml` is read, so a `review_model` set there
  applies; spike S3 confirms it. A worktree moved by hand still finds the repository
  through its `.git` file, which holds an absolute path by default, but the
  repository's record of it still names the old path: the git-worktree manual says
  the main worktree then cannot find it, and Codex 0.171.0 checks that record too,
  so it does not apply the main repository's trust to the moved folder
  (`resolve_root_git_project_for_trust` in `codex-rs/git-utils/src/trust.rs`
  compares the recorded folder with the current one). `git worktree repair` fixes
  both, and a task folder is never moved by hand while its task runs. Retiring moves a folder with `git worktree move`, which updates
  the link, as the git-worktree manual says of that command.
- **The reviewer reads the main repository's `.git`.** A task folder's git data lives
  in the main folder's `.git/worktrees/<name>`. The loop's guide recorded on
  2026-11-12 that the read-only sandbox grants read access from the root of the file
  system. On Windows, a reading of Codex's source says this depends on the sandbox
  mode, and that the elevated mode grants a repository under the user's profile
  folder; spike S3 checks it.
- **Reviews at the same time.** Each Codex run writes its own session file, and the
  state databases in the Codex home are shared. Open issues in Codex's repository,
  read on 2026-11-24, report trouble when runs overlap: rows lost when concurrent
  first runs share a fresh Codex home (#42447); Windows sandbox instances racing to
  write one file (#33741); sandboxed commands that hang in one worktree on Windows
  with 0.172.0 (#63631); and HTTP 429 or "reached concurrency limit" errors with about
  three sessions at once (#43402, #54010, #54017). Spike S5 runs two reviews at once
  on Windows. The loop already stops a round whose Codex run exits with an error, and
  the task then waits for the user. If S5 shows that two reviews at once interfere,
  the plan adds a queue for Codex reviews before any code: a shared lock, like the
  merge lock, that lets only as many reviews run at once as S5 found to work, while
  the tasks' other steps go on, and the board shows a task that waits for its turn
  (decision D8).
- **Cost.** Each Codex review is one run that counts toward the user's ChatGPT
  allowance: OpenAI's pricing page says that "local messages and cloud chats share
  your plan's usage allowance" and that reviews run locally count toward the general
  usage limits. A task spends one review run per round, plus at most one rebuttal in
  a round where Claude rejects a finding that Codex labeled P0 or P1 (the loop's
  step 6), plus the extra round the gate can add and the review after a rebase, which
  every automatic merge after a rebase onto a moved base needs (4.7, step 4).
  These are counts of runs, not of usage: the same page says that what a message
  uses depends on the model and on the size and complexity of the task, and calls
  its message counts estimates (read 2026-11-24). Task sessions review at the same
  time, so three tasks in review use the allowance roughly three times as fast as
  one, for reviews of similar size, as an illustration and not a rate. The Claude
  side is alike: agent view's page says ten background sessions use quota "roughly
  ten times as fast" as one.

### 4.7 Commit, update, merge, clean up

The steps follow the prototype, which tests each git step, with the changes this
section names. First the rules every git step keeps, then the steps.

**Rules every git step keeps.** Each rule is a test in phase 1.

1. **Identity.** A step acts only on the task folder recorded in the status file, a
   linked worktree of this repository, on the branch `task/<slug>`, which it reads
   with `git symbolic-ref HEAD`: the loop's fingerprint records the commit and the
   files, not the branch. While a rebase is stopped at a conflict, git has detached
   `HEAD`, so `resolve-continue`, and `retire` and `purge` of a task given up during
   the conflict (4.2, `abandon`), check the rebase in progress instead, the branch it
   started from and the commit it rebases onto, which git keeps in the rebase's
   state, against the status file. After `resolve-continue` ends, and after the user's
   own `git rebase --abort` (step 5), the branch is checked again.
2. **Exact commits.** The task's branch holds only commits the task made. Before each
   review and at the gate, its tip must be the commit the task started from or the
   task's last recorded commit: a commit that anyone else made there stops the task
   and asks the user, because a review of uncommitted changes would not see it.
   `commit`, `rebase`, and `merge` each take the commit they expect to start from and
   refuse when the branch points anywhere else. After a rebase, the task's new tip is
   recorded before the checks run, and the checks, any review, and the merge use that
   tip.
3. **The base moves only forward.** Each time a step reads the base's tip, the tip
   must descend from the last base the task accepted: the commit it started from, or
   the base of its last rebase. A base that moved any other way, such as one the user
   reset to an older commit, stops the task and asks the user, so that no merge brings
   back commits the user removed.
4. **A rebase writes over nothing git does not track.** Git treats ignored files as
   expendable. Observed on 2026-11-24 with git 2.56: a rebase replaced an ignored file
   at a path the base had started to track, and exited 0. So before a rebase or
   `resolve-start`, the script lists the paths the rebase will write: every path
   tracked in the base's tip or in a commit it replays, and not tracked in the task's
   tip. It stops when one of them, or a folder above or below one of them, is an
   untracked or ignored file or folder in the task folder. That covers a base that
   starts to track a path, and a task that stops tracking one, since a rebase first
   checks out the base's tip, where the path is still tracked.
5. **Nothing is deleted at cleanup.** Cleanup moves a task's folder aside, whole. Only
   a purge deletes anything: the whole retired folder, after the user has seen
   everything in it that git cannot restore, has confirmed that no program still
   writes there, and the folder is still as it was listed (step 8). Git would
   otherwise delete without asking. Observed the same day: `git worktree remove`
   deleted an ignored file that was the only copy, and an edit to a file marked
   `assume-unchanged`, both with exit code 0.
6. **Edits git hides.** Git's status does not show an edit to a tracked file marked
   `assume-unchanged` or `skip-worktree`. `commit` refuses while such a file differs
   from its version in the index, because `git add -A` would leave the edit out of a
   commit whose checks ran with it. A purge lists such files among what it would
   delete.
7. **The approved tree is the committed tree.** When the gate passes, the task
   session records, besides the folder's fingerprint, the tree object of the approved
   state, which git computes from a temporary copy of the index with `git add -A` and
   `git write-tree`, leaving the real index alone. `commit` compares the tree it
   staged, and then the tree it committed, with that object. An edit saved after the
   gate makes the staged tree differ and sends the change back to the gate; a hook's
   change makes the committed tree differ, goes through the review of step 4, and
   asks approval 5 again, unless the task merges on its own and that review is clean
   (step 3).
8. **Copied files go no further.** The list of copied local files is checked against
   the index and the untracked files a review reads in full before every Codex run,
   by the loop itself, each round and each rebuttal (4.6), and against the committed
   tree after every commit, by `commit`. A copied file in any of them stops the task
   at once and asks the user, before a review would send it to Codex or a merge
   would take it into the base. A commit that holds a copied file, as one that a hook
   changed can, stays out of every review and every merge even after a later commit
   deletes the file, because the file would stay in the history a merge brings into
   the base: the loop's check covers every commit of a branch-mode review's range,
   and `merge` refuses a range in which any commit holds one. Such a task stays
   stopped; `task abandon` ends it, and its purge lists that commit, unless the user
   rebuilds the branch by hand.
9. **One writer at a time.** One task session runs a task. It takes the task's runner
   claim before it does anything: a folder in the task's log folder, created in one
   step, that holds its session id. A second session that finds the claim held stops
   at once, unless `claude agents --json --all` shows that the holder has ended. When
   that listing is unavailable, or does not show the holder, the second session never
   takes the claim over on its own: it asks the user
   to confirm that the first session has ended. It takes over only after that, and
   after the checks of 4.8. `task new`
   records a launch before it starts the session and the session's id after, and
   looks for a live session in the task folder before it launches another. Merges into
   the main folder hold the repository's merge lock (step 7). Changes to `tasks.md`
   hold a lock in the main folder's log folder, so that two control sessions starting
   tasks at the same moment cannot lose a line. A status file has one writer at a
   time: `task new` before the task session starts, the task session while it runs,
   and the control session's `clean`, `abandon`, and `purge` after the session was
   deleted.

   The control session never stops or deletes a task session in the middle of a git
   step. `task stop` and `task abandon` first write a pause request in the task's log
   folder. The task session looks for it at every step boundary, between git steps
   and between review rounds, and records `paused` in its status file. The control
   session goes on once the session has paused, or waits on the user with no git
   step open in its journal (4.8) and the merge lock not held by it; it tells the user
   when that takes more than a few minutes, and does nothing meanwhile. Then it reads
   the journal and the branches again: a task that merged in the meantime is offered
   to `task clean`, not abandoned.

   A task whose session has already ended, because `task stop` stopped it, or it
   failed, has no one left to pause. When `claude agents --json --all` shows that,
   the control session does not wait: it checks the repository itself, as a restart
   does (4.8): the journal, the branches, whether a rebase or a merge is in progress,
   and who holds the merge lock. It goes on only when no git step is open. When the
   listing cannot tell whether the session ended, it asks the user, as for a runner
   claim.

**The steps.**

1. **Gate.** The checks pass on the final tree, and the loop's final verdict is
   `verified` or `clean with unverified items`. `fixes not re-reviewed` offers one more
   round first. `open findings` and `review failed` stop the task and ask the user.

   The gate also compares the folder's fingerprint with the one the loop's last
   completed round ended with, which `<run>-summary.json` records. When they differ,
   something changed after the last review: the loop's own fixes, rows it wrote in
   `docs/reviews/decisions.md`, or an edit from elsewhere. The task session then runs
   one more round, within the rounds the task has left (4.6); when none is left, it
   stops and asks the user, and says that the final tree was not reviewed.

   A row written in the last round is the usual case. The loop asks the reviewer to
   check each new row once. It finds new rows by comparing with `HEAD` in the default
   mode and with the merge base in branch mode, so a later round of either mode checks
   a row while the task is not merged; once the task merges, the row is part of the
   base, and no later review checks it.

   When the gate passes, and the branch's tip is still as rule 2 requires, the task
   session records the approved tree: the folder, the branch, that fingerprint, which
   is the reviewed tree, and its tree object (rule 7).
2. **Merge on its own, or ask** (decision D5). The task merges without asking only
   when its start approval said `merge: automatic when clean` and every condition
   below holds. The task session checks them when the gate passes, and again right
   before the merge against the latest review then (step 4), and records the result
   of each in the status file and the report.
   1. **The base is neither `main` nor `master`** (4.1).
   2. **The latest review is clean:** the loop's last round returned no finding at
      all, P0 to P3, and it reviewed the final tree: the gate's comparison of
      fingerprints shows that nothing changed after it.
   3. **No finding was overruled:** no finding of the task, in any round of any run,
      was rejected or overridden. A rejected finding is recorded in
      `docs/reviews/decisions.md` so that it is not raised again, so a clean last
      round does not show that Claude and Codex agreed.
   4. **Nothing needs the user:** nothing waits for an answer, and the report lists
      no open question, no assumption about what the user meant, and no suggestion or
      follow-up. The task session also reads the latest review's whole text: a
      suggestion or a question anywhere in it counts, labeled or not. When it is
      unsure, it asks.
   5. **No gap:** the verdict is `verified`, the reviewer confirmed every acceptance
      criterion in the last round, and the change stayed within the request.
   6. **The checks pass** on the commit that would be merged.
   7. **No locked test changed** (tests first, 4.2).
   8. **No conflict:** a task whose rebase conflicted asks, because the user has not
      seen the resolved result (step 5).

   A question the user answered during the task does not block an automatic merge,
   nor do the decisions the task session recorded while implementing, which the
   reviewer checks against the request. With every condition met, the task commits,
   rebases, and merges as the steps below say, and the board shows that it merged on
   its own, with the time and the commit; a task merged this way is one commit, which
   one `git revert` undoes. Otherwise it asks approval 5, with the verdict, the
   criteria and their results, the files, the checks, the rejected findings with
   their evidence and their rows in `docs/reviews/decisions.md`, the P3 items, the
   conditions of an automatic merge that failed, and `git diff --stat` against the
   base.
3. **Commit.** The folder, the branch, and a new fingerprint must equal the approved
   tree, or the change goes back to step 1. The message follows the repository's
   style. `worktree.sh commit` takes the branch's tip as the commit it expects
   (rule 2), refuses while an edit git hides exists (rule 6), stages everything, and
   compares the staged tree with the approved tree object (rule 7). It runs the
   repository's hooks, never amends, refuses when a copied local file would be
   committed, checks the committed tree for copied files (rule 8), and compares the
   committed tree with the approved one. When a hook changed it, the committed tree is
   not the one the gate approved, so the review of step 4 runs on it. A task that
   merges on its own goes on only when that review is clean (step 2); otherwise the
   task session shows the user the hook's changes and asks approval 5 again for the
   commit as it is, whatever that review found. The task session records the commit.
4. **Review after the commit.** Every review from here on runs the loop in branch mode
   against the base (`--base refs/heads/<base>`): the folder has nothing uncommitted,
   so the default mode would stop with nothing to review. Such a review runs when a
   hook changed the content in step 3, and after a rebase onto a moved base (step 5):
   always when the task is to merge on its own, and otherwise when the base changed a
   file the task changes, or an instruction file: `AGENTS.md`, `AGENTS.override.md`,
   or `CLAUDE.md` in any folder, anything under a `.codex` folder, or
   `docs/reviews/decisions.md`, the files `instruction-changes.sh` lists (decision
   D13). Its verdict must pass the gate of step 1, and a review that fails does not
   pass; before an automatic merge, it must also meet the conditions of step 2. Any
   change it leads to, a fix or a new row in `docs/reviews/decisions.md`, needs a
   second commit (approval 6) and then the gate again. The user's OK in step 2, when
   there was one, covered the change as the user saw it, so a finding of such a
   review, or a failed check, asks the user again before the merge, also for a task
   that was to merge on its own.

   For a merge the user approves, a rebase that brought in only other files gets the
   checks but no new review: the merge question showed how far the base had moved
   when the user answered, such as `dev +1`, and the user is the second look. The
   reviewed tree and the merged commit then differ, and the status file and the report
   record both: the tree the reviewer saw, and the commit that was checked and merged.
   An automatic merge never lands a commit that no review saw.
5. **Update.** `worktree.sh rebase <base>` takes the task's commit from step 3, or
   from a second commit, and the last accepted base (rules 2 and 3). It reads the
   base's tip once, so that its checks and the rebase use the same commit, and stops
   before rebasing when that tip does not descend from the last accepted base
   (rule 3), or when the rebase would write over an untracked or ignored path
   (rule 4); the user then decides (approval 7). It rebases with
   `--reapply-cherry-picks`, so that git drops a commit only when replaying it
   changes nothing, not because a commit with the same patch is in the base's
   history. Observed with git 2.56: after the base had cherry-picked the task's
   change and then reverted it, a plain rebase dropped the task's commit and left the
   change out, while the flag replayed it.

   A conflicting rebase is aborted at once, before anyone has worked in the folder, so
   the abort only returns the folder to the task's commit, and the files are named
   (approval 7). To resolve it, after the user's OK, `worktree.sh resolve-start`
   starts the same rebase again and leaves the conflict in place; the task session
   resolves it in the task folder with the user, then `worktree.sh resolve-continue`
   finishes the rebase (rule 1 says what it checks while `HEAD` is detached). The
   resolved result goes through the checks, the review of step 4, and approval 5
   again, because the user has not seen it; such a task never merges on its own.

   Once the resolution has started, no task command aborts the rebase (decision D15):
   `git rebase --abort` resets the folder hard and discards more than the conflict
   (4.2, `abandon`). To give the task up, `task abandon` retires the folder with the
   rebase still stopped. To drop the resolution and keep the task, the user runs
   `git rebase --abort` in the task folder. Before that, the task session shows
   `git status` there and says what the abort also discards: an edit to a file outside
   the conflict, an ignored file at or below a path the task's tip tracks, and an edit
   git hides (rule 6), so that the user copies what they want first. Afterwards it
   checks that no rebase is in progress and that the branch is at the task's recorded
   tip (rules 1 and 2), and asks the user again: resolve again, keep the reviewed
   branch (approval 5's second ending), or give the task up.

   When the base moved, the task session records the rebased tip at once (rule 2).
   If a lockfile or manifest changed, it reinstalls the dependencies with the install
   command the user approved in `task new`, which the status file records; when the
   repository now asks for another command, such as after a change of package
   manager, it asks the user before running it. Then it reruns the checks, runs the
   review of step 4 when it applies, and records the base the task now sits on as its
   accepted base.
6. **Merge.** The task folder must be clean and on its branch, with the recorded tip.
   `worktree.sh merge` takes that commit and the accepted base. It refuses when the
   task branch points anywhere else (rule 2). It also refuses when the base's tip is
   not the accepted base: a tip that descends from it, as when another task merged
   first, sends the task back to step 5, at most twice, then the task stops; any other
   tip stops the task and asks the user (rule 3). It refuses when the main folder is
   not on the base. The task then waits and says what to do. Right before it starts,
   it also reads the merge policy again from the accepted base's own `AGENTS.md`
   (`git show <accepted base>:AGENTS.md`), because a task merged meanwhile can have
   changed it: when it now forbids a local merge, or sends changes through pull
   requests, the task does not merge and asks the user again, offering only the kept
   branch (approval 5).

   The fast-forward itself is not `git merge --ff-only`, which compares with the base
   as it reads it when it starts, not with the accepted base. A user's own git
   command, in the main folder or in any worktree, since all worktrees share the
   repository's branches, could reset the base between the check and the merge,
   which would then bring back the commits the user removed. So `merge`, run with the
   main folder as its working directory, updates the main folder's files first and
   moves the base last, and only from the accepted base, in four steps:

   1. It checks the main folder, under the merge lock of step 7. No merge,
      cherry-pick, revert, rebase, `git am`, or bisect is in progress there, which git
      marks with files such as `MERGE_HEAD` that `git rev-parse --git-path` locates:
      moving the base would change the parent of a merge the user commits later.
      Observed with git 2.56: with a clean `git merge --no-commit` pending,
      `MERGE_HEAD` was there, no index entry was in conflict, and `git read-tree`
      did not refuse. No index entry is in conflict. No path the change touches has
      a staged or unstaged change there: git keeps such a change in some cases, as
      when the user staged the task's version and then edited the file again
      (git-read-tree manual, two-tree merge, cases 18 and 19, read 2026-11-24), and
      the recovery below could not tell it from what step 2 wrote; the user commits
      it or sets it aside first. No path the change adds, tracked
      in the task's commit and not in the accepted base, nor a folder above or below
      one, is an untracked or ignored file there, which step 2 would replace without
      asking (observed: `git read-tree -m -u` replaced an ignored file in its way and
      exited 0). Then it records the index's entries, `git ls-files --stage`, and
      the content hash of each file the change touches.
   2. It brings the main folder's index and files from the accepted base to the
      task's commit with `git read-tree -m -u <accepted base> <task commit>`, while
      the base still points to the accepted base. Git checks every path before it
      writes a file: a local change it would overwrite stops it with "Entry 'a' not
      uptodate. Cannot merge.", exit 128, and nothing changed (observed). Changes to
      other files stay: a staged one keeps its index entry, an unstaged one its file
      (observed).
   3. Before the base moves, it checks the files themselves: each path the change
      deletes is gone, and each path it adds or changes holds the task's version, as
      git would store it. Git counts a file it could not delete as no error:
      `check_updates` ignores what `unlink_entry` returns (`unpack-trees.c` at the
      tag `v2.56.0`), so a file held open on Windows can stay while the index drops
      it. When a path fails, the merge stops before the base moves, keeps the lock,
      and names the path; once the user has closed what held it, the merge deletes
      it, when its content is still the accepted base's, and checks again. Then it
      moves the base with `git update-ref -m <message> refs/heads/<base>
      <task commit> <accepted base>`, which git does only while the base is exactly
      the accepted base, in one step under git's lock of the branch. Observed with
      git 2.56: with any other value it refused and changed nothing.
   4. It checks the result: the base at the task's commit; for each path the change
      touches, the index entry of the task's commit; and for every other path, the
      entry step 1 recorded, so that staged work of the user counts as kept, not as a
      difference. Observed: after steps 2 and 3, `git status` showed only the user's
      own staged and unstaged changes.

   When the compare-and-swap of step 3 refuses, the base moved during the merge, by a
   command in another worktree or, against the precondition below, in the main
   folder. When the base's new tip holds the task's version of every path the change
   touches, a commit made in the main folder took in the change that step 2 staged:
   the files then already match the base, so the merge leaves them as they are, stops,
   and tells the user, and the task goes back to step 5, whose rebase finds the change
   already in the base (below). Otherwise the merge puts the files back with
   `git read-tree -m -u <task commit> <accepted base>`, which restored exactly the
   index that step 1 recorded, with the user's work, in a run with git 2.56, and it
   stops and asks the user. It never moves the base from any other value.

   Step 2 can also fail after its checks, while it writes files: git writes them one
   at a time and gathers the errors (`check_updates` in `unpack-trees.c` at the tag
   `v2.56.0`), and `git read-tree` then exits 128 without writing the index
   (`builtin/read-tree.c`, same tag). Some files can then be the task's while the
   index and the base are not, as when a file is held open on Windows or the disk is
   full. The merge then puts back, at once and by itself, only what it can tell that
   step 2 wrote (decision D16). It compares each path the change touches, as git
   would store it
   (`git hash-object --path`), with its version in the accepted base and in the
   task's commit. A path at the task's version, or missing where the task deletes it,
   is written back from the index, which still holds the accepted base's version, or
   removed when the task adds it. A path at the accepted base's version stays as it
   is. A path at neither version was written by someone else after step 1, such as
   the user, and is left untouched and named to the user. Step 1 found every path
   the change touches at the accepted base's version and the added paths free, so a
   path at the task's version was written by step 2. It then compares the index and
   those paths with what step 1 recorded; a path left for the user, or a
   path it cannot restore keeps the merge lock and the journal entry, and the user is
   told which.

   The recovery thus writes only over a file that holds the task's version, a copy of
   what the task's commit holds, or at a path where nothing is: nothing that exists
   only in the main folder is overwritten, and phase 1 tests exactly that in each case
   of an interrupted merge. It runs by itself rather than leaving a half-updated main
   folder for the user to repair, because a merge can run while nobody watches (D5),
   and a repair by hand, such as `git checkout .` or `git reset --hard`, can discard
   the user's own work. Showing the files first and waiting for the user would need
   the same comparison of each file, and would leave part of the task's change in the
   main folder, under a dev server or a build, until the user answered.

   It never squashes and never stashes the user's work. Unlike `git merge`, it runs no
   `post-merge` hook of the repository; the report says so.

   The status file records each of the four steps before it runs (4.8). A crash
   between steps 2 and 3 leaves the main folder at the task's commit while the base is
   still at the accepted base: `git status` there shows the task's change as staged,
   and a commit there would include it, not undo it. A restart recognizes that state,
   keeps the merge lock, and asks the user whether to finish step 3 or to put the
   files back as above. A file that a program other than git creates at a path of
   step 1 in the seconds before step 2 is not protected, as for the purge.

   When the rebase left the task's tip at the accepted base, replaying the task's
   commit there changed nothing (observed with git 2.56: with the flag of step 5 and
   the change already in `dev`, the tip ended equal to `dev`). Before it calls the
   change already in the base, the task session compares each path the task's commit
   changed, in the base's tip and in the task's tip from before the rebase, which the
   status file keeps; a path that differs stops the task and asks the user. There is
   then nothing to merge, and `merge` is not run. The task session runs the checks on that tree,
   checks the criteria against it, records in the status file and the report that
   the change was already in the base, and asks the user to confirm before the task
   is cleaned up.

   The precondition: while a task merges, which takes seconds, the user runs no git
   command in the main folder. The merge question says so; for a task that may merge
   on its own, the start approval says so; and the board shows a merge in progress.
   The base itself needs no such promise: step 3 moves it only from the accepted base,
   whoever else writes to it. An automatic merge can come while the user works in the
   main folder, which makes a git command of the user's in those seconds likelier; a
   commit there between steps 2 and 3 is the case the compare-and-swap paragraph above
   describes. Phase 1 tests each case of this step (section 8).
7. **One merge at a time.** A merge updates the main folder's files and then moves
   the base, so two merges that overlap in time could interleave those steps and leave
   the main folder half updated. `worktree.sh merge` therefore holds a lock for the repository
   from its first check
   to the check of its result: a folder in the repository's git folder
   (`git rev-parse --git-common-dir`), which `mkdir` either creates or refuses in one
   step. It removes the lock on every exit, except when a merge stops with files of
   the main folder not yet put back (step 6), which keeps the lock and its journal
   entry until they are. A merge that finds the lock waits a few
   minutes, then stops and asks the user; a lock whose owner is gone is reported with
   the command to remove it, never removed on its own. The second of two merges thus
   starts after the first ended, finds that the base moved, and goes back to step 5.
   A merge also retries once when git reports `index.lock`, as the prototype does.
   When the file is still there after the retry, it may be stale: a git process killed
   in the middle of a write, such as step 2's `read-tree`, leaves it behind, and every
   git command in the main folder, the user's too, then fails until it is removed.
   Git's own message says "Another git process seems to be running in this
   repository, or the lock file may be stale" (`unable_to_lock_message` in
   `lockfile.c` at the tag `v2.56.0`). The merge then stops before step 2, or, when
   step 2 had started, keeps the merge lock and its journal entry; either way it shows
   git's message and the command to remove the file once no git process runs there.
   It never removes `index.lock` itself, since a git process of the user's or of an
   editor may still hold it, as it never removes its own merge lock (decision D16).
   Phase 1 tests two merges started at the same moment, and a leftover `index.lock`.
8. **Clean up: retire, then purge.** The task session records `merged` and ends its
   turn. It cannot move or remove its own folder: the folder is its process's working
   directory, and on Windows "the current directory for a process is locked while the
   process is executing. That prevents the directory from being deleted, moved, or
   renamed" (Microsoft's `SetCurrentDirectory` page). Cleanup therefore runs in the
   control session, in two stages.

   **Retire:** `task clean` for a merged task, `task abandon` for one that is not
   merged. Before it ends anything, `worktree.sh retire --check` makes sure that the
   move can happen: the destination is free, the worktree is not locked, and it has
   none of what `git worktree move` takes for submodules. Git 2.56's
   `validate_no_submodules`, which `move_worktree` runs before it renames, refuses a
   worktree whose own record in the repository holds a `modules` folder, even an
   empty one, which its comment accepts as a false positive, and one with a populated
   submodule (`builtin/worktree.c` at the tag `v2.56.0`). `retire --check` looks for
   both. A task folder with either is retired in place: locked where it is, with its
   branch, and shown on the board as retired in place, for the user to clean up by
   hand.

   After the user's OK, the control session deletes the task's session with
   `claude rm <id>`. That also stops the background shell commands and subagents the
   session started, which stopping a session does not: they carry over to its next
   process (agent view page, "The supervisor process"). It also deletes the session's
   own scratch folder, `~/.claude/jobs/<id>/tmp/` (agent view page, "Where state is
   stored"), so the task session keeps nothing the task needs there: its work stays
   in the task folder and its record in its log folder, and approvals 8 and 9 say
   what deleting the session removes. `claude rm` keeps the transcript, and leaves on
   disk a worktree the user created and started the session in (agent view page), so
   it never touches the folder. Then `worktree.sh retire` moves the folder with
   `git worktree move` to `../<repo>.retired/<repo>-<slug>-<task id>`, locks it there
   with `git worktree lock --reason "retired task <task id>"`. It writes nothing into
   the folder: the task's id is in the lock's reason, which `git worktree list
   --porcelain` shows, and in the status file. Observed with git 2.56: the listing
   printed `locked retired task <id>`, and a locked worktree refused
   `git worktree move` until it was unlocked. A task given up during a conflict is
   retired with its rebase still stopped, which git allows (4.2, `abandon`);
   `retire --check` and `retire` then identify the folder by the rebase in progress
   (rule 1).

   Retiring deletes nothing of the task's folder, branch, or review record; it deletes
   only the task's session, with its scratch folder, after approval 8 or 9. The move
   is one rename, and git makes it before it
   records the folder's new place: git 2.56's `move_worktree` stops when `rename`
   fails, before it changes anything (`builtin/worktree.c` at the tag `v2.56.0`, read
   2026-11-24). On Windows the rename fails while a program has its working directory
   in the folder, or a file there open, so a folder in use stays where it was, and the
   user is told. On macOS and Linux the rename succeeds: a program that writes to an
   open file goes on writing into the retired folder, and one that writes by the old
   path finds nothing there. When something creates the old path again, the board
   reports it, and nothing touches it. The task's branch stays, with every commit,
   until the purge.

   **Purge:** `task purge [<id>...]`; `task clean` also offers it for tasks retired
   more than seven days ago (decision D14). For each retired folder it shows the size
   and everything git cannot restore, measured against the base as it is now, for
   every task, merged or abandoned: the branch's commits that are not on the base;
   the staged and unstaged changes; the untracked and ignored files, with an ignored
   folder such as a dependency folder shown once; copies of `.worktreeinclude` files,
   marked unchanged or changed against the originals in the main folder; the edits
   git hides (rule 6); and, for a task retired during a conflict, that its rebase is
   still stopped, with the resolution so far among the changes. Behind that list sits
   a manifest of the whole folder: the
   branch's tip; the base's name and tip, against which the commits were counted; the
   hashes of the staged and unstaged diffs; and every file, also each one inside a
   folder shown once, with its path from the folder's root, size, modification time,
   and content hash, and every link with its destination, never followed. One file
   is left out: the folder's root `.git` file, which points to the worktree's record in
   the repository and which git rewrites when it moves the worktree, as step 1 below
   does. The purge checks it instead by what it points to, before and after the move:
   the worktree's own record, the one `git worktree list` shows for this task.
   Hashing a large dependency folder takes a while, and the purge says so.

   A purge deletes the whole folder, so it is only as safe as the folder is quiet. Its
   precondition, which the user confirms with the OK: no program still writes into
   the folder. Where it can check, the purge does, in steps that each record their
   intent in the status file first (4.8):

   1. It unlocks the worktree and moves it with `git worktree move` to a purging path
      beside it, which keeps git's record of the folder right. On Windows the move
      fails while a program holds the folder or a file in it, as retiring does (S4
      checks both); the purge then locks the worktree again where it is and stops.
   2. Where `lsof` exists, it lists the programs with a file open in the folder, and
      stops on any.
   3. It takes the manifest again, and goes on only when it is as the user approved
      it, with the task's branch at its approved tip and the base at its approved tip
      or at one that descends from it: a base that only moved forward, as when another
      task merged meanwhile, still holds every commit the list showed as on the base.
      Otherwise it locks the worktree again at the purging path, where the next purge
      finds it, and shows the new list.
   4. It refuses while a folder inside is a mount point, because git descends into
      every folder it removes without asking where its files live
      (`remove_dir_recurse` in `dir.c` at the tag `v2.56.0`), so it would delete the
      files of a folder mounted there from elsewhere. On Linux it reads
      `/proc/self/mountinfo`, which lists bind mounts of the same file system too,
      and on macOS the output of `mount`; on Windows, how a folder that a volume is
      mounted on shows in the manifest is unverified, and S4 checks it. The user is
      asked to unmount it first. Then it unlinks every link, because on Windows
      `git worktree remove` follows junctions, such as those a package manager
      creates, and deletes what they point to; refuses populated submodules; and
      removes the folder with `git worktree remove --force`, which the approval
      covers.
   5. The purge's list holds two choices for each task, its folder and its branch,
      and the manifest records both. A kept task's branch is not chosen unless the
      user names it; when only the folder was chosen, the purge ends after step 4 and
      records the branch as kept. Otherwise it deletes the branch, and checks the
      base, in one transaction that git applies
      whole or not at all: `git update-ref --stdin` with the two lines
      `verify refs/heads/<base> <base tip>` and
      `delete refs/heads/task/<slug> <approved tip>`, where `<base tip>` is the tip it
      has just read and found to be the approved one or a descendant of it, as in
      step 3; when the base moves again before the transaction, the transaction fails
      and the purge reads the base once more, a few times at most. A base that moved
      any other way could leave the branch the last name of commits the list did not
      show, so then the branch stays. Observed with git 2.56: with the base moved, the
      transaction failed, exit 128, and the branch stayed; and `git update-ref -d`
      alone, at another tip, refused and kept the branch. The folder is gone by then,
      so the status file records that the folder was removed and the branch kept, the
      purge says exactly that, and a later `task purge <id>` offers to delete only the
      branch, with a new list of its commits that are not on the base and both tips.
      It also keeps the branch while `git worktree list --porcelain` shows it checked
      out in any worktree, or while a rebase in progress in any worktree names it,
      which that listing shows only as `detached` (4.2, `abandon`), here and in a
      purge of the branch alone: observed with
      git 2.56, `git update-ref -d` deleted a branch that another worktree had checked
      out, where `git branch -d` refused, and that worktree's `HEAD` then named a
      branch that no longer existed. The listing and the transaction are two steps,
      so a checkout of the branch in the instant between them is not caught: the
      purge's precondition, which the user confirms, includes that nobody checks out
      the task's branch while the purge runs.

   A write made after step 3 by a program the user left running is not protected, and
   the purge says so when it asks.

   **A purge that fails halfway.** Git 2.56 unregisters a worktree even when deleting
   its folder failed: its `remove_worktree` runs `delete_git_dir` "even if ret is
   non-zero" (same source). What is left is a folder at the purging path, partly or
   wholly empty and no longer a worktree, and the branch stays. The next purge removes
   such a folder only when it is empty and sits at the purging path the status file
   records; anything else is listed for the user to inspect, with a new OK. S4 checks what such a
   failure leaves. Logs stay in every case.
9. **Never pushed.** Nothing in these steps pushes, force-pushes, amends, or resets,
   and nothing aborts a rebase once the resolution of its conflict has started
   (step 5).

### 4.8 Stops, failures, and resuming

- A stop records the phase `stopped` with the step and the reason, writes the report so
  far, and asks the user in the task session what to do, as the prototype's step 14
  does. The folder and the branch stay.
- After a shutdown, or when a session failed, a reply asking it to continue, from the
  peek panel or after `claude attach <short id>`, restarts it from its saved
  conversation and picks the interrupted work back up. A restart alone, by attaching
  or by `claude respawn <id>`, reopens the conversation without continuing the work:
  the agent view page says "To pick the interrupted work back up, send it a reply
  asking it to continue" (section "Sessions show as failed or stopped after
  shutdown", read 2026-11-24). The task session then reads its status file, and after
  a compaction of its context it does the same. The end-to-end checklist of section 8
  checks that such a reply brings a task to its next recorded step.
- A status file written in one step can still lag behind git: a crash can fall
  between a merge and the line that records it. So before each step that changes git
  state, the status file records the step and what is known before it runs: for a
  commit, the branch's tip, which becomes the parent, and the approved tree; for a
  rebase, the task's tip and the base commit it rebases onto; for a merge, the base's
  tip, the commit to merge, and the main folder's index entries; for a retirement,
  the folder and the retired path it moves to; for a purge, the approved manifest
  and the branch's tip. A commit's own id is not known before the commit exists, so
  it is never recorded in advance.
- On a restart the task session reads the repository before it does anything: the
  tips of both branches, whether a rebase or a merge is in progress, the index and the
  folder's fingerprint, and `git worktree list`. A leftover `index.lock` in the main
  folder's git folder stops it before any recovery, and is reported as 4.7, step 7
  says. A new commit on the recorded parent
  means the commit happened, and its tree is then checked as after a hook (4.7,
  step 3). Tips and an index still as recorded mean the step did not start, except
  for a merge: its step 2 can stop inside git after writing some files and before
  writing the index (4.7, step 6), so the restart also compares each file the change
  touches with its version in the accepted base, where step 1 found it, and in the
  task's commit. A file at the task's version, or missing where the task deletes it,
  means step 2 started, and the merge's recovery puts it back (decision D16). A file at neither
  version was written by someone else after step 1, perhaps the user after the
  crash, and is left untouched and named to the user. The merge lock stays until
  every such file is accounted for. Any other
  state, such as a staged index without a commit, or a rebase in progress, stops the
  task and asks the user. Nothing is replayed on a guess. The control session does
  the same before it goes on with a retirement or a purge that was interrupted.
- Closing the control session does not stop the task sessions.
- To give up a task that is not merged: `task abandon <slug>`, which retires it and
  deletes nothing of it but its session, also during a conflict, whose rebase stays
  stopped; its purge, later, lists what it would delete (4.2; 4.7, step 8).

### 4.9 Limits of parallel work

- **How many at once.** Claude and Codex usage grow with the number of tasks running,
  and so does the user's reviewing. Claude Code's agent-teams page advises starting
  "with 3-5 teammates", and the Codex issues above report errors with about three
  sessions at once. `task new` asks before starting a fourth active task in one
  repository, showing the three active ones with their phases (decision D8). It
  counts the tasks of one repository only, while tasks in other repositories use the
  same allowances. A queue for Codex reviews comes only if spike S5 shows that two
  reviews at once interfere (4.6).
- **Ports and databases.** Test suites that bind a fixed port or share a local
  database collide across task folders. The first release does not solve this; the
  guide says so, and a repository can document a per-folder setting in its
  `AGENTS.md`. Other tools give each worktree its own range of ports, which a later
  release could copy.
- **Disk and install time.** Each task folder is a full checkout with its own
  dependencies.
- **Overlapping tasks.** Two tasks that change the same files conflict at the second
  merge, or need a second review after the rebase. Changes that do not share files can
  still break each other's behavior; the checks after every rebase onto a moved base
  are the guard, with a new review before every automatic merge after such a rebase,
  and, for a merge the user approves, only when files overlap (decision D13).

## 5. Safety: what stays and what changes

**Stays as it is:** the reviewer's read-only sandbox, the limits on its tools, the
fingerprints before and after each round, the second look and the rebuttal, the
handling of instruction files, logs outside the reviewed repository, and setup that
writes only after the user approves.

**Changes, as decided (D6).** `AGENTS.md` lists among the safety guarantees:
"nothing in this plugin commits, pushes, or installs software". The task commands
commit on a task branch, merge into the base, after the user's OK or on their own
when the user allowed it, and run a repository's own dependency install in a task
folder. The new wording, with the changes of decisions D5, D7, D13, and D15:

> Nothing in this plugin commits, pushes, or installs software, with three
> exceptions, all in the task commands. The first is a commit on a task branch, at
> most one per approval of the user, or one when the task merges automatically. The
> second is a fast-forward of the base branch in the main folder, one merge at a
> time, from the base commit the task was rebased onto to the commit that was
> checked, whose change was reviewed, and that was reviewed again after a rebase
> whenever the base brought changes to the same files or to an instruction file, and,
> for an automatic merge, after any rebase onto a moved base. It happens after the
> user's explicit OK, or automatically when the user allowed that in the task's start
> approval, the base is neither `main` nor `master`, and the task is clean: the latest
> review returned no findings and no suggestions, no finding was rejected or
> overridden, nothing is left for the user to answer or decide, the reviewer
> confirmed every acceptance criterion, no locked test changed, and the checks pass
> on that commit. The third is the repository's own install command, the one the user
> approved, run inside a task folder. The task commands never push, force-push,
> amend, or reset; never abort a rebase once the resolution of its conflict has
> started; never rebase over a file git does not track; never send to review or merge
> a change that holds a copied local file; when they clean up, delete nothing of a
> task's folder, branch, or review record, but move the folder aside, and delete only
> the task's Claude Code session, with its scratch folder, after the user's OK; and
> delete a retired folder and its branch only in a purge the user approved, of the
> files, commits, and changes it listed, when they are still as listed.

**New guarantees,** most of them carried over from the prototype: the task commands
are user-invoked only; one task session per task; one commit per task, and a second
only after the user's OK; the commit holds the approved tree; the merge
fast-forwards to the exact commit the checks saw, from the exact base commit, one
merge at a time under a lock, never overwrites ignored files, never stashes, never
squashes, and checks its result; a merge without the user's OK only under every
condition of 4.7, step 2, and never into `main` or `master`; tests written first
stay locked unless a recorded decision changes one, and a changed one blocks an
automatic merge; a merge cut short puts back only files that hold the task's
version, and a stale `index.lock` is reported, never removed; no rebase is aborted
once the resolution of its conflict has started; branch names resolve as
`refs/heads/<name>`;
`.worktreeinclude` decides which gitignored files are copied, and a copied file found
in the index, in a review's scope, or in a commit stops the task; a rebase never
replaces a file git does not track; cleanup moves folders aside and deletes nothing
of a task but its session;
a purge unlinks links first and deletes only what the user approved, as it was then,
and a branch only at the approved tip; and the task commands change the main folder
only through the merge, and through a switch to `dev` that the user approves in
`task new` (4.1).

**What the task session is not:** isolated by Claude Code. Its rules and the user's
permission settings keep it in its folder, and the merge is the one step of the task
commands that writes to the main folder. A lasting permission answer the user gives
in a task session is saved there by Claude Code itself (4.3). Decision D11 keeps it
so, because each task merges itself, also while the user's terminal is closed. The
alternative, isolation through `EnterWorktree` with the control session merging,
takes over only if spike S6 shows that Claude Code refuses the merge's commands.

## 6. Changes to this repository, once built

| Path | Change |
|---|---|
| `plugins/codex-review-loop/skills/task/SKILL.md` | New: `new`, `status`, `clean`, `abandon`, `purge`, `stop`. |
| `plugins/codex-review-loop/skills/task-run/SKILL.md` | New: the task session's steps, with tests first (4.2) and the check of an automatic merge (4.7, step 2). |
| `plugins/codex-review-loop/agents/test-author.md` | New, from the prototype's agent of that name: writes tests from the task file and the interface before the implementation exists, and creates and edits test files only (4.2, decision D7). The prototype gives it `Read`, `Grep`, `Glob`, `Write`, `Edit`, and `Bash`, to run each new test once. |
| `plugins/codex-review-loop/skills/task/worktree.sh` | Ported from the prototype: `preflight`, `create`, `copy-local`, `commit`, `rebase`, `merge`. New: `retire` and `purge`, which take the place of the prototype's `remove` (4.7, step 8), and which also take a folder whose rebase is stopped at a conflict; `resolve-start` and `resolve-continue` (4.7, step 5), with no command that aborts a rebase once its resolution has started (decision D15); and the rules of 4.7 in each command they concern: the identity check, also during a rebase in progress (rule 1); the commit each command expects (rule 2); the base that moves only forward (rule 3); the paths a rebase writes (rule 4); the edits git hides, in `commit` and `purge` (rule 6); the approved tree object (rule 7); the copied files (rule 8); and the merge lock (rule 9, step 7). `merge` itself is rebuilt: a compare-and-swap of the base with `update-ref` and an update of the main folder with `read-tree`, in place of the prototype's `git merge --ff-only` (4.7, step 6), with the recovery of a merge cut short and the report of a leftover `index.lock` (decision D16). Its fingerprint gives way to the loop's `fingerprint.sh`; `hash`, which locks the tests written first, is ported with them (decision D7). |
| `plugins/codex-review-loop/skills/codex-loop/SKILL.md` | One addition: before every Codex run, each round and each rebuttal, the check of the copied files that `copied-files.txt` in the log folder lists, when that file exists, against the index, the untracked files, and in branch mode every commit of the review's range (4.6). Without it the loop runs as today. |
| `plugins/codex-review-loop/skills/task/task-state.sh` | New: writes and reads status files and `tasks.md`, the latter under its lock, holds the runner claim (4.7, rule 9), prints the board's facts, and checks the conditions of an automatic merge that the records show (4.7, step 2). |
| `plugins/codex-review-loop/skills/task/` templates | New: the status file and the report. |
| `tests/worktree.test.sh`, `tests/task-state.test.sh` | Ported and new shell tests, run by `tests/run-all.sh`. |
| `README.md`, `plugins/codex-review-loop/README.md`, `docs/GUIDE.md`, `docs/CHEATSHEET.md` | The task commands, their safety properties, and the guide's section 10 rewritten around them. |
| `AGENTS.md` | The layout table, the checks, the plugin-load row (`Skills (4)` and `Agents (2)  finding-checker, test-author`), the invariant of section 5, and in "Directory listing" the front matter checked before a release, as "the front matter of the four skills and the two agents" in place of "of the two skills and the agent". |
| `CHANGELOG.md`, `plugin.json` | 0.8.0, a minor release: new behavior. |

The setup skill's templates do not change: the task-file rule they install already
names the task folder's own log folder.

## 7. Phases

Phases 1 to 3 each end with the repository's checks and a review by the loop. They
are steps of one change, released together as 0.8.0: the maintainer commits when
phase 3 passes, in one commit with the version and the changelog entry, as the
release rule of `AGENTS.md` asks. A phase committed on its own follows the same rule
in its own commit. Phase 2 updates the row of `AGENTS.md`'s checks that counts the
plugin's skills and agents in the same change as the skills and the new agent, so
that its end-of-phase check can pass. Phase 0 changes nothing in this repository, so it ends with its record
instead.

**Phase 0: experiments.** No plugin code. They run in a scratch repository with a
`dev` branch, which the maintainer trusts once for Claude Code, by starting `claude`
there, and once for Codex, whose trust is its own: a
`[projects."<scratch main folder>"]` entry with `trust_level = "trusted"` in
`~/.codex/config.toml`, as the configuration reference describes. `codex exec
--trust` would save trust too, but it is an option of a run, which needs a prompt
and so would spend a request outside the budget below. What each spike observed is kept
in the loop's private log folder. A failure changes this plan before any code is
written. S3 and S5 run the loop with `--report-only`, which runs one round and no
rebuttal. Phase 0 starts at most four Codex runs: three reviews, and in S3 one run
that is expected to fail at its first request, because its model name does not
exist. Whether such a failed request counts against the allowance is not
documented, so the budget counts it; any more needs the maintainer's OK first.

The spikes run in the order of what each could overturn, and phase 0 stops at the
first failure, which changes this plan before the next spike runs (decision D10):
S1 and S2, whether option C works at all; then S6, who merges; then S3 and S5, the
reviews; then S4, cleanup. A failure of S1 or S2 thus costs none of the Codex runs of
S3 and S5. The spikes' task sessions run in `auto` mode, the mode `task new` offers
first (decision D12), so that S3, S5, and S6 also show whether auto mode lets a task
session run Codex and merge into the main folder, which lies outside the task's own
folder. If its classifier blocks the merge, the fix is an allow rule of auto mode,
or decision D11's alternative.

| Spike | Question | Passes when |
|---|---|---|
| S1 | Can a session's Bash tool start a background session in a task folder? | `claude --bg --name` from the Bash tool starts it; `claude agents --json` lists it under that name; its first prompt runs a plugin skill, and the plugin's agents, as the test-author agent will be, are available to it; it makes no worktree of its own; it can read its full session id from `CLAUDE_CODE_SESSION_ID`; `claude --resume` finds its transcript, with or without `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1`. |
| S2 | Do its questions and prompts reach the user? | `AskUserQuestion` shows as `blocked` with `waitingFor` `input needed`, and a reply from the peek panel answers it; a permission prompt shows as `blocked` with `permission prompt`, and attaching answers it; with `AskUserQuestion` denied by a permission rule, the session records its wait in a status file of the shape of 4.5, written for the spike, and `claude agents --json` shows the session `done`. How the board combines the two is a test of phase 2, which builds the board. |
| S6 | Can a task session merge? | From a background task session in `auto` mode, with a scratch repository's main folder as the working directory, the merge's own two operations, `git read-tree -m -u` on a disposable change and `git update-ref` of a disposable branch checked out there, are not refused by Claude Code; for each, the spike records whether a permission prompt appeared and needed attaching, and whether auto mode's classifier blocked it. The prototype's `worktree.sh merge`, which runs `git merge --ff-only`, does not stand in for them. If Claude Code refuses them, decision D11's alternative takes over: the control session merges. |
| S3 | Does a loop round work in a task folder? One review, with `--report-only`, on a change left uncommitted in the task folder, since the loop stops when there is nothing to review. | The reviewer's commands read the main repository's `.git` through the read-only sandbox; `fingerprint.sh`, `instruction-changes.sh`, and `round-facts.sh` work; the log folder is the task's. Whether Codex reads the task folder's own `.codex/config.toml` cannot be told from the loop's report, which takes the review model from the configuration files, not from Codex. So, with the repository trusted for Codex, the task folder's `.codex/config.toml`, and only that one, sets `review_model` to a model name that does not exist, as an uncommitted change. A run that fails on that name shows that Codex read the task folder's file; S3 then removes the name and runs again, which is also the control: the same review without the name succeeds. A run that succeeds shows that Codex did not read it, and is S3's review. Either way S3 spends one review. |
| S5 | Do two task sessions review at once without interfering? Two reviews, each with `--report-only`, on a change left uncommitted in each task folder. | Both rounds complete, each fingerprint matches, and each log folder holds only its own task's files. If they interfere, the plan adds a queue for Codex reviews before any code (4.6, decision D8). |
| S4 | Can the control session retire and purge on Windows, after a background session? | Retiring a task folder fails while its session runs, while a shell's working directory is in it, and while a file in it is open, and the folder then stays where it was; retiring succeeds after `claude rm`, and after that shell left the folder; `claude rm` leaves the folder in place and stops a background command the session started, such as one that writes a file every second, which `claude stop` alone does not; a purge that fails halfway leaves what is recorded, on disk and in `git worktree list`. And a folder inside a retired folder with a volume mounted on it (`mountvol`): what the purge's manifest records for it, and that the purge refuses while it is mounted. |

**Phase 1: the git steps.** Port `worktree.sh` and its tests, `hash` among them; add
`retire` and `purge` in place of `remove`, `resolve-start` and `resolve-continue`, and
each rule of 4.7 with its tests; and add the tests to `tests/run-all.sh`. Nothing
changes for users yet.

**Phase 2: the commands.** The `task` and `task-run` skills, with tests first and the
check of an automatic merge; the `test-author` agent; `task-state.sh` with its tests;
and the templates.

**Phase 3: release 0.8.0.** Documentation, the invariant of section 5, the version,
and the end-to-end checklist of section 8 on each system it can run on.

**Later, each on the maintainer's word:** a board file that updates itself; the
prototype's Claude review stage; a per-folder port setting; and option B, one
terminal per task, for users whose organization turns agent view off (decision D1).

## 8. Tests

- **Shell tests** for every command of `worktree.sh` and `task-state.sh`, in throwaway
  repositories, as the prototype's test file does today, run by `tests/run-all.sh` on
  Linux, macOS, and Windows in the existing workflow. The prototype's workflow pins
  macOS's own bash 3.2; this repository's workflow does not, and phase 1 decides
  whether to add that pin.
- **Cases the review rounds of this plan found,** each a shell test in phase 1, one or
  more per rule of 4.7: a rebase onto a base that tracks a path where the task folder
  keeps an ignored file, and a rebase of a task that stopped tracking a file and
  keeps it ignored; a file marked `assume-unchanged` with an edit, at `commit` and in
  a purge's list; a commit someone else made on the task branch before the first
  review, and one added after the rebase; an edit saved after the gate, which the
  approved tree object catches; a hook that changes the commit, and one that stages a
  copied file; a copied file that a change of ignore rules brings into a review's
  scope; a base reset to an older commit, before the rebase and before the merge; a
  rebase after which the repository asks for another install command; two merges
  started at the same moment; two `task new` started at the same moment, both kept in
  `tasks.md`; the same task session launched twice, the second stopping at the runner
  claim; a conflict resolved through `resolve-start` and `resolve-continue` while
  `HEAD` is detached; a retirement while a
  file in the folder is written, and a file written at the old path afterwards; a
  purge whose manifest changed after the approval, by a new file in an ignored folder
  or by a file of the same size and modification time with other content; a branch
  that moved after the purge's approval, which `update-ref` keeps; a `starting`
  task with no folder or branch, cancelled by `task abandon`; two `task new` started
  with the clock held at the same second, which get different ids; a reset of the
  base from outside, from the main folder and from another worktree, between the
  merge's update of the files and its compare-and-swap, which then refuses and puts
  the files back; an ignored file at a path the merge adds, which stops it; a local
  edit in the main folder that the merge would overwrite, which stops it before
  anything changes; a staged and an unstaged change to other files in the main
  folder, both kept and counted as kept by the final check; a pending
  `git merge --no-commit` in the main folder, which stops the merge; an update of the
  files that fails halfway, with a folder made read-only on Linux and macOS and a
  file held open on Windows, after which the files are restored; `task abandon`
  during a conflict, after part of it was resolved, with one resolution staged and
  then edited again, an edit to a file outside the conflict, an ignored file at and
  one below a path the task's tip tracks, and an edit hidden by `assume-unchanged`,
  which retires the folder with the rebase still stopped and every file as it was;
  the purge of such a folder, which lists the stopped rebase and the resolution,
  removes the folder, and only then deletes the branch, which git refuses while the
  rebase is in progress; the user's own `git rebase --abort`, after which the task
  finds its branch at the recorded tip and asks again; a crash between the merge's update of the
  files and its compare-and-swap, which a restart recognizes; a `task new` cut short
  after it copied a file, whose file is still listed in `copied-files.txt`; a bind
  mount inside a retired folder on Linux, which stops the purge while a file outside
  the folder survives; a base that moved forward during a purge, which still deletes
  the branch, and one reset during it, which keeps the branch and records the removed
  folder; a staged or unstaged change in the main folder to a file the task changes,
  which stops the merge before anything changes; a crash inside the merge's update
  of the files, which a restart finds by the files' hashes, keeping the lock; a
  copied file that a hook put into a commit, kept out of review and merge
  even after a later commit deletes it; a base that cherry-picked the task's change
  and reverted it, after which the rebase keeps the task's commit; a task branch
  checked out in another worktree, which the purge keeps; a kept branch, retired
  with its branch kept, and purged with its branch kept unless the user names it; a
  file the user edits after a crash inside the merge's file update, which the
  recovery leaves untouched and names; a deletion the merge cannot make on Windows
  while a program holds the file, which stops it before the base moves; a merge
  policy that a task merged meanwhile changed in the base's `AGENTS.md`, after which
  only the kept branch is offered; a task folder with a populated submodule, and one whose record holds
  an empty `modules` folder, both retired in place; a runner claim whose holder cannot be
  listed, which is not taken over; a merged task whose retired folder gained a
  tracked edit, which the purge lists; a purge on Windows while a file in the folder
  is open, whose move to the purging path is refused, leaving the worktree locked
  where it was; a base reset between the purge's list and its deletion, which keeps
  the branch; a retired folder that already holds a file of any name, which retiring
  leaves untouched; a copied file that a fix makes visible between two review rounds,
  which the loop stops before the next round; a task whose rounds ran out before a
  rebase needed a review, which asks the user; a rebase that leaves nothing to merge;
  `task stop` and `task abandon` during a git step, which wait for the step boundary;
  `task abandon` of a task whose session was stopped earlier; a purge of an untouched
  retired folder, which passes although the move rewrote its `.git` file; a base
  moved at the moment of the branch's deletion, which the transaction refuses; a
  leftover `index.lock` in the main folder, which the merge and a restart report and
  never remove; in each case of an interrupted merge, every file whose content
  existed only in the main folder still holding that content afterwards; a commit
  made in the main folder between the merge's update of the files and its
  compare-and-swap, after which the merge leaves the files as they are and the task
  finds its change already in the base; `preflight` in a main folder with a detached
  `HEAD` or a rebase in progress, which refuses, and on `main` or `master`, which
  reports a base that needs the user's confirmation; and a locked test that changed
  or went missing, which `hash` reports.
- **The check of an automatic merge.** A script reads the conditions of 4.7, step 2
  that the records show, from the status file, the loop's `<run>-summary.json` files,
  and the locked tests' hashes, with a test for each condition failing alone,
  including a finding rejected in an earlier round under a clean last round, and a
  base of `main` or `master`. The task session judges the one condition no script
  reads: a suggestion or a question in the review's text.
- **The status script:** a write replaces the file in one step; fields read back as
  written; the board's facts cope with a missing status file, a session that
  `claude agents --json` does not list, and a folder that is gone; and a slug used
  twice shows each task's own review, with the purged task and its replacement both
  on the board; and a slug that a task not yet purged holds is refused, also when two
  control sessions approve it a second apart.
- **The skills** have no automated harness yet; item B5 of `docs/TODO.md` is still
  open. An end-to-end checklist, run by hand with background sessions: two tasks at
  once in a scratch repository with a `dev` branch; a task started on `main`, which
  asks for confirmation and offers `dev`; tests written first by the test-author
  agent for a bug fix, failing before the fix; a question; a permission prompt; an
  automatic merge of a clean task, and a merge approval for one that is not clean;
  the second task's rebase after the first one merged, with the review that an
  automatic merge then needs; an overlapping change before a merge the user approves,
  which triggers a second review; a hook that changes the committed content; a
  conflict resolved with the user; a resume after `claude stop`, and one after a
  shutdown by a reply asking the session to continue, which reaches the task's next
  recorded step; a task given up with `task abandon`, once during a conflict; and the
  retirement and purge of a folder that holds an ignored file. It runs on
  each of Windows, macOS, and Linux that the maintainer can run it on. A system it did
  not run on is named as unverified in the guide's known limits and in the changelog,
  as the guide does today for the loop.
- **The published-files check** passes, as for every change.

## 9. Risks

| Risk | Effect | Mitigation |
|---|---|---|
| Agent view is a research preview | Its screen, keys, or JSON change, or a release breaks background sessions | Depend only on `--bg`, `--name`, `agents --json`, `stop`, `rm`, and `respawn`; record the Claude Code version each spike ran on; option B, one terminal per task, if background sessions stop working (D1) |
| Starting a session from a session is undocumented | Task sessions cannot start, or keep no transcript | Spike S1, run first; if it fails, option B becomes the design before any code (D1, D10) |
| Usage grows with each task | A limit is reached in the middle of a review | Ask before a fourth active task; the loop already stops and reports a usage limit |
| Codex runs at the same time fail, as open issues report | A review round fails | Spike S5 on Windows before any code, and a queue for Codex reviews if it fails (D8); the loop stops the failed round and the task waits for the user |
| A clean review is a second opinion, not proof | An automatic merge lands a wrong change that nobody looked at | Only under every condition of 4.7, step 2, and never into `main` or `master`; tests written first by a separate agent and locked; the checks on the commit that lands; a review after any rebase onto a moved base; one commit per task, which one `git revert` undoes; the board shows every automatic merge (D5, D7, D13) |
| An automatic merge comes while the user works in the main folder | A commit of the user's in the seconds between the merge's update of the files and its compare-and-swap takes in the task's change | The merge refuses changes to the paths it touches before it starts; the compare-and-swap refuses a moved base, and the merge then leaves the files as they are; the start approval states the precondition, and the user can set a task to ask (4.7, step 6) |
| A task for `main` or `master` | A change reaches production without the user's promotion | `task new` asks for confirmation and offers `dev`; such a task never merges on its own (D3, D5) |
| The user switches the main folder to another branch while tasks are open | Their merges cannot land | A task keeps its base; its merge waits, and the board and `task new` say so (4.1) |
| The user gives up a conflict partly resolved | `git rebase --abort` discards the resolution, edits outside the conflict, ignored files at tracked paths, and hidden edits | No task command aborts a rebase once its resolution has started; `task abandon` retires the folder as it is; the user's own abort comes after a warning and `git status` (D15) |
| A merge is cut short while it writes the main folder's files | Part of the task's change is in the main folder, under the user's dev server or build | The merge puts back by itself only the files that hold the task's version, leaves any other file for the user, and keeps the merge lock until every file is accounted for (D16) |
| A git process is killed during the merge | A stale `index.lock` makes every git command in the main folder fail | The merge and a restart report it with git's message and the command to remove it, and never remove it themselves (4.7, step 7) |
| A task folder is moved by hand while its task runs | The repository's record of the folder names its old path: the main folder's git cannot find it, and Codex does not apply the main repository's trust to it | The guide says not to, and names `git worktree repair`; the task commands move a folder only with `git worktree move`, which updates the record |
| The task session is not isolated by Claude Code | A task edits the main folder | The skill's rules; only the merge script writes there, with its guards; decision D11 |
| Two merges at once | The main folder is left half updated | One merge at a time under a lock, to the exact commit that was checked; a checked result; a rebase and retry |
| The user's own git command changes the base during a merge, from any worktree | The merge brings back commits the user removed | The merge updates the main folder's files first and moves the base last, only from the accepted base, by a compare-and-swap that git refuses for any other value, and then puts the files back (4.7, step 6) |
| A folder from elsewhere is mounted inside a retired folder | The purge deletes files outside the task | The purge refuses while a folder inside is a mount point (4.7, step 8); S4 checks the Windows case |
| The repository takes changes into its base only through pull requests and CI | A local merge goes around that process | Approval 5 says the merge is local and unchecked by CI, and offers to keep the reviewed branch instead, the only ending when `AGENTS.md` names that process (4.1, 4.3) |
| A program still writes into a retired folder when it is purged | Its last writes are deleted unseen | The user confirms that nothing writes there; the purge checks open files where it can, and says that it cannot protect a later write (4.7, step 8) |
| A task folder holds a populated submodule | `git worktree move` refuses to retire it | `retire --check` runs before the session ends; the folder is retired in place for cleanup by hand |
| The user stops or abandons a task in the middle of a git step | The step is cut in half, in the task folder or in the main folder | `stop` and `abandon` wait for the session to pause at a step boundary (4.7, rule 9) |
| A task uses more review rounds than the user's limit, across several runs of the loop | The allowance goes further than the user agreed | The status file counts the rounds of every run, and a run gets only what is left; beyond it the user is asked (4.6) |
| Files git does not track, in a task folder | Cleanup deletes the only copy of a file | Cleanup only moves the folder aside; a purge deletes what the user approved, checked against content hashes just before deleting (4.7, rule 5 and step 8) |
| A rebase would write a path where the task folder keeps an untracked or ignored file, because the base started to track it or the task stopped tracking it | The rebase replaces the only copy | `rebase` and `resolve-start` stop before they run and ask the user (4.7, rule 4) |
| An edit git's status hides (`assume-unchanged`, `skip-worktree`) | A commit leaves it out, or a purge deletes it unseen | `commit` refuses while such a file differs from the index; a purge lists it (4.7, rule 6) |
| An edit saved after the gate | An unreviewed change is committed and merged | The staged and committed trees must equal the approved tree object (4.7, rule 7) |
| A copied local file enters a review's scope or a commit, through a change of ignore rules or a hook | A secret reaches Codex or the base | Copied files are checked against the index, a review's scope, and every committed tree (4.7, rule 8) |
| Two sessions run the same task | They overwrite each other's work and records | The runner claim (4.7, rule 9) |
| A rebase brings a different install command | A command the user did not approve runs | The approved command is recorded; another asks first (4.7, step 5) |
| The user resets the base while a task runs | A merge brings back removed commits | Every reading of the base must descend from the task's accepted base, before a rebase and at the merge (4.7, rule 3) |
| A rebase brings in changes to other files only | The merged commit is not the reviewed tree | Checks after every rebase; before an automatic merge, a new review after every rebase onto a moved base; for a merge the user approves, a new review when a file the task changes or an instruction file changed, and the moved base shown in the merge question; both recorded in the report (D13) |
| Background commands outlive a stopped session | A writer keeps changing a folder during cleanup | The session is deleted with `claude rm` before the folder moves, and the move deletes nothing; S4 checks it |
| A purge fails halfway on Windows | A partly emptied folder in the retired area, no longer a worktree | The branch stays; the next purge removes only an empty folder at the recorded path, and lists anything else for the user |
| A lasting permission answer in a task session | The rule applies to the whole repository on macOS and Linux | The board says so at every permission prompt and recommends the one-time answer |
| A crash between a git step and its record | A resumed task repeats or skips a step | The status file records each step's expected state first, and a restart compares it with the repository |
| Windows junctions in a task folder | A purge deletes files outside it | The purge unlinks every link first, as the prototype's `remove` does, and is tested for it |
| A task folder in use on Windows | Retiring fails | The folder stays where it was, and the user is told what holds it |
| Changes that conflict in behavior, not in files | The base breaks after both merges | Checks after every rebase onto a moved base, and a review before every automatic merge after one (D13) |
| Copied local files reach the reviewer | Secrets in a review | `.worktreeinclude` is opt-in, and the guide says what a copy exposes |
| A long task loses its place | Steps repeat or are skipped | The status file and the task file hold the state, and the task session reads them first |
| Retired folders pile up | Disk use, a dependency folder each | The board shows their sizes, and `task clean` offers to purge those retired more than seven days ago (D14) |

## 10. Decisions

The maintainer took each decision on 2026-11-25, after reading its options; the
sections named carry it out.

| # | Question | Decision |
|---|---|---|
| D1 | The design | Option C alone: one control session, and a background session per task (sections 2 and 4.2). Option B, one terminal per task, is not built alongside it; it becomes the design only if spike S1 or S2 fails. Until then, a user whose organization turns agent view off cannot run parallel tasks. |
| D2 | Where task folders go | Beside the main folder, `../<repo>-<slug>`, on `task/<slug>` (4.1). |
| D3 | How the base is chosen | The branch checked out in the main folder when `task new` runs, usually `dev`. `main` and `master` need the user's confirmation first, with an offer to switch the main folder to `dev`; with no branch checked out, `task new` refuses. Promoting `dev` to `main` stays the user's own step (4.1). |
| D4 | How a task lands on the base | One commit per task, rebased, fast-forwarded: a straight history, one commit per task (4.7). |
| D5 | Automatic merge | Yes, for a task that ends clean by every condition of 4.7, step 2, unless the user set the task to ask in its start approval, which shows the setting. Never into `main` or `master`. |
| D6 | The safety invariant | The wording in section 5, with the changes of D5, D7, D13, and D15. |
| D7 | What to take from the prototype | Its git steps, tests, and report template, and its tests-first stage with its test-author agent (4.2); a changed locked test blocks an automatic merge. Not its Claude review stage. |
| D8 | Active tasks per repository | Ask before the fourth (4.9). A queue for Codex reviews comes only if spike S5 fails (4.6). |
| D10 | Phase 0 | Run the six spikes in the order of what each could overturn, S1 and S2, then S6, then S3 and S5, then S4, and stop at the first failure (section 7). At most four Codex runs, three of them reviews, plus a little Claude usage. The spikes' task sessions run in `auto` mode. |
| D11 | Isolation of the task session | Not isolated, so that each task merges itself (4.7). If spike S6 shows that Claude Code refuses the merge's commands, the alternative takes over: the task session moves into its folder with `EnterWorktree`, Claude Code then blocks its edits and git commands in the main checkout, the user approves that move for every task, and the control session merges. |
| D12 | Permission modes of task sessions | `manual`, `acceptEdits`, or `auto`, chosen per task in the start approval with `auto` offered first, and passed with `--permission-mode`. `dontAsk`, in which the task cannot ask for its merge, `plan`, in which it cannot edit, and `bypassPermissions`, for a session nobody watches, are refused (4.2). |
| D13 | A new review after a rebase | Before an automatic merge, after every rebase onto a moved base. For a merge the user approves, only when the base changed a file the task changes or an instruction file, and the merge question shows how far the base moved. The checks run after every rebase onto a moved base (4.7, step 4). |
| D14 | Cleanup | Two stages: retire at once, moving the folder aside and deleting nothing but the task's session; purge after seven days, or sooner when the user asks, deleting only what the user approved (4.7, step 8). |
| D15 | Giving up a conflict partly resolved | No task command aborts a rebase once the resolution of its conflict has started. `task abandon` retires the folder with the rebase still stopped and every file as it was; to drop the resolution and keep the task, the user runs `git rebase --abort`, after a warning of what it discards (4.2, 4.7 step 5). |
| D16 | Recovery after a merge is cut short | The merge puts back by itself only the files it can prove it wrote, which hold the task's version, and leaves any other file for the user, keeping the merge lock until each is accounted for. A leftover `index.lock` is reported with the command to remove it, never removed (4.7, steps 6 and 7). |

The numbers of the decisions do not change between versions of this plan, so that
the review records can name them. D9 was dropped on 2026-11-24 by the maintainer's
decision; see section 11. D15 and D16 were added on 2026-11-25.

## 11. Out of scope

Pushing, pull requests, and remote CI; cloud sessions; parallel tasks where background
sessions are turned off, which option B would serve (D1); promoting `dev` to `main`;
version control other than git;
a graphical interface; tasks that span repositories; changes to the review loop's
review logic; the evaluation corpus; and the prototype's repository, which stays as it
is, by the maintainer's decision of 2026-11-24.

## 12. Sources and checks

Read on 2026-11-24 unless a date is given.

| Source | Used for |
|---|---|
| https://code.claude.com/docs/en/agents | Which parallel feature fits which work; agent teams do not isolate teammates in worktrees |
| https://code.claude.com/docs/en/agent-view | `--bg`, `--name`, agent view's groups and keys, peek and reply, which does not answer a permission prompt, a session restarted after a shutdown, which picks its work back up only after a reply asking it to continue, `agents --json` with and without `--all` and its fields, what a stopped session's background commands do, isolation of background sessions, deleting sessions and worktrees, the session's scratch folder that deleting it removes, notifications, supervisor, limits, version history |
| https://git-scm.com/docs/git-worktree | `move` cannot move a worktree with submodules; a linked worktree moved without `git worktree move` needs `repair` |
| https://code.claude.com/docs/en/sessions | Resuming by session id; `--permission-mode` sets the mode of a resumed session |
| git's source at the tag `v2.56.0`, `builtin/worktree.c`, `remove_worktree` and `move_worktree` | A worktree is unregistered even when deleting its folder failed; a move renames the folder before it records the new place, and changes nothing when the rename fails |
| https://code.claude.com/docs/en/permissions | Where a lasting permission answer is saved; a file-edit approval lasts for the session; some prompts offer only a one-time answer |
| `codex exec --help`, Codex CLI 0.171.0 | `--trust` saves Codex's trust for a project, as an option of a run |
| Runs of git 2.56 in scratch repositories, 2026-11-24: merge, purge, and abort | `git update-ref --stdin` with a `verify` of the base and a `delete` of the branch fails whole, exit 128, when the base moved, and keeps the branch; `git update-ref <ref> <new> <old>` moves a branch checked out in the main folder only from `<old>`, and refuses any other value; `git read-tree -m -u <old> <new>`, run before that, updates the index and files while the branch stays, refuses a local edit it would overwrite ("not uptodate", exit 128) before changing anything, keeps a staged and an unstaged change to other files, replaces an ignored file in its way with exit 0, and does not refuse while a clean `git merge --no-commit` is pending; the reverse `git read-tree -m -u <new> <old>` restores the earlier index exactly; `git update-ref -d` deletes a branch that another worktree has checked out, where `git branch -d` refuses; after the base cherry-picked the task's change and reverted it, a plain rebase drops the task's commit and leaves the change out, and `--reapply-cherry-picks` replays it; `git rebase --abort` deletes an ignored file inside a folder where the task's tip tracks a file, exit 0; `git rebase --abort` during a conflict returns an edit outside the conflict to its earlier version and replaces an ignored file at a path the task's tip tracks, exit 0, and refuses, exit 128, when an untracked file that is not ignored is at such a path |
| git's source at the tag `v2.56.0`, `builtin/worktree.c`, `validate_no_submodules` | `git worktree move` refuses a worktree whose record holds a `modules` folder, even an empty one, or that has a populated submodule |
| Runs of git 2.56 on Windows in scratch repositories, 2026-11-25: a rebase stopped at a conflict | `git worktree move` and `git worktree lock` succeed while the rebase is stopped, and the moved folder keeps the rebase, the partly resolved file, and an edit outside the conflict; meanwhile the branch still points at the task's commit, `HEAD` is detached, and `git worktree list --porcelain` shows the worktree as `detached`; `git branch -D` refuses the branch, "used by worktree"; `git worktree remove --force` removes the worktree, after which `git branch -D` deletes the branch; `git rebase --abort` in the moved folder returns the branch to the task's commit and discards the edit outside the conflict, exit 0 |
| git's source at the tag `v2.56.0`, `unable_to_lock_message` in `lockfile.c` | The message for a lock file that exists: another git process may be running, or the lock file may be stale |
| The prototype, 0.3.0 at `3a7a44b`: `agents/test-author.md` and the tests-first stage of `skills/start/SKILL.md`, read 2026-11-25 | The test-author agent's tools and limits; when tests come first; the interface, the failing tests, the lock by hash, and the reviewer's check of a changed locked test |
| git's source at the tag `v2.56.0`: `check_updates` in `unpack-trees.c`, `cmd_read_tree` in `builtin/read-tree.c`, `remove_dir_recurse` in `dir.c`, `ACTION_ABORT` in `builtin/rebase.c` | `git read-tree -u` writes files one at a time and, when one fails, exits without writing the index, and it ignores a failed deletion; git's recursive removal descends into every folder, a mounted one too; `git rebase --abort` resets the working tree hard |
| Runs of git 2.56 in a scratch repository, 2026-11-24: locks, reflogs, and rebases | A locked worktree refuses `git worktree move`, and `git worktree list --porcelain` shows the lock's reason; `git reflog exists` tells whether a branch has a reflog; a rebase onto a base that already holds the same change drops the task's commit, and the tip ends at the base |
| https://code.claude.com/docs/en/permission-modes | `dontAsk` denies anything that would ask; the `--permission-mode` flag comes before `permissions.defaultMode` in the order that sets a new session's mode; `auto` is a terminal session's built-in default |
| https://code.claude.com/docs/en/worktrees | `--worktree` location and branch, `worktree.baseRef`, `.worktreeinclude`, which sessions the isolation checks cover, a lasting permission answer saved in the main checkout on macOS and Linux |
| https://code.claude.com/docs/en/sub-agents | Tools removed from every subagent, `AskUserQuestion` among them; background subagents raise their permission prompts in the main session |
| https://code.claude.com/docs/en/permissions | Workspace trust keyed on the main checkout's root in a worktree; trust check of `claude --bg` |
| https://code.claude.com/docs/en/errors | `CLAUDE_CODE_CHILD_SESSION` and transcript saving; `Workspace not trusted` |
| https://code.claude.com/docs/en/cross-session-messaging | Messages between local sessions, not used by this design |
| `claude --help`, Claude Code 2.1.331 | `--bg`, `-w`, `--tmux`, `-n`, the choices of `--permission-mode`, and the `agents`, `attach`, `logs`, `stop`, `rm`, `respawn` commands |
| Runs of git 2.56 in scratch repositories, 2026-11-24 | `git worktree remove` without `--force` deletes an ignored file that is the only copy, and a tracked file's edit hidden by `assume-unchanged`, and exits 0; a rebase replaces an ignored file at a path the base has started to track, and exits 0; `git update-ref -d` with an expected value refuses at another tip and deletes at that one |
| https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setcurrentdirectory | A process's current directory cannot be deleted while the process runs |
| The prototype, 0.3.0 at `3a7a44b`: `skills/start/SKILL.md`, `worktree.sh`, `tests/worktree.test.sh`, `README.md` | The git steps and their guards, the task flow, the report template |
| This repository at `2a99609`: `log-dir.sh`, `SKILL.md` of the loop, `docs/GUIDE.md` sections 9 and 10, `AGENTS.md` | How the loop names its log folder and runs; the current advice for parallel work; the invariants |
| https://code.claude.com/docs/en/agent-teams | Agent teams are experimental; "Start with 3-5 teammates" |
| https://learn.chatgpt.com/docs/config-file/config-reference | `projects.<path>.trust_level` covers "a project or worktree"; untrusted projects skip project-scoped `.codex/` layers |
| Codex source at the tag `rust-v0.171.0`, `codex-rs/git-utils/src/trust.rs` | A worktree resolves to its main repository for trust, only while the repository's record of the worktree names the folder it is in |
| https://learn.chatgpt.com/docs/pricing | Local messages and cloud chats share one allowance; local reviews count toward the general limits; what a message uses depends on the model and the task's size and complexity, and the message counts are estimates |
| https://git-scm.com/docs/git-read-tree | Two-tree merge: a change the user staged to the new version, edited again or not, keeps its index entry (cases 18 and 19) |
| Codex issues #33741, #42447, #43402, #54010, #54017, #63631 | Reported trouble with concurrent Codex runs |
| Repositories and documentation of claude-squad, ccmanager, Conductor, Crystal and its successor Nimbalyst, Vibe Kanban, uzi, worktrunk, git-worktree-runner, agent-deck, Sculptor, Superset, cmux, the Codex app, the Copilot cloud agent, and Cursor | The survey of section 2: how tools create tasks, show their state, take answers, merge, and clean up; their pain points |

Two statements rest on readings of Codex's source by an assistant, not on a run or on
documentation: that a trusted worktree reads its own `.codex/config.toml`, and which
folders the Windows sandbox lets the reviewer read. Spike S3 settles both.
