# Path 1: install from your own clone

You register a folder on your computer as the plugin's marketplace, instead of the
GitHub repository. Claude Code then reads the plugin straight from that folder and
never contacts GitHub. Everything else works as in the normal install.

## Install

1. Clone the repository and review it, as described in
   [Review it in about ten minutes](README.md#review-it-in-about-ten-minutes).

2. If you added the GitHub marketplace earlier, remove it first. Both are named
   `codex-review-loop`, and Claude Code allows only one marketplace per name:

   ```bash
   claude plugin uninstall codex-review-loop@codex-review-loop
   claude plugin marketplace remove codex-review-loop
   ```

3. In a terminal, add your clone and install the plugin. Use the full path to the
   folder that contains `.claude-plugin/marketplace.json`:

   ```bash
   claude plugin marketplace add ~/src/codex-review-loop
   claude plugin install codex-review-loop@codex-review-loop
   ```

   On Windows, for example: `claude plugin marketplace add C:\src\codex-review-loop`.
   Inside Claude Code, `/plugin marketplace add <path>` and
   `/plugin install codex-review-loop@codex-review-loop` do the same.

4. Restart Claude Code, or run `/reload-plugins` in a session that is already open.

5. Continue with steps 2 to 4 of the [main README's Install section](../../README.md#install):
   the setup command, preparing a repository, and a first review.

## Check that it worked

```bash
claude plugin list
```

Under `codex-review-loop@codex-review-loop` you should see the version and a
`Read from:` line that points into your clone:
`<your clone>/plugins/codex-review-loop`.

```bash
claude plugin details codex-review-loop@codex-review-loop
```

This lists what the plugin adds. Expect `Skills (2)  codex-loop, setup`,
`Hooks (0)`, and `MCP servers (0)`.

## Take a new version

Claude Code reads the plugin from your clone every time it starts. Whatever is in
that folder is what runs: a `git pull` takes effect at the next start, with no
update command. So read the changes before you pull them:

```bash
cd ~/src/codex-review-loop
git fetch
git log --oneline HEAD..origin/main
git diff HEAD..origin/main -- plugins/
git merge --ff-only origin/main
```

`CHANGELOG.md` explains each version in plain words. After merging, restart Claude
Code or run `/reload-plugins`, then run `/codex-review-loop:setup`. It updates the
rule blocks in your config files if their templates changed, and reports "up to
date" otherwise.

For the same reason, do not edit files in the clone unless you mean to change the
plugin: your edits take effect at the next start.

## Remove

```bash
claude plugin uninstall codex-review-loop@codex-review-loop
claude plugin marketplace remove codex-review-loop
```

Your clone stays where it is; delete it if you no longer want it. To remove the
rules that setup added, see the [main README's Uninstall section](../../README.md#uninstall).
