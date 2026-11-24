# Round <N> triage: <repository>, <yyyy-mm-dd>

<!--
Written by Claude after each review round, kept at
~/.claude/codex-reviews/<repo>/<RUN>-round<N>-claude.md. The headings, the table
columns, the decision words, and the keys of the judge record are fixed, so that
rounds can be compared and counted. Never put secrets in this file.
-->

<scope and mode; the review model and effort and where each came from; the sandbox
line of the log header; Codex's exit code; the session id; whether the fingerprint
before and after the round was identical>

## Findings

| # | Finding | Reviewer label | Final label | Decision | Evidence | Proof |
|---|---|---|---|---|---|---|
| 1 | <the finding in one sentence, starting with (criterion N), (beyond request), or (handoff) when the reviewer gave one> | <P0, P1, P2, P3, or none> | <P0, P1, P2, or P3> | <one decision word> | <what you traced or reproduced, with repository-relative paths, and what you changed> | <the test and "fails before the fix, passes after", or the reason no test is possible> |

Write "None." in place of the table when the review reported no finding.

Reviewer label is the label Codex wrote; `none` marks a defect you found yourself.
Final label is the one you set from the scale in the review prompt.

Decision is exactly one of:

- `fixed`: valid, P0 to P2, and fixed in this round.
- `not fixed`: valid, P0 to P2, and left as it is, as in a `--report-only` run.
- `listed for the user`: valid, and P3.
- `rejected`: not valid. Evidence holds the code path, test output, or documentation
  that disproves it.
- `outside scope`: valid, but not part of this task.
- `disputed twice`: already recorded in `docs/reviews/decisions.md`.
- `escalated`: an override that the second look or the rebuttal contradicted and that
  you still hold, or one whose rebuttal failed. Not fixed and not recorded in
  `docs/reviews/decisions.md`: the user decides it.

## Overrides

| # | Override | Second look | Its answer | Rebuttal | The reviewer's answer |
|---|---|---|---|---|---|
| 1 | <rejected, or P3> | <not run, agreed, disagreed, or could not tell> | <the agent's verdict and severity, and the code it named> | <not run, withdrawn, maintained, or failed> | <what the rebuttal said of this finding, or why none ran> |

Write "None." in place of the table when no finding was overridden.

One row per finding that you rejected, or that Codex labeled P0 to P2 and you labeled
P3 without deciding it `outside scope` or `disputed twice`, before its second look,
numbered as in the findings table. Keep the row when the
second look or the rebuttal changed your decision; the findings table holds the
decision that stands. Override is what you decided before the second look. Second look
is `agreed`, `disagreed`, or `could not tell` by the table in step 6 of the skill, and
`not run` when the agent was not available. Rebuttal is `not run` for a finding that
gets none: one that Codex labeled P2 or P3, one moved to P3, one escalated after its
second look, and every finding of a `--report-only` run.

Below the table, one line for each finding that the round's rebuttal reported without
being asked, as the rebuttal wrote it.

## Requirement checklist

| Criterion | State | Verified by | Basis |
|---|---|---|---|
| 1 <the criterion in a few words> | <met, not met, fixed this round, or not verifiable> | <reviewer, implementer, or nobody> | <what shows it> |

Verified by names who verified the state the row records, not who looked at the
criterion. It is `reviewer` when this round's review says that it checked the
criterion as it now stands, by reading the code or by running something. A criterion
you changed after the review, such as one that is `fixed this round`, is in a state no
reviewer has seen: it is `implementer` when a test or check that you ran shows it, and
`nobody` otherwise, until a later review checks it. The same two words apply when the
review says that it could not check the criterion, or does not mention it.

In a run without a task file, write this line in place of the table: "No acceptance
criteria: no task file was used."

Stayed within the request: <yes, or what goes beyond it>

<in a run without a task file only: a section "## Decisions while fixing", one line
per decision with its reason>

## Judge record

```text
plugin=<the plugin's version, or unknown>
<every line that round-facts.sh printed for this round, unchanged>
web=<cached, live, or off>
tools=<default, or allowed>
fingerprint=<the four hashes of this round, separated by spaces>
```

<when the round ran a rebuttal only: a section "## Rebuttal judge record" with the
same keys in the same kind of block, for the rebuttal: the lines round-facts.sh
printed for its log, and its own fingerprint>
