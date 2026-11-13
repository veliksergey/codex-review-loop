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
