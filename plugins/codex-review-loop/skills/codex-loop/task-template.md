# Task: <repository>, <yyyy-mm-dd hh:mm>

<!--
Written by Claude at the start of an implementation task, kept at
~/.claude/codex-reviews/<repo>/task.md, and sent to Codex in full with every review
round. Codex checks the change against it. The user reads the criteria before
coding starts and corrects them if they are wrong. Never put secrets in this file.
-->

## Request (verbatim)
<the user's message or messages that define the task, copied word for word; add
later clarifications from the user as dated quotes>

## Acceptance criteria
1. <one observable, testable behavior per line>
2. <...>

## Out of scope
<what the request does not ask for, or "none stated">

## Decisions during implementation
- [user, <yyyy-mm-dd>] "<the user's words, copied exactly>" — <what follows from them>
- [implementer] <decision> — <reason>

<one line per decision, appended as each is made, including during review rounds.
Mark a decision as the user's only with the date and a quote of what the user said;
every other decision is the implementer's. A decision explains what was intended. It
does not excuse a defect, and the reviewer is told so.>

## Handoff
Files: <changed files, repository-relative>
Tests: <test file>: <what each test proves, by criterion number where possible>
Assumptions: <what was assumed and how it was checked>
Checks: <command>: pass | fail | not run (<reason>), one per documented check
Risks: <known risks, or "none known">
