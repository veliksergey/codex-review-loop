<!-- codex-review-loop:begin claude-rules -->
# Claude Code responsibilities

Claude Code is the implementer. Codex is the independent reviewer. The user's
explicit request overrides both defaults.

## Working rules

- Follow the repository's own `AGENTS.md` and `CLAUDE.md`.
- Open a repository root as the working directory, not a parent folder that holds
  several repositories, so the right `AGENTS.md` and `CLAUDE.md` load.
- Confirm the branch before editing. Branch policy is per repository and is
  stated in that repository's `AGENTS.md`; do not assume a branch exists.
- Run the repository's documented checks that actually exist before calling work
  complete. Report every skipped or failed check and why.
- Keep changes focused on the requested outcome and preserve unrelated work.
- Keep code comments short: one to three lines saying what a non-obvious line does or
  guards. Put the story behind a decision in the task file, the review log, or a
  repository decision document, never in code.

## Responding to Codex findings

- Treat each finding as a testable claim. Reproduce or trace it before editing.
- Fix valid findings in severity order and add the regression coverage.
- Reject a finding only with concrete code paths, test output, or primary
  documentation — never preference or intent.
- Record each rejected finding and its evidence in `docs/reviews/decisions.md`
  so the next review does not re-litigate it.
- After two rounds of disagreement on the same finding, stop and escalate to the
  user. CI, not an agent, decides whether a change is mergeable.

## Codex review loop

- After completing an implementation task in a git repository, and after the
  repository's documented checks pass, run the `codex-loop` skill before
  reporting completion. Skip it only when the user says to skip review or the
  change is documentation-only.
- Task file: at the start of an implementation task in a git repository, write
  `~/.claude/codex-reviews/<repo>/task.md`, where `<repo>` is the folder name of the
  repository root. Sections, in order: `## Request (verbatim)` with the user's
  words copied exactly, `## Acceptance criteria` numbered with one testable behavior
  each, `## Out of scope`, `## Decisions during implementation`, and `## Handoff`
  with files, tests and what each proves, assumptions, check results, and risks.
  The `codex-loop` skill folder holds the full template. Show the criteria to the
  user before coding starts. Append each implementation decision with its reason as
  it is made. Complete the Handoff section before running the loop. The loop sends
  the file to Codex, which checks the change against it.
- Default scope is all uncommitted changes. Use the paths, `--base`, or
  `--focus` the user gives; a folder or file named in the request is a scope.
- Fix policy: verify every finding first. Fix valid P0-P2 findings with a
  regression test. List valid P3 findings for the user's decision and do not fix
  them unasked. Record each rejected finding with evidence in
  `docs/reviews/decisions.md`.
- At most 3 rounds per task. Stop early when a round reports no P0-P2 findings,
  when a round changed no code, or when the same finding is disputed a second
  time. Then hand the rest to the user.
- Codex runs read-only; only Claude edits. The loop never commits or pushes.
- Review logs live in `~/.claude/codex-reviews/<repo>/`, never inside the
  repository.

## Handoff

Finish with: files changed, commands run and their exact results, tests added
and what each proves, assumptions made, and remaining risks.
<!-- codex-review-loop:end claude-rules -->
