# Review decisions

One row per Codex finding that was **rejected**, so the next review does not
re-litigate it. Accepted findings need no row — the fix and its regression test
are the record.

Add a row only with concrete evidence: a code path, test output, or primary
documentation. "We meant it that way" is not evidence.

| Date | Finding | Severity claimed | Decision | Evidence |
|---|---|---|---|---|
| 2026-11-23 | The second look must not receive text that a finding quotes from the implementer, such as a handoff claim, a decision, or a row of this file: redact it before the call, or call the second look not run. | P1 | Rejected by the user: the finding goes to the agent as Codex wrote it, without its label, and the agent gives quoted implementer text no weight. | `review-prompt.md`, `<output_contract>`: "For a handoff finding, name what you compared the claim against", so the quoted claim is what the agent must check. `SKILL.md` step 6, "Add nothing else": a redaction is made by the implementer, who wants to override the finding, and would let it reshape the claim the agent judges. `agents/finding-checker.md`, "How to check": quoted implementer text is "what the reviewer disputes" and gets "no weight as evidence". |
| 2026-11-23 | In branch mode, a rebuttal must also check the reviewed commit, `HEAD`, when a finding is about the committed diff: a fix that is staged but not committed can hide a defect that a commit of the branch still holds. | P1 | Rejected: a review in branch mode judges the branch's commits and the uncommitted changes as one change, where that change ends: on disk, or in the staged version for a finding about what is staged. A defect that a commit adds and an uncommitted change removes is not in the change. | `SKILL.md` step 1, branch mode: "The scope block asks for the committed changes since the merge base plus the uncommitted changes, so fixes can stay uncommitted between rounds." The branch scope of step 4: "Target: all changes on the current branch since `<base>`, its merge base with `<ref>`, plus any uncommitted changes", and "Read the whole of each changed file", which is the file on disk. The loop's own fixes stay uncommitted in this mode, so a rebuttal told to check `HEAD` would maintain a finding that an earlier round fixed, and escalate a correct rejection. |
| 2026-11-24 | The second look should get the committed text only of the instruction files that govern the files a finding is about, not of every `AGENTS.md` or `CLAUDE.md` the change edits, so that an unrelated folder's file does not reach the agent. | P2 | Rejected by the user: the agent gets the committed version of each instruction file the change edits, as built. | `SKILL.md` step 6, the second look's prompt: "for each listed `AGENTS.md`, `AGENTS.override.md`, or `CLAUDE.md` that the change does not add, `Committed version of <path>:`", so that the agent judges by the committed rules, not by the change's own version on disk. `agents/finding-checker.md`, "How to check": "The rules in the repository's `AGENTS.md` say what its code must do; apply them when the finding is about one." The agent runs in Claude Code on the user's computer, as the main session does, so the committed text of the user's own repository reaches no new party. |

If the same finding is raised a third time, that is a signal the repository's
`AGENTS.md` is missing a fact, not that the reviewer is wrong. Fix the
instructions instead of adding another row.
