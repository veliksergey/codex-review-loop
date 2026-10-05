# AGENTS.md

Rules for AI coding agents and people changing this repository.

## What this repository is

A Claude Code plugin, published from this repository as its own marketplace. Claude
Code implements; the Codex CLI reviews read-only. Users install it with
`/plugin marketplace add veliksergey/codex-review-loop`.

| Path | Contents |
|---|---|
| `.claude-plugin/marketplace.json` | Marketplace catalog with one entry, `codex-review-loop`. |
| `plugins/codex-review-loop/.claude-plugin/plugin.json` | Plugin manifest, including `version`. |
| `plugins/codex-review-loop/skills/codex-loop/` | The review loop skill, the review prompt sent to Codex, the task file template, and `fingerprint.sh`, the before/after working-tree check. |
| `plugins/codex-review-loop/skills/setup/` | The setup skill and the blocks it installs in users' global files. |
| `tests/` | Shell tests. Not shipped with the plugin. |
| `docs/` | User documentation. `docs/reviews/decisions.md` records rejected review findings. |

## Commands

There is no build or lint. These are the checks:

| Check | Command | Passes when |
|---|---|---|
| Marketplace manifest | `claude plugin validate --strict .` | Exit 0 |
| Plugin manifest and skills | `claude plugin validate --strict plugins/codex-review-loop` | Exit 0 |
| Plugin loads with both skills | `claude --plugin-dir ./plugins/codex-review-loop plugin details codex-review-loop` | Lists `Skills (2)  codex-loop, setup` |
| Fingerprint script | `bash tests/fingerprint.test.sh` | Exit 0, prints `all passed` |

## Release rule

Users receive a change only when the plugin's version changes. Every change under
`plugins/` raises `version` in `plugins/codex-review-loop/.claude-plugin/plugin.json`:
patch for wording and fixes, minor for new behavior or a changed template. Set the
version only there, never also in `marketplace.json`. Add an entry for the new
version at the top of `CHANGELOG.md` in the same commit, and list documentation-only
changes under "Documentation only".

## Invariants

- **No personal or company details.** No names of people or companies, email
  addresses, internal host or machine names, ticket numbers, private repository
  names, or absolute paths from a real computer. Examples use placeholders such as
  `<repo>`, `src/auth`. The one exception is the repository owner's GitHub account,
  `veliksergey`, in the install command `veliksergey/codex-review-loop`.
- **Portable shell commands.** Commands in skills must work in bash on macOS, on
  Linux, and in Git Bash on Windows. Prefer git built-ins over platform tools: for
  example `git hash-object --stdin`, not `sha1sum`. No GNU-only flags.
- **Bundled files by variable.** Skills reference their own files through
  `${CLAUDE_SKILL_DIR}` and another skill's files through `${CLAUDE_PLUGIN_ROOT}`,
  never through a `~/.claude/skills/` path or `..`. The rules that
  setup installs in `CLAUDE.md` must not point into the plugin's install folder,
  because that path changes with every version.
- **Markers stay.** Each file in `skills/setup/templates/` that setup inserts into a
  user's file starts and ends with its `codex-review-loop:begin <id>` and
  `codex-review-loop:end <id>` markers. Setup finds and updates blocks by those
  markers; a block id never changes once released.
- **The safety guarantees stay.** Codex always runs with
  `-c 'sandbox_mode="read-only"'`; the loop fingerprints the tree before and after
  each round; nothing in this plugin commits, pushes, or installs software; logs
  live outside the reviewed repository; setup writes only after the user approves
  the exact change and backs up the file first.
- **Facts are sourced.** A claim about Claude Code or Codex behavior in the docs or
  skills comes from the official documentation or from a run that was actually
  observed. Mark anything else as unverified.

## Branches

`main` is the only branch so far. No branch policy yet.

## Review decisions

Rejected review findings and their evidence: `docs/reviews/decisions.md`.
