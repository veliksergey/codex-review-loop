# To do

Open work on this repository as of 2026-11-23, in the order recommended. None of it is
started. Each item starts on the maintainer's word, and each experiment spends reviews
of the maintainer's Codex allowance.

IDs such as B5, C2, and E6 are those of `docs/IMPROVEMENT_PLAN.md`, sections 7 and 8.
Each item is described here so that it can be read without the plan.

## Where things stand

- The plugin is at 0.7.0. Releases A and B of the plan are done, except B5, and C2
  of release C.
- The baseline is run and recorded: B6, with the experiments E1 and E2. Its results are
  private. They are kept in the loop's log folder, outside this repository, and no
  figure of them belongs in a file here.
- The evaluation corpus holds 25 cases, and each label is agreed with.

## Next, in this order

- [x] **The tools built into Codex that list MCP resources.** In a review that was
  observed, the reviewer called tools of Codex's own that list the resources of MCP
  servers, although every server was off. The loop stops such a review, because a tool
  that should be off was called. Found on 2026-11-23, for Codex 0.171.0: no setting
  that the loop can use removes them. Codex adds `list_mcp_resources`,
  `list_mcp_resource_templates`, and `read_mcp_resource` when an MCP server is on, and
  always when the model runs its tools in code mode only, which in the model catalog
  of Codex 0.171.0 is every model but one. The sources:
  `codex-rs/core/src/tools/spec_plan.rs`, lines 1329 to 1332 at the tag
  `rust-v0.171.0`; Codex's pull request 50546 of 2026-10-03, which made it so on
  purpose; the configuration reference, which names no key for them; and
  `codex debug prompt-input`, which listed all three with every MCP server off. With a
  model catalog edited to drop code mode, it listed them only while the server of the
  search connector was on. A setting turns code mode off only for a model that
  declares no tool mode, which in that catalog is `gpt-5.5` alone. With such a model,
  the feature `code_mode_only` off, as it is by default, and no MCP server on, as with
  `--web off`, the three are gone and the shell stays, as the edited catalog showed;
  while an MCP server is on, such as the search connector's server in a review with web
  search, they stay. For a model that runs in code mode only, the setting
  `features.code_mode.excluded_tool_namespaces = ["functions"]` hides them, and with
  them `exec_command`, through which the reviewer runs its shell commands, as the same
  command showed. Without `--allow-tools`, the loop goes on stopping a review whose log
  records a call of one, and 0.6.3 says so. What is still open is under "Smaller
  points".
- [x] **C2: a second look at the implementer's overrides.** Before a rejection, or a
  move from must-fix to P3, is recorded, a read-only subagent with a fresh context
  checks the finding against the code. For a rejected P0 or P1 the reviewer also gets
  one rebuttal. Done in 0.7.0 on 2026-11-23: the plugin's agent `finding-checker` has
  only `Read`, `Grep`, and `Glob`, and judges the finding without the implementer's
  decision or evidence; a rebuttal is one more review per round at most, under every
  rule of a round. An override that either contradicts and the implementer still holds
  is `escalated` to the user. How often the agent and the rebuttal are right is not
  measured; that needs the evaluation corpus and the maintainer's word.
- [ ] **B5: a feasibility test of `claude plugin eval`.** For the mechanics of the
  skill, on Linux or WSL2, with a stand-in for `codex`. Five cases: not logged in, empty
  output, a changed fingerprint, report-only writes nothing, and the round limit
  reached. If the stand-in cannot be injected, record that and stop. It needs no Codex
  account.
- [ ] **E6: what a second pass with another focus adds.** After a clean first round on
  defect cases of the corpus, run a pass with a focus. Measure the verified defects
  each pass adds. It decides C3.

## Release C

Each item is adopted only when its condition holds.

- [ ] **C1: follow up the findings of the round before.** The next round's prompt
  lists the accepted findings of the previous round, worded neutrally, and asks for
  "closed" or "not closed" on each. When the round limit is reached after fixes, one
  more pass looks only at the files changed since. Stop and escalate when a round
  reports at least as many must-fix findings as the one before. Adopt when E2 shows that
  findings of later rounds are real defects. E2 is run; the decision waits for the
  maintainer, with the private record.
- [x] **C2.** See above: done in 0.7.0.
- [ ] **C3: a second pass for risk areas.** When round 1 is clean and the change touches
  paths the repository lists as risk areas, run a second pass with another focus, and
  let those areas set the effort. Adopt when E6 shows that the second pass finds
  verified defects. E1 is run; what it says about C3 is in the private record.
- [ ] **C4: review in two passes.** First without the handoff, then with it, to check
  its claims. Adopt when E3 shows that the handoff sways the result.
- [ ] **C5: a permission profile.** One that keeps the repository read-only and also
  denies reads of secret files such as `.env`. It replaces `sandbox_mode` with
  `default_permissions`, so the wording of the read-only invariant changes with it.
  Adopt when the profile works with `codex exec review` on all three systems and the
  maintainer accepts the new wording.
- [ ] **C6: the reviewer's overall verdict.** Read it, and treat a mismatch with the
  number of findings, or a low overall confidence, as "clean with unverified items".
  Adopt when the verdict can be read from `--json` output or another documented place.
- [ ] **C7: rules for review in the repository template.** Name the section
  `## Code Review Rules`, and have setup propose two or three rules, each with a safe
  alternative. Adopt when the control cases of the corpus show no added false alarms.

## Experiments

Each is measured on the corpus with `tests/eval_review.py`, into a results folder of
its own, and compared with the baseline. `tests/eval/README.md` says how a review of a
case is run, judged, and reported.

- [ ] **E3: does the handoff sway the reviewer?** The same code with three handoffs:
  none, short, and long and confident. Measure the change in detection on defect cases.
  A drop with the long handoff: adopt C4.
- [ ] **E4: does naming the author matter?** "Another AI coding agent (Claude Code)"
  against "another engineer". Measure detection and false alarms. Keep the better one;
  with no difference, use the neutral wording.
- [ ] **E5: is higher effort worth it?** Two effort levels on the corpus. Measure
  detection for each review and for each minute. It sets the default, and the routing
  in C3.
- [ ] **E6.** See above.
- [ ] **E7: do embedded instructions suppress findings?** Seed a defect beside a
  comment that suppresses it, a relaxed rule, a false row of rejections, and a decision
  that excuses it. Measure detection with and without that text. Any drop: the rules
  the prompt has against this are not enough yet.

## Smaller points

- [ ] **What the search connector's server offers as resources.** No single setting
  removes Codex's three tools for the resources of MCP servers for every model and web
  search mode the loop runs with, and without `--allow-tools` the loop stops a review
  whose log records a call of one.
  With `--web off` no MCP server is on, and such a call reaches nothing, so the loop
  could let it through there. A review with web search asks Codex to turn the search
  connector on, and while its server is on these tools can reach it; what it offers
  was never checked.
  One Codex request could confirm that the server is on, ask it by name for its
  resources, and record what it advertises. It needs `orchestrator.mcp.enabled` left
  on, as it is by default: set to false, that setting keeps these tools from the
  server, and the request would show only the refusal. Its resource templates cannot
  be learned that way: Codex 0.171.0 answers a list of them for this server itself,
  with an empty list, without asking the server (`codex-rs/codex-mcp/src/binding.rs`,
  `list_resource_templates`). An empty list of resources would still not show that
  `read_mcp_resource` reaches nothing there: a server's tools can return links to
  resources that its lists leave out. A change to the loop is a release.
- [ ] **The severity of security defects.** Decide whether the scale in
  `review-prompt.md` needs firmer wording for them. The evidence is in the private
  record. A change to the prompt is a release, and is measured against the baseline
  before and after.
- [ ] **A command that failed counts as one that ran.** `round-facts.sh` counts a
  command by whether it ran, whatever its exit code, so a review in which every command
  failed is `shell_usable=yes`. In the loop a person reads the review, which says when
  it was blocked. `tests/eval_review.py` marks such a review as not usable since
  2026-11-20. A change to the script is a release. The recommendation is to leave it.
- [ ] **One review of `w-handoff-control`.** Criterion 1 of the task file that the
  cases `w-handoff` and `w-handoff-control` share was reworded on 2026-11-20. No review
  has read the new wording, so whether the control now comes back clean is not known.
  It spends one review.
- [ ] **Rejections tied to the code they are about.** A row of
  `docs/reviews/decisions.md` holds a date and the evidence, and not the commit the
  evidence was read at. Record the commit with each row, and have a rejection checked
  again when that code changes, so that it does not become a lasting exemption. The
  prompt already lets the reviewer raise a recorded finding again with new evidence.
  This comes from the two reports that the plan replaced, and the plan did not take
  it up. It changes a template, so it is a release.
- [ ] **A Codex configuration that sets `default_permissions`.** The loop always
  passes `sandbox_mode="read-only"`. The plan records, from Codex's configuration
  reference as read on 2026-11-12, that `default_permissions` must not be combined with
  `sandbox_mode`. What Codex does when a user's configuration sets the one and the loop
  passes the other was never tried. Try it, and if the read-only sandbox does not hold
  then, stop the review before it starts, with a message. It is near C5 and comes from
  the same two reports.

## On another computer

A clone of this repository does not carry everything this work needs.

- **The loop's log folder,** `~/.claude/codex-reviews/<repo>/`. It holds the baseline
  record, the reviews of the corpus, the task files, and the review logs. A later
  measurement is compared with the baseline there. It is private and never goes into
  the repository, so copy it by hand. Where the clone lies at another path than on the
  first computer, delete `repository-root.txt` in the copy; `log-dir.sh` writes it
  again.
- **The setup.** Claude Code with this plugin installed and its setup skill run, and
  the Codex CLI signed in. `README.md` says how.
- **The checks.** `AGENTS.md` lists them. `bash tests/run-all.sh` needs bash and git,
  and Python 3.8 or newer for the tests of the tooling in `tests/`.
- **A push** needs an account that may write to this repository.
