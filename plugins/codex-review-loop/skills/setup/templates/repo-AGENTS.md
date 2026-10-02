# AGENTS.md

Instructions for AI coding agents working in this repository. Claude Code reads it
to know which checks to run; Codex reads it before every review.

## Roles

Claude Code implements. Codex reviews read-only. The user decides and commits.

## Commands

The checks CI runs. Claude runs them before each review round and after each fix;
Codex runs the read-only ones during review. Write `none` for a check this
repository does not have.

| Check | Command |
|---|---|
| Typecheck | {{TYPECHECK}} |
| Lint | {{LINT}} |
| Test | {{TEST}} |
| Build | {{BUILD}} |

## Branches

{{BRANCHES}}

## Invariants

Rules a change must never break, for example: every endpoint checks authorization
on the server; every lookup is scoped to the caller's tenant; public exports keep
their shape. Replace this paragraph with this repository's rules.

## Review decisions

Rejected review findings and their evidence: `docs/reviews/decisions.md`.
