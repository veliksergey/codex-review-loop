# Changelog

Changes to the codex-review-loop plugin, newest first. Claude Code updates an
installed copy only when the version in `plugins/codex-review-loop/.claude-plugin/plugin.json`
changes; see the README's Update section. Documentation changes that need no update
are listed at the end.

## 0.1.3 — 2026-10-05

- `setup` no longer reports the `config.toml` review defaults as changed just
  because they hold your own model, effort, and web search values. It compares
  only the markers and comments of that block, so a rerun says "up to date"
  instead of asking "Update / Keep mine" every time. Updating that block keeps
  your values.

## 0.1.2 — 2026-10-05

- The review's before/after check of the working tree now also covers the contents
  of untracked files, so an edit to new code under review is caught.
- That check moved into `skills/codex-loop/fingerprint.sh`. It works from the
  repository root whatever folder Claude Code was started in, and a failing step
  stops the loop instead of printing a fingerprint. The first version of the
  untracked-file check hashed nothing when Claude Code was started in a subfolder.
- The review command no longer pre-approves `cp` and `cat`; it archives the task
  file with Claude's own file tools.
- A missing `docs/reviews/decisions.md` is created from the setup command's
  template.

Copies installed between 2026-10-03 and 2026-10-05 reported 0.1.1 but already had
the untracked-file check in its first, flawed form, plus the `cp`/`cat` and
template changes. Update to get the fixed check.

## 0.1.1 — 2026-10-02

- MIT license, in the repository and in the plugin folder.

## 0.1.0 — 2026-10-02

- First release: the `codex-loop` review command, the `setup` command with
  `machine`, `repo`, and `check` modes, the README, the guide, and the cheat sheet.

## Documentation only (no update needed)

- 2026-10-05: README Update section explains how to check the installed version;
  this changelog.
- 2026-10-05: cheat sheet gains a "When to use" column and a table of plugin and
  Codex commands.
- 2026-10-03: README states that reviewed code and the task file are sent to OpenAI
  through your ChatGPT account, and names the install command's account.
