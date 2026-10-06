# Changelog

Changes to the codex-review-loop plugin, newest first. Claude Code updates an
installed copy only when the version in `plugins/codex-review-loop/.claude-plugin/plugin.json`
changes; see the README's Update section. Documentation changes that need no update
are listed at the end.

## 0.1.6 — 2026-10-06

- Prepared for Anthropic's plugin directory: `plugin.json` gains `homepage`,
  `repository`, and an author `url`, and the plugin folder gains its own `README.md`,
  which the directory shows as the listing and which describes what the plugin
  runs, sends, and writes.

## 0.1.5 — 2026-10-05

- The review command works when copied by hand into `~/.claude/skills`, outside the
  plugin system: when it needs to create `docs/reviews/decisions.md` and the setup
  template is out of reach, it writes the heading and table header itself.

## 0.1.4 — 2026-10-05

- `--report-only` now truly changes nothing in the repository: a rejected finding
  is recorded in the round log instead of `docs/reviews/decisions.md`.
- A review without a task file — an audit, a missing `task.md`, or your "no
  requirement" answer — no longer updates or archives `task.md`, which is absent or
  belongs to another task.
- Rerunning `setup` with a different model or effort choice now shows and applies
  the change; before, the comparison rule silently kept the old values.
- The documented model fallback is correct: without `review_model`, a review runs
  on the session model (`model` in the config, else the account default), per
  OpenAI's configuration reference.
- The plugin's author reads "The codex-review-loop authors", matching the license.

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

- 2026-10-05: `docs/manual-install/` explains how to review the plugin and install
  it without trusting GitHub: from your own clone, by copying the plugin folder, or
  by hand. Linked from the README.
- 2026-10-05: the repository is public — the README and guide now say the plain
  install needs no credentials, and the stored-credential steps apply only to a
  private fork or mirror. The README opens with why the loop uses a reviewer from
  a different vendor. The guide and cheat sheet state the session-model fallback.
- 2026-10-05: update steps in the README, guide, and cheat sheet now use
  `claude plugin update codex-review-loop@codex-review-loop` after refreshing the
  marketplace; refreshing alone leaves the installed version unchanged.
- 2026-10-05: README Update section explains how to check the installed version;
  this changelog.
- 2026-10-05: cheat sheet gains a "When to use" column and a table of plugin and
  Codex commands.
- 2026-10-03: README states that reviewed code and the task file are sent to OpenAI
  through your ChatGPT account, and names the install command's account.
