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
| `plugins/codex-review-loop/skills/codex-loop/` | The review loop skill, the review prompt sent to Codex, the task file template, the triage file template, the run summary template, and seven scripts: `fingerprint.sh`, the before/after working-tree check; `instruction-changes.sh`, which lists the instruction files a change edits; `log-dir.sh`, which prints the log folder and stops when another repository with the same folder name already uses it; `task-hash.sh`, which hashes the request and the acceptance criteria of the task file; `mcp-off-flags.sh`, which prints the flag that turns the configured MCP servers off; `tool-flags.sh`, which builds the flags that limit the reviewer's tools and checks them against Codex before a review starts; and `round-facts.sh`, which reads what the reviewer ran from Codex's log and identifies the round by its prompt and commit. |
| `plugins/codex-review-loop/skills/setup/` | The setup skill and the blocks it installs in users' global files. |
| `tests/` | Shell tests; `run-all.sh`, which runs them all and prints one table of the cases that passed, failed, and were skipped; `published-files.sh`, which looks for a home-folder path or an e-mail address in the files git would publish; and repository tooling in Python: `loop_stats.py`, which prints figures about a user's own review runs, `eval_corpus.py`, which builds and checks the evaluation corpus, and `eval_review.py`, which runs a Codex review on a case of the corpus as the loop runs one and scores reviews against the labels, each with its tests. Not shipped with the plugin. |
| `tests/eval/` | The evaluation corpus: cases that a review can be run on, each a defect case or its control, with a label for each that says what is wrong. `tests/eval/README.md` describes it, and how a review of a case is run, judged, and reported. Not shipped with the plugin. |
| `.github/workflows/tests.yml` | Runs `tests/run-all.sh` on Linux, macOS, and Windows for a push to `main` and for a pull request. It needs no account and installs nothing. It fetches the whole history, which some cases of the corpus are built from, and sets `EVAL_CORPUS_SLOW=1`, so that every proof of the corpus runs on each system that can run it. |
| `docs/` | User documentation. `docs/reviews/decisions.md` records rejected review findings. |

## Commands

There is no build or lint. These are the checks:

| Check | Command | Passes when |
|---|---|---|
| Marketplace manifest | `claude plugin validate --strict .` | Exit 0 |
| Plugin manifest and skills | `claude plugin validate --strict plugins/codex-review-loop` | Exit 0 |
| Plugin loads with both skills | `claude --plugin-dir ./plugins/codex-review-loop plugin details codex-review-loop` | Lists `Skills (2)  codex-loop, setup` |
| Fingerprint script | `bash tests/fingerprint.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| Instruction files script | `bash tests/instruction-changes.test.sh` | Exit 0, prints `all passed` |
| Log folder script | `bash tests/log-dir.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| Task hash script | `bash tests/task-hash.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| Statistics script | `bash tests/loop-stats.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run. Without Python 3.8 or newer the whole test is one skip |
| Round facts script | `bash tests/round-facts.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| MCP flags script | `bash tests/mcp-off-flags.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| Tool flags script | `bash tests/tool-flags.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| Published files | `bash tests/published-files.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run. Its last case runs `tests/published-files.sh` on this repository |
| Test runner | `bash tests/run-all.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run |
| Evaluation corpus | `bash tests/eval-corpus.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run. On Windows the proofs that run a shell test take minutes and are one skip, unless `EVAL_CORPUS_SLOW=1` is set, as the workflow sets it; `python tests/eval_corpus.py check --slow` runs them too. Without Python 3.8 or newer the whole test is one skip |
| Review runner | `bash tests/eval-review.test.sh` | Exit 0, prints `all passed`, followed by a skip count where a case cannot run. A stand-in takes the place of Codex, so it starts no review. Without Python 3.8 or newer, or without a bash that can run the plugin's scripts, the whole test is one skip |

`bash tests/run-all.sh` runs every row from the fingerprint script down in one go. It
prints one table of the cases that passed, failed, and were skipped in each file, names
each failed and each skipped case, and exits 0 when nothing failed. The workflow runs
that command on Linux, macOS, and Windows. The first three rows need Claude Code and are
not part of it. A skipped case is not a passed one: a case that one system skips counts
as checked only where another system runs it.

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
  `tests/published-files.sh` looks for two of these in the text of every file git
  would publish: a path into a home folder with a name in it, and an e-mail address
  outside the hosts reserved for examples. It cannot recognise the others. It reads
  neither file names, nor where a link points, nor the files of a submodule, and it
  passes over the user and the host of an SSH remote and over a path inside a URL that
  is not a file URL. It does not replace reading the change.
- **Python stays in `tests/`.** Repository tooling may use Python 3 with the standard
  library only. Nothing under `plugins/` may need Python, and a system without it must
  still pass every check, with the Python tests reported as skipped.
- **Review figures stay private.** `tests/loop_stats.py` prints figures about one
  person's reviews and writes no file. Its output, and anything else read from a real
  log folder, is never committed. Tests use logs they build themselves. The same holds
  for a review of a case of the evaluation corpus: what the reviewer said, and any
  score made from it, stays outside the repository. `tests/eval_review.py` keeps reviews
  in the loop's log folder and refuses a results folder inside this repository; what
  its `report` prints is private like the figures above.
- **Labels stay outside fixtures.** A label of the evaluation corpus says what is wrong
  with a case, and a reviewer reads everything its fixture holds. So a fixture holds no
  label, no name of a case, and no other case; `tests/eval_corpus.py build` writes it
  outside this repository, and a change to how fixtures are built keeps the test of
  that. No review of a case runs before a person agreed with its label, and a case or
  a label that changes counts as not agreed. Only that person records the agreement:
  an agent does not run `agree` unless the user says so for the cases named.
  `tests/eval_review.py run` refuses a case that is not agreed with. Each call of it
  spends one review of the user's Codex allowance and sends the fixture to OpenAI, so
  an agent runs it only for the cases the user asked a review of; its tests use a
  stand-in for Codex.
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
  each round; the reviewer is told which instruction files a change edits, to apply
  their committed versions, and that a decision in the task file does not excuse a
  defect; nothing in this plugin commits, pushes, or installs software; logs
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
