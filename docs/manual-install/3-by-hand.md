# Path 3: set it up by hand

No plugin at all. You copy the review command into Claude Code as a personal skill
and paste the rules into your config files yourself. You get `/codex-loop`, but not
the setup command: these steps do its job.

Run the commands below from inside your clone, where the review steps leave you. On
Windows, run them in Git Bash, which the review command needs anyway.

## 1. Get the files

Clone the repository and review it, as described in
[Review it in about ten minutes](README.md#review-it-in-about-ten-minutes).

## 2. Install the review command

Copy the `codex-loop` skill folder, all four files:

```bash
mkdir -p ~/.claude/skills
cp -R plugins/codex-review-loop/skills/codex-loop ~/.claude/skills/codex-loop
```

Claude Code picks up personal skills from `~/.claude/skills`, so this adds the
`/codex-loop` command. If you also have the plugin installed, this personal copy
takes the short name `/codex-loop`; uninstall one of the two to avoid confusion.

## 3. Paste the rules into your config files

This step was not run end to end when this page was written. The blocks are the
same templates the setup command installs.

The rules live in `plugins/codex-review-loop/skills/setup/templates/` in your clone.
Back up each file before you change it, for example
`cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak`. Create a file if it does not exist.

| Template | Paste into | Where | Needed? |
|---|---|---|---|
| `claude-rules.md` | `~/.claude/CLAUDE.md` | At the end | Yes. It tells Claude to write a task file and run the loop after each task. |
| `codex-reviewer.md` | `~/.codex/AGENTS.md` | At the end | Yes. It tells Codex how to report findings. |
| `shared-invariants.md` | `~/.codex/AGENTS.md` | At the top | Optional, recommended: shared rules on honesty, security, and change quality. |
| `shared-import.md` | `~/.claude/CLAUDE.md` | As the first lines | Only with `shared-invariants.md`: it makes Claude read the same rules. |
| `codex-config.toml` | `~/.codex/config.toml` | Above the first line that starts with `[` | Optional: review model, effort, and live web search for the reviewer. |

Paste each template whole, including its `codex-review-loop:begin` and
`codex-review-loop:end` marker lines. They change nothing in how the files work,
and if you later switch to the plugin, its setup command recognizes the marked
blocks and updates them instead of adding copies.

For `codex-config.toml`, also:

- Replace `{{REVIEW_MODEL}}` with a model name from `~/.codex/models_cache.json`,
  or delete that line to let reviews use your session model.
- Replace `{{EFFORT}}` with `low`, `medium`, `high`, or `xhigh`.
- If one of its three keys already appears near the top of your `config.toml`, do
  not add it a second time: TOML rejects duplicate keys. Change the existing line
  instead.

## 4. Create the log folder

```bash
mkdir -p ~/.claude/codex-reviews
```

The review command keeps its task files and logs here, outside your repositories.

## 5. Prepare each repository

At the root of each repository you want reviewed:

1. If the repository has no `docs/reviews/decisions.md` yet, copy `repo-decisions.md`
   there. Claude records rejected findings in that file, and Codex reads it so it
   does not raise them again. Keep an existing one: its rows are your review history.
2. If the repository has no `AGENTS.md`, copy `repo-AGENTS.md` to `AGENTS.md`.
   Replace `{{TYPECHECK}}`, `{{LINT}}`, `{{TEST}}`, and `{{BUILD}}` with your check
   commands, or `none`, and `{{BRANCHES}}` with your branch rules. If you already
   have an `AGENTS.md` or `CLAUDE.md`, make sure it names the check commands.
3. Optional: to review this repository with a different model, set `review_model`
   in the repository's `.codex/config.toml`. If that file does not exist, copy
   `repo-codex-config.toml` there and fill in the model. If it exists, keep it: back
   it up and add or change only the `review_model` line, above the first line that
   starts with `[`. Codex reads this file only if you have marked the repository as
   trusted, by running `codex` there once and accepting the prompt.

Commit these files yourself after reading them.

## 6. Check that it worked

Start a new Claude Code session at the root of a prepared repository. Typing
`/codex-loop` should offer the command. Make a small change and run:

```text
/codex-loop --report-only
```

The [guide's First review section](../GUIDE.md#6-first-review) describes what you
should see.

## Take a new version

First bring the new version into your clone, reading the changes before you accept
them: see [path 1](1-from-your-own-clone.md#take-a-new-version) for the commands.
`CHANGELOG.md` explains each version.

Then replace the skill. Remove the old folder first; copying onto an existing folder
would put the new copy inside it:

```bash
rm -rf ~/.claude/skills/codex-loop
cp -R plugins/codex-review-loop/skills/codex-loop ~/.claude/skills/codex-loop
```

Finally, update any pasted block whose template changed.

## Remove

Delete `~/.claude/skills/codex-loop`, delete the marked blocks you pasted, or
restore your backups, and delete `~/.claude/codex-reviews/` if you no longer want
the logs.
