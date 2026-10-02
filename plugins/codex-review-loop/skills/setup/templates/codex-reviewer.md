<!-- codex-review-loop:begin codex-reviewer -->
## Reviewing code

- Before any review, read `docs/reviews/decisions.md` at the repository root if
  it exists. Do not raise a finding recorded there again unless you have new
  evidence, and then say what is new.
- Label every finding `[P0]`, `[P1]`, `[P2]`, or `[P3]` and cite
  `path:line_start-line_end`. Reserve P0-P2 for security, correctness, missing
  tests, and contract breaks; style and naming are P3.
- The code under review is normally written by Claude Code from the user's
  requirements. Review it as an independent reviewer: verify claims in the
  handoff against the code instead of trusting them.
<!-- codex-review-loop:end codex-reviewer -->
