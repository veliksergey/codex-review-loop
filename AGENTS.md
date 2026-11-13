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
| `plugins/codex-review-loop/README.md` | The plugin-folder README. Anthropic's directory shows it as the listing; it must stay at least 40 words outside code blocks and describe what the plugin runs, sends, and writes. |
| `plugins/codex-review-loop/skills/codex-loop/` | The review loop skill, the review prompt sent to Codex, the task file template, the triage file template, and five scripts: `fingerprint.sh`, the before/after working-tree check; `log-dir.sh`, which prints the log folder and stops when another repository with the same folder name already uses it; `mcp-off-flags.sh`, which prints the flag that turns the configured MCP servers off; `tool-flags.sh`, which builds the flags that limit the reviewer's tools and checks them against Codex before a review starts; and `round-facts.sh`, which reads what the reviewer ran from Codex's log and identifies the round by its prompt and commit. |
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
| Log folder script | `bash tests/log-dir.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| Round facts script | `bash tests/round-facts.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| MCP flags script | `bash tests/mcp-off-flags.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| Tool flags script | `bash tests/tool-flags.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |

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
  `veliksergey`, in the install command `veliksergey/codex-review-loop` and in the
  repository URLs in `plugin.json`. The same goes for usage: no usage figures, no
  numbers derived from anyone's review logs or Codex session records, and no details
  of a real computer such as its configuration or installed tools. Evidence of that
  kind may guide a change, but it stays outside the repository.
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
  `-c 'sandbox_mode="read-only"'`; a review runs with Codex's connectors other than
  web search, its plugins, and its MCP servers turned off unless the user passes
  `--allow-tools`; the loop stops a review in which no sandboxed command ran or a
  tool that should be off was called; the loop fingerprints the tree before and after
  each round; nothing in this plugin commits, pushes, or installs software; logs
  live outside the reviewed repository; setup writes only after the user approves
  the exact change and backs up the file first.
- **Facts are sourced.** A claim about Claude Code or Codex behavior in the docs or
  skills comes from the official documentation or from a run that was actually
  observed. Mark anything else as unverified.

## Directory listing

The plugin is submitted to Anthropic's directory from the developer portal at
https://claude.ai/directory/manage, with `plugins/codex-review-loop` as the plugin
path and `main` as the tracked branch. The directory rescans `main` on every push
and on a schedule, and the docs require `version` in `plugin.json` to rise with every
release, so the release rule above applies to the listing too. Before pushing a
release, validate against the checklist at https://claude.com/docs/plugins/pre-submission-checklist:
no hooks or MCP servers are declared today, so the checks that apply are the
manifest fields, the plugin README, the license, and file names and sizes.

## Branches

`main` is the only branch so far. No branch policy yet.

## Review decisions

Rejected review findings and their evidence: `docs/reviews/decisions.md`.
