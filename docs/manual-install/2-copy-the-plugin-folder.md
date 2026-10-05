# Path 2: copy the plugin folder

You copy the reviewed plugin folder into Claude Code's `skills` folder. Claude Code
recognizes a folder there that has a plugin manifest and loads it as a plugin, with
no marketplace involved.

## Install

1. Clone the repository and review it, as described in
   [Review it in about ten minutes](README.md#review-it-in-about-ten-minutes).

2. If you installed the plugin from GitHub earlier, uninstall it first. An installed
   marketplace plugin with the same name takes precedence, and Claude Code would not
   load your copy:

   ```bash
   claude plugin uninstall codex-review-loop@codex-review-loop
   claude plugin marketplace remove codex-review-loop
   ```

3. Copy the plugin folder, not the whole repository. Run this from inside your
   clone, where the review steps leave you:

   macOS, Linux, or Git Bash on Windows:

   ```bash
   mkdir -p ~/.claude/skills
   cp -R plugins/codex-review-loop ~/.claude/skills/codex-review-loop
   ```

   Windows PowerShell:

   ```powershell
   New-Item -ItemType Directory -Force "$HOME\.claude\skills" | Out-Null
   Copy-Item -Recurse plugins\codex-review-loop "$HOME\.claude\skills\codex-review-loop"
   ```

   The copy must include the hidden `.claude-plugin` folder; that is what makes
   Claude Code treat it as a plugin. Both commands above copy it.

4. Restart Claude Code.

5. Continue with steps 2 to 4 of the [main README's Install section](../../README.md#install):
   the setup command, preparing a repository, and a first review.

## Check that it worked

```bash
claude plugin list
```

Expect an entry `codex-review-loop@skills-dir` with `Status: ✔ loaded` and the
version you copied. `claude plugin details codex-review-loop@skills-dir` lists
`Skills (2)  codex-loop, setup` and `Hooks (0)`.

## Take a new version

Update your clone and read the changes (see
[path 1](1-from-your-own-clone.md#take-a-new-version) for the commands). Then replace
the folder, removing the old one first; copying onto an existing folder would put
the new copy inside it:

```bash
rm -rf ~/.claude/skills/codex-review-loop
cp -R plugins/codex-review-loop ~/.claude/skills/codex-review-loop
```

```powershell
Remove-Item -Recurse -Force "$HOME\.claude\skills\codex-review-loop"
Copy-Item -Recurse plugins\codex-review-loop "$HOME\.claude\skills\codex-review-loop"
```

Restart Claude Code and run `/codex-review-loop:setup`, which updates the rule
blocks in your config files if their templates changed.

## Remove

Delete the folder:

```bash
rm -rf ~/.claude/skills/codex-review-loop
```

```powershell
Remove-Item -Recurse -Force "$HOME\.claude\skills\codex-review-loop"
```

To remove the rules that setup added, see the
[main README's Uninstall section](../../README.md#uninstall).
