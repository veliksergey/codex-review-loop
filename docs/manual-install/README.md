# Installing without trusting GitHub

The normal install in the [main README](../../README.md) pulls the plugin straight
from GitHub. That is convenient, but it means trusting whoever controls the
repository, today and with every update you accept later.

If you would rather read the code first and decide yourself when to take a new
version, use one of the three paths below. All three give you the same review
loop; they differ in how much of the plugin system you use.

## What you would be trusting

The plugin is the folder `plugins/codex-review-loop/`, 15 files:

| Files | What they are |
|---|---|
| `.claude-plugin/plugin.json` | The plugin's name, version, and description. |
| `skills/codex-loop/SKILL.md` | Instructions Claude follows when it runs a review. |
| `skills/codex-loop/review-prompt.md` | The prompt sent to Codex. |
| `skills/codex-loop/task-template.md` | The shape of the task file Claude writes. |
| `skills/codex-loop/fingerprint.sh` | The only script: 17 lines of read-only `git` commands that fingerprint your working tree before and after each review. |
| `skills/setup/SKILL.md` | Instructions Claude follows when you run the setup command. |
| `skills/setup/templates/` | Eight plain-text templates that setup pastes into your config files. |
| `LICENSE` | MIT. |

There are no hooks, background servers, or agents. Nothing runs when Claude Code
starts; Claude reads these files only when you, or the rules in your `CLAUDE.md`,
start one of the two commands.

When those commands run:

- **The review command** reads your repository with git, runs Codex with a
  read-only sandbox, writes its logs to `~/.claude/codex-reviews/<repo>/`, and edits
  your code only to fix findings. With `--report-only` it edits nothing.
- **The setup command** changes `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, and
  `~/.codex/config.toml`, each only after showing you the exact change and getting
  your approval, and backs each file up first.
- **Your code and the task file** are sent to OpenAI through your ChatGPT account
  when Codex reviews them, as with any Codex use.

## Review it in about ten minutes

1. Clone the repository somewhere you keep it:

   ```bash
   git clone https://github.com/veliksergey/codex-review-loop.git
   cd codex-review-loop
   ```

   On Windows, if git stops with `Filename too long`, clone into a shorter folder
   such as `C:\src`, or run
   `git -c core.longpaths=true clone https://github.com/veliksergey/codex-review-loop.git`.

2. List what the plugin contains. Expect the 15 files above:

   ```bash
   git ls-files plugins/
   ```

3. Check that nothing is set to run on its own. Expect no output:

   ```bash
   grep -rnE '"(hooks|mcpServers|lspServers|monitors)"' .claude-plugin plugins
   ```

4. Read `fingerprint.sh` and the two `SKILL.md` files. The templates are short
   enough to skim.

5. Note the commit you reviewed, so you can compare against it later:

   ```bash
   git log -1 --format='%H %s'
   ```

## Choose a path

| | [1. From your own clone](1-from-your-own-clone.md) | [2. Copy the plugin folder](2-copy-the-plugin-folder.md) | [3. By hand](3-by-hand.md) |
|---|---|---|---|
| How | Register your reviewed clone as a local marketplace | Copy one folder into `~/.claude/skills` | Copy the review command as a personal skill, and paste the rules into your config files yourself |
| Commands you get | `/codex-review-loop:codex-loop` (short: `/codex-loop`) and `/codex-review-loop:setup` | The same | `/codex-loop` only. You do setup's job by hand |
| Taking a new version | `git pull` in your clone, after reading the changes | Replace the folder with the newer one | Replace the skill folder and update the blocks you pasted |
| Effort | Lowest | Low | Most |

**Start with path 1** unless you have a reason not to. It behaves exactly like the
normal install, except that Claude Code reads the plugin from your own folder and
never contacts GitHub.

## How these pages were tested

On Windows on 2026-10-05, each path in a separate, empty Claude Code profile:

- **Paths 1 and 2:** installed, checked, updated, and removed exactly as written.
- **Path 3:** the copy and update commands were run as written, and the copied
  skill was confirmed to load. That check used the skill as a project skill
  (`.claude/skills` inside a folder), because the empty profile was not signed in
  to Claude; personal skills in `~/.claude/skills` load by the same rules. Pasting
  the rule blocks (step 3) was not run end to end.
- Nothing has been tested on macOS or Linux yet.
