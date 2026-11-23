# Review loop: consolidated assessment and improvement plan

Prepared on **2026-11-12** against plugin **0.2.4**, `main` at `487c478`. The
decisions recorded on 2026-11-13 are in section 9 and are built into the plan.

This report answers two questions: how well the plugin matches the AI-as-judge
guidance in the supplied book excerpt, and what would
make the review loop more accurate. It combines the excerpt, two earlier reports
of the same date (an assessment of the loop against the excerpt, and a study of
current review practice), and independent research into current practice and into
how the two tools behave. Section 7 is the plan.

The two earlier reports are not kept in this repository. They were retired on
2026-11-23, once this plan had taken up each of their items; section 5 lists the
items and where each landed. The excerpt is not kept here either: it is text from a
published book. A citation such as `excerpt:1-34` names lines of the maintainer's
copy.

Terms used throughout: the **implementer** is Claude Code and the **reviewer** is
Codex. A **run** is one invocation of the loop; a **round** is one Codex review
inside a run. A **must-fix** finding is one labeled P0, P1, or P2. Where a
citation gives only a file name, `SKILL.md`, `review-prompt.md`, and
`task-template.md` are the files in `plugins/codex-review-loop/skills/codex-loop/`.

## Summary

**The design matches the excerpt where it matters. Its two weaknesses are that it
reports more certainty than its evidence supports, and that its reviewer can do
more than the documentation says.**

- **Alignment is strong on the fundamentals.** The loop states the task, writes
  the criteria down, uses categories instead of scores, demands evidence, runs
  exact checks first, and leaves the decision to a person. The requirement check,
  which compares the change with numbered criteria, is its most distinctive part.
- **A clean result is weaker than it reads.** The reviewer usually cannot run
  tests in its read-only sandbox, and a criterion it could not verify is
  mentioned only in its summary. The loop has no verdict between clean and open
  findings. Current benchmarks put single-pass detection of known defects between
  one third and three quarters.
- **The round cap can leave the last fixes unreviewed.** The guide says so, but
  the skill has no verdict for it. Research on repeated fix rounds shows they are
  not safer by default.
- **The reviewer is not confined to the read-only shell.** OpenAI's documentation
  says the sandbox limits commands, and that web search, connectors, and MCP
  servers are outside it. The loop neither limits nor reports their use.
- **The implementer is the only check on findings about its own work.** It can
  reject a finding or lower its severity, and a rejection it has just written
  binds the reviewer in the next round.
- **The privacy statements name less than can leave the computer.**
- **The earlier reports are right about the main gap,** which is that accuracy is
  unmeasured. I confirm most of their findings and change three (section 5).

**Recommended order.** First, report honestly, limit the reviewer's tools, and
close two paths that can suppress findings (Release A). Second, make the loop
measurable, using bug fixes in this repository's history as labeled test cases
(Release B). Third, add verification passes only where the measurements justify
their cost (Release C).

## 1. Evidence used

| Source | What it contributed | Limits |
|---|---|---|
| The excerpt, 429 lines | The principles compared in section 2. | Its statistics describe 2023 models. They are not evidence about this plugin. |
| Every file under `plugins/`, `tests/`, and `docs/` | The behavior assessed in sections 2 and 4. | Read statically. |
| The behavior of the two tools | The reviewer's built-in guidelines, the shape of its result, the scope of its read-only policy, and the options the review command advertises. | Observed on 2026-11-12 on one installation. Undocumented details can change with any CLI release. |
| Official documentation and research | Sections 2, 5, and 6, each opened on 2026-11-12. | Several papers are preprints. Vendor figures are self-reported. |

**What this report does not contain.** Under decision 4 it has no usage figures,
no numbers derived from anyone's review logs, and no details of anyone's
computer. The priorities were also informed by a private analysis of the
maintainer's own review logs. No figure from that analysis appears here, and each
finding below stands on the sources it cites.

**What nobody has measured.** There are no human labels, so nothing yet measures
whether the reviewer's findings are correct or how many defects it misses.
Release B exists to change that.

## 2. Alignment with the excerpt

The plugin does one of the three things the excerpt describes: it evaluates a
single result against a written specification
(excerpt:1-34). The specification is the task
file. I agree with the first report that pairwise ranking does not answer this
plugin's question; section 8 notes the one place where comparison is useful.

| Principle in the excerpt | What the plugin does | Assessment |
|---|---|---|
| State the task, the criteria, and the scoring system (48-62). | Verbatim request, numbered criteria, and handoff go to the reviewer (`task-template.md:10-30`, `review-prompt.md:33-49`). | **Strong.** |
| Prefer classification to numbers; narrow ranges work better (63-68). | Four severity classes and three criterion states (`review-prompt.md:36-38`, `75-84`). | **Strong in form.** Two definitions of the classes reach the reviewer; see F9. |
| Give examples for each grade (69-100). | None. | **Gap.** Add examples only after measuring them (A6, E2). |
| A judge is model, prompt, and settings; change one and it is a different judge (104-106). | Saves each prompt; reports model and effort (`SKILL.md:103-114`, `192-198`). | **Partial.** The Codex CLI updates on its own schedule and brings the built-in guidelines and the tools with it. Neither is recorded; see F12. |
| Results vary between runs, and consistency is not accuracy (115-130). | Treats the reviewer's severity as a proposal (`SKILL.md:249-254`). | **Gap.** Variation is acknowledged for labels only, and never measured (E1). |
| Criteria drift over time and across teams; do not trust a judge whose model and prompt you cannot see (132-165). | Prompt and task file are archived per run. | **Partial.** The criteria are written by the implementer and can change after the user has seen them; see F16. |
| Cost and latency: use stronger judges selectively, spot-check (166-191). | `--model`, `--effort`, `--rounds`, `--focus`. | **Adequate controls, no routing.** Effort is chosen by hand; see C3. |
| Self-bias (197-202). | A reviewer from another vendor; handoff statements are claims (`review-prompt.md:47-48`). | **Half addressed.** The review is independent; the triage is not; see F5. |
| First-position bias (203-208). | Not applicable: one candidate, no ordering. | **Not applicable.** |
| Verbosity bias (209-217). | Asks for one strong finding over several weak ones (`review-prompt.md:107`). | **Untested.** The task file grows each round as decisions are appended (`SKILL.md:291-292`); see E3. |
| Privacy when a proprietary judge reads your data (218-222). | README and plugin README disclose what is sent. | **Understated.** See F2. |
| Supplement AI judges with exact methods and human evaluation (223-226). | Checks must pass first; fixes need a regression test; the user commits (`SKILL.md:50-53`, `258`, `324-325`). | **Strong workflow,** but no human-labeled calibration, and the reviewer often cannot run the tests itself (`docs/GUIDE.md:451-453`). |
| Stronger, weaker, or same-model judges; specialized judges (227-315). | Model and effort are configurable. | **Unmeasured.** See E5. |

### Where the excerpt needs updating

The excerpt reports results from 2023. Six later results change how its advice
applies to this plugin. All were opened on 2026-11-12.

- **Its example figure is about answer order, not repeated runs.** The excerpt
  cites a rise in consistency from 65% to 77.5% when examples are added
  (excerpt:122-125). In
  [the source paper](https://arxiv.org/abs/2306.05685), "Consistency is the
  percentage of cases where a judge gives consistent results when swapping the
  order of two assistants", and the judge with examples "performs similarly" to
  the one without when compared with humans. Examples are not a demonstrated fix
  for the variation this loop faces.
- **Variation between repeated runs has since been measured.**
  [Rating Roulette](https://arxiv.org/abs/2510.27106) (EMNLP 2025) reports that
  "LLM judges have low intra-rater reliability in their assigned scores across
  different runs".
- **The bias list is longer, and the narrative biases matter most here.**
  [CALM](https://arxiv.org/abs/2410.02736) identifies "12 key potential biases".
  One is that "Telling the model that this is a refined result will lead to
  different evaluations". [A study to appear at ICSE 2027](https://arxiv.org/abs/2603.18740)
  crafted pull-request descriptions to bias security review and succeeded "in
  32/33 (97%) cases", while crude templates were "ineffective and may even
  backfire". This loop gives the reviewer the implementer's handoff in every
  round, and tells it in later rounds what was fixed.
- **Labels move judges.** [A study in Findings of EMNLP 2026](https://aclanthology.org/2026.findings-emnlp.1571/)
  found that "Under blind evaluation, self-preference disappears", while judges
  "inflate scores for self-labeled selections and deflate those for other-labeled
  ones". The plugin's prompt names the author as another AI agent
  (`review-prompt.md:1-7`).
- **Validators are agreeable.** [A study of LLM validators of code feedback](https://arxiv.org/abs/2510.11822)
  measured a "True Positive Rate 96%" and a "True Negative Rate <25%": they
  confirmed valid items and failed to reject invalid ones. The implementer's
  acceptance of a finding is therefore not proof that the finding was right.
- **Vendors tune reviewers toward precision.** OpenAI [describes](https://alignment.openai.com/scaling-code-verification/)
  accepting "modestly reduced recall in exchange for high signal quality and
  developer trust", and warns that "Teams could start treating a clean review as
  a guarantee of safety rather than as one layer of defense."

## 3. What the loop's own records can show

The loop already saves, outside the repository, everything needed to measure how
it behaves for a given user: the prompt, the review, the log, and the triage
notes of every round (`SKILL.md:103-114`). No command reads them today.

| Question | Measure | Read from |
|---|---|---|
| Does a clean first round end most runs? | Rounds per run; share of runs whose first round has no must-fix finding. | Review files |
| Do rounds converge? | Must-fix findings by round; how often the round after a round with findings reports more; how often a run that used every round still had findings in the last one. | Review files |
| Which checks produce findings? | Findings by label, and by tag: criterion, handoff, beyond request. | Review files |
| How does triage treat the reviewer? | Accepted, rejected, and deferred findings; the reviewer's label against the final label. | Triage notes |
| What did the reviewer use? | Shell commands started and failed; tool calls by server; the sandbox line; the CLI version. | Logs |
| Does a clean round say what it could not verify? | Whether the summary names something not run or not verifiable. | Review files |
| What does a round cost? | Duration per round. | File times |

Such figures describe one person's work. They belong in that person's log folder
and never in this repository (decision 4). B1 and B2 make them easy to produce
for any user.

One property of the reviewer's output is not personal and matters for the plan.
The review ends in a structured result that the loop does not read: a JSON object
with a confidence score and priority for each finding, an overall verdict of
"patch is correct" or "patch is incorrect", and an overall confidence. OpenAI's
[cookbook](https://developers.openai.com/cookbook/examples/codex/build_code_review_with_codex_sdk)
shows the same fields, and a review session observed on 2026-11-12 ended in that
shape. Codex renders it to the text the loop saves. Whether the stated confidence
separates right findings from wrong ones is unknown.

## 4. Findings

P2 marks a correctness, safety, or disclosure gap with a concrete path to it. P3
marks an improvement. "Observed" means seen in the behavior of the tools on
2026-11-12. None of the P2 findings is a report of observed harm.

**F1. [P2] The reviewer's tool surface is wider than the read-only guarantee, and
the loop neither limits nor reports it.**
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:200-221`, `README.md:157-162`.
The loop forces `sandbox_mode="read-only"` and states that for files git ignores
"the read-only sandbox is the guarantee". OpenAI's security documentation
describes the sandbox as a limit on commands the model runs, and says the command
network proxy "does not filter web search, app or connector tool calls, MCP server
connections". Connectors are on by default, and MCP servers come from the user's
own Codex configuration. The loop's check of each round reads only the log header
and one older Windows error, so a round in which the sandboxed shell never
started, or in which the reviewer worked through other tools, is not reported.
Whether such tools can write files was not tested. Fix: A2 reports the tools used
and stops when the sandboxed shell is unavailable; A11 turns the other tools off.

**F2. [P2] The privacy statements name less than what can leave the computer.**
`plugins/codex-review-loop/README.md:39-41`, `51-55`; `README.md:173-178`.
Both say the only data sent is the code under review and the task file. The
review prompt itself allows web search (`review-prompt.md:67-70`), and a search
is a request the reviewer composes. The observed read-only policy grants read
access from the root of the file system, not only to the repository, so the
reviewer can read, and therefore send, files outside the change. `AGENTS.md`
requires the plugin README to describe what the plugin sends. Fix: A3.

**F3. [P2] "Clean" has no weaker neighbour.**
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:295-298`, `312`;
`review-prompt.md:99-100`; `docs/GUIDE.md:451-453`.
The verdicts are clean, stopped with open findings, and stopped on an error. A
criterion the reviewer could not verify is stated only in its summary. The guide
says the reviewer often cannot run the tests. A run in that state, and a run
whose last fixes were never reviewed, both end as clean. This confirms the first
report's finding 3. Fix: A1 adds the missing verdicts; C6 would add the
reviewer's own verdict as a signal.

**F4. [P2] The round cap can leave the last fixes unreviewed, and a finding that
is not repeated counts as fixed.**
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:25`, `295-298`;
`docs/GUIDE.md:461-462`.
The guide states the limit and says the final report mentions it, but the skill's
list of verdicts has no entry for it. A fix is new code, and it is the one kind
of change the loop can ship without review. Each round is also a fresh review
that is never asked whether the earlier findings are closed, so their absence
from the next review is taken as proof, although reviewers do not report the same
things on every run (section 2). Fix: A1 names the state; C1 adds a targeted
pass.

**F5. [P2] The implementer is the only check on findings about its own work.**
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:247-262`;
`review-prompt.md:15-16`, `27-29`.
The implementer can reject a finding or move it below the must-fix line. A
rejection is written to `docs/reviews/decisions.md`. The reviewer is told to treat
that file as bookkeeping, not to review it, and not to raise a recorded finding
again without new evidence. An uncommitted row written minutes earlier by the
implementer therefore binds the reviewer in the next round. When nothing else was
fixed, the loop stops and the reviewer never sees the rejection. Section 2 cites
research in which model validators agreed far more readily than they objected,
and section 6 cites research on leniency toward one's own work. Fix: A8 lists
every override for the user; C2 adds an independent check.

**F6. [P2] A documented decision is exempt from review.**
`plugins/codex-review-loop/skills/codex-loop/review-prompt.md:45-48`;
`task-template.md:21-23`.
The prompt says decisions in the task file are intentional, must not be flagged
as mistakes, and may be flagged only when they contradict the request or a
criterion. The same section calls the task file's statements claims to verify.
Decisions are written by the implementer. A decision that creates a security or
data-loss defect outside the listed criteria is therefore excluded by
instruction. No instance was searched for or observed. Fix: A4.

**F7. [P2] The change under review can carry the reviewer's instructions.**
`plugins/codex-review-loop/skills/codex-loop/review-prompt.md:15-16`, `24-29`.
The reviewer's built-in guidelines, observed in a review session, tell it to
apply project instruction files in the order `AGENTS.override.md`, `AGENTS.md`,
then fallbacks. The plugin's prompt tells it to read `AGENTS.md` and the
decisions file first. When a change edits one of those files, the edited text
governs the review of that change. Claude's managed Code Review avoids this by
reading its instruction file "from the base or default branch and never from the
pull request's own changes". This makes the second report's item 3 concrete.
Fix: A5.

**F8. [P2] Setup changes settings for every Codex session, and describes them as
review defaults.** `plugins/codex-review-loop/skills/setup/templates/codex-config.toml:1-7`;
`plugins/codex-review-loop/skills/setup/SKILL.md:114-115`, `143-144`;
`docs/GUIDE.md:167-169`.
The block sets three top-level keys. `review_model` applies to reviews only.
`model_reasoning_effort` and `web_search` apply to every session. The template
writes `web_search = "live"`, which the configuration reference describes as
"unrestricted live retrieval"; the default is `cached`, "an OpenAI-maintained
index without external web access". The user approves the exact lines, but the
description says they are for the reviewer. Fix: A9.

**F9. [P3] Two severity scales reach the reviewer.**
`plugins/codex-review-loop/skills/codex-loop/review-prompt.md:75-84`.
The built-in guidelines define P0 as "Only use for universal issues that do not
depend on any assumptions about the inputs", P1 as "Urgent", and P2 as "Normal.
To be fixed eventually". The plugin defines P0 as an exploitable flaw or data
loss, which usually does depend on an input. The guidelines say more specific
instructions override them, but the plugin's prompt never says its scale replaces
theirs. Which definition the reviewer follows has not been measured. Fix: A6, E2.

**F10. [P3] Audit mode works against two built-in rules.**
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:63-69`, `158-165`.
The built-in guidelines say "pre-existing bugs should not be flagged" and that a
finding's location "should overlap with the diff". An audit has no diff and looks
only for existing defects. The scope text for paths mode implies an override but
never states it. Fix: A7.

**F11. [P3] Precision is filtered twice and recall is helped by nothing.**
`plugins/codex-review-loop/skills/codex-loop/review-prompt.md:107`.
The built-in guidelines say to prefer no findings unless one is something "a
person would definitely love to see and fix". The plugin adds "Prefer one strong
finding over several weak ones". The implementer then verifies every finding. So
the pipeline has two filters against false alarms and one look for defects.
OpenAI states that its reviewer was tuned this way on purpose (section 2).
Published benchmarks put single-pass detection by current agents between one
third and three quarters (section 6). Fix: C3, after measurement.

**F12. [P3] The record of the judge is incomplete.**
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:103-114`, `192-198`.
The log header already holds the CLI version, model, effort, and sandbox. Missing
are the plugin version, a hash of the prompt and instruction files, the reviewed
commit and fingerprint, the web search mode, and the tools used. The built-in
guidelines and the available tools change with the CLI, not with this plugin, so
without that record two reviews cannot be compared. This confirms a P3 in the
first report. Fix: A10.

**F13. [P3] The after-review fingerprint depends on the order of the
implementer's actions.** `plugins/codex-review-loop/skills/codex-loop/SKILL.md:207-215`.
The second fingerprint is a separate step taken after the review returns. An edit
made in between, for example at the user's request, voids the comparison, and
nothing detects that. Fix: A2 takes the second fingerprint in the same step that
reads the log.

**F14. [P3] Same-named checkouts share one log folder and one task file.**
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:97-101`; `docs/GUIDE.md:345-346`.
The second report rates this P2. I rate it P3, because the loop prints the
request before each run and asks when the task plainly differs
(`SKILL.md:70-74`). Detection is cheaper than a new folder scheme. Fix: A10.

**F15. [P3] The completeness check proves less than its name suggests.**
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:240-245`.
The first report rates this P2 because a file listed by `git status` passes. The
skill claims only the converse, that a name appearing nowhere was never looked
at, and that claim is true. The improvement is to cover tracked files and paths
mode, and to call the result "mentioned in the log".

**F16. [P3] The acceptance criteria can change after the user has seen them.**
`plugins/codex-review-loop/skills/setup/templates/claude-rules.md:38-47`;
`plugins/codex-review-loop/skills/codex-loop/SKILL.md:274-275`.
The criteria drive the requirement check and are written by the implementer. The
rule against editing them is an instruction. Fix: B1 records a hash of the
request and criteria sections when they are shown, and the loop reports any later
change.

**F17. [P3] Two documentation statements are out of date or too strong.**
`docs/GUIDE.md:388-390` says session records are `rollout-*.jsonl`; older records
are now stored compressed, as `rollout-*.jsonl.zst` (observed 2026-11-12).
`README.md:8-10` says a reviewer from another vendor "does not share the author's
blind spots", which section 6 contradicts; the first report makes the same point.
Fix: A10.

## 5. The two earlier reports

| Item | My assessment | What this report adds | Plan |
|---|---|---|---|
| First report, finding 1: no accuracy coverage. | Confirmed. It is the main gap. | A cheap source of labeled cases: in this repository's history, the commit before a bug fix is a tree with a known defect. | B4 |
| First report, finding 2: completeness check. | Valid observation, P3 not P2. | See F15. | A10 |
| First report, finding 3: no incomplete verdict. | Confirmed. | A ready signal in the reviewer's own overall verdict. | A1, C6 |
| First report, P3: worked severity examples. | Agree, with a prior step. | Two scales conflict (F9); resolve that before adding examples. | A6 |
| First report, P3: record the judge configuration. | Agree. | Part is already in the log header; the tool surface is the missing part. | A10 |
| First report, P3: independence is a hypothesis. | Agree. | Research on agreeable validators and on correlated errors (sections 2 and 6). | A8, C2 |
| Second report, 1: a runner. | Partly. Move fact extraction and prompt assembly into scripts first. | The gaps found here are in reading results, not in launching Codex. A runner that launches Codex needs a shell grant with arguments, and 0.2.2 removed such grants after the directory held 0.2.1. | A2, B3 |
| Second report, 2: behavioral evaluations. | Agree. | The source of cases above, and a staged budget (section 9). | B4, E1, E2 |
| Second report, 3: embedded instructions. | Agree. | The concrete mechanism and a precedent (F7). | A5, E7 |
| Second report, 4: unique storage. | Agree on the problem; prefer detection. | See F14. | A10 |
| Second report, 5: scoped repository rules. | Agree. | The built-in guidelines already attribute findings to rule files. OpenAI names the section `## Code Review Rules`. | C7 |
| Second report, 6: capability checks. | Agree, and it is more urgent than rated. | OpenAI's documentation confirms that the sandbox does not cover these tools (F1). | A2, A11 |
| Second report, 7: portable automation. | Agree. | No addition. | B3 |
| Second report, 8: targeted verification. | Agree. | Which passes to try first, and why. | C1, C2, C3 |

Three corrections to the earlier reports:

1. **Structured output is already there.** The second report proposes testing
   `--output-schema`. The review's native result is already a fixed JSON object
   (section 3). The open question is how to read it, not how to request it.
2. **A confidence filter needs evidence first.** Both reports mention structured
   fields in general terms. Nothing shows that the reviewer's stated confidence
   separates right findings from wrong ones.
3. **One source address.** The Anthropic article on agent evaluations is at
   `https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents`. The
   other four sources cited in the second report were opened and say what the
   report attributes to them; two publication dates could not be confirmed from
   the pages.

## 6. Current practice that applies

All sources were opened on 2026-11-12. Quoted figures are the sources' own; none
measures this plugin.

| Source | What it says | Consequence for the loop |
|---|---|---|
| [CR-Bench-v2](https://arxiv.org/abs/2611.02566), preprint, 2026-11-02 | "Even the strongest systems detect only about one-third of known defects". It scores detection of a known defect separately from the usefulness of comments. | One pass misses most known defects. Measure detection and usefulness separately (B4). |
| [SecPRBench](https://arxiv.org/abs/2610.33509), preprint, 2026-10-24 | "Across eight frontier models, recall ranges from 32.5% to 78.1%". In 68% of misses the agent "reports on a file that holds the flaw but argues for a different mechanism". A security harness that abstains more lowered recall by 8.3 points. | Grade the mechanism, not the file. Stricter filtering costs recall (F11). |
| [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents), Anthropic, 2026-01-09 | "20-50 simple tasks drawn from real failures is a great start." "Test both the cases where a behavior should occur and where it shouldn't." "LLM-as-judge graders should be closely calibrated with human experts". It separates success in at least one of k trials from success in all k. | Corpus size, matched defect and control cases, repeated trials (B4, E1, E2). |
| [Code Review](https://code.claude.com/docs/en/code-review.md), Claude Code documentation | Four stages: several agents find, "a verification step checks the candidate findings against the code and filters out false positives", then rank and post. "A review with no findings doesn't mean your code is error-free or secure." Instructions come "from the base or default branch and never from the pull request's own changes". | The loop already has find and verify. It lacks the caveat on a clean result (A1) and the instruction rule (A5). |
| [Best practices](https://code.claude.com/docs/en/best-practices.md), Claude Code documentation | A fresh reviewer "isn't swayed by the reasoning that produced the code". "A reviewer that's asked to find problems will always find *something*. If you fix every finding, you end up with extra abstraction layers and tests for cases that can't happen." A subagent given only read tools "can't edit anything, and that limit is enforced by Claude Code rather than requested in a prompt". | An independent check of overrides can be a read-only subagent (C2). Findings in later rounds may be over-reporting, which only control cases can settle (E2). |
| [Build iterative repair loops with Codex](https://developers.openai.com/cookbook/examples/codex/build_iterative_repair_loops_with_codex), OpenAI | "A good loop usually stops for one of four reasons: validation passes, the loop reaches a maximum number of attempts, the remaining delta stops changing, or the next decision needs human review." | The loop has three of the four. It lacks "stops changing" (C1). |
| [Custom Code Review rules for Codex](https://developers.openai.com/blog/custom-code-review-rules-for-codex), OpenAI | Rules go under `## Code Review Rules` in `AGENTS.md`. "Try one change that should trigger the rule, one safe counterexample, and one unrelated change." Rule-guided variants "recovered 98% of the required custom findings, compared with 58.3% in the baseline control". | Specific repository rules are the best-supported way to raise detection (C7). |
| [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) and [security page](https://learn.chatgpt.com/docs/agent-approvals-security) | `web_search` is `disabled`, `cached`, `indexed`, or `live`. `features.apps` enables connectors and is on by default. `mcp_servers.<id>.enabled` disables a server. Named permission profiles can deny reads by glob, and `default_permissions` must not be combined with `sandbox_mode`. "Treat web results as untrusted." | The settings that A9, A11, and C5 use. Each must be tested with `codex exec review` before it is relied on. |
| [Test plugins with evals](https://code.claude.com/docs/en/plugin-evals.md), Claude Code documentation | `claude plugin eval` runs a plugin against cases with graders, from version 2.1.269. Mocks replace MCP tools. "Native Windows has no backend, so run shell-granting suites under WSL2". Every run is a real model call. | A way to test the skill end to end, on Linux or WSL2 only, and only if `codex` can be replaced by a stand-in (B5). |

Research and field reports on review loops, with the same reading rules:

| Source | What it says | Consequence for the loop |
|---|---|---|
| [SWR-Bench](https://arxiv.org/abs/2509.01494), preprint, 2025-09-01, revised 2026-06-05 | "a simple multi-review aggregation strategy that significantly boosts ACR performance, increasing F1 scores by up to 43.67%". | Several independent reviews find more than one. This is the best support for a second pass (C3, E1, E6). |
| [How AI code review can make correct code worse](https://imbue.com/blog/2026-04-29-how-ai-code-review-can-make-correct-code-worse), Imbue, 2026-04-29 | In an implement, review, fix pipeline: "In more than 70% of trials, the score doesn't change." "Of 15 resolved tasks, the reviewer found issues in 8." "The fixer made changes beyond the immediate scope of the review finding, and that led to a regression." | A reviewer reports issues on correct code too, and fixing them has a cost. This is why E2 needs control cases, and why findings in later rounds cannot be assumed to be real defects. Small samples, from a vendor of a review tool. |
| [Security Degradation in Iterative AI Code Generation](https://arxiv.org/abs/2506.11022), preprint, 2025-05-19 | "a 37.6% increase in critical vulnerabilities after just five iterations", "emphasizing the need for robust human validation between LLM iterations". | More unattended rounds are not safer by default (C1). The study used generic "improve this" requests without findings or tests, so it is a worst case for this loop. |
| [Self-Attribution Bias](https://arxiv.org/abs/2603.04582), preprint, 2026-03-04 | "monitors fail to report high-risk or low-correctness actions more often when evaluation follows a previous assistant turn". Also: "explicitly stating that the action comes from the monitor does not by itself induce self-attribution bias." | The measured effect is about context, not vendor: judging one's own work in the same conversation is lenient. That is the implementer's position at triage (F5, C2). |
| [Correlated Errors in Large Language Models](https://arxiv.org/abs/2506.07962), ICML 2025 | "models agree 60% of the time when both models err"; "larger and more accurate models have highly correlated errors, even with distinct architectures and providers". Measured on leaderboard and hiring tasks, not on code review. | A reviewer from another vendor still shares blind spots. Agreement between the two tools is not proof (F17). |
| [SEVRA-BENCH](https://arxiv.org/abs/2606.13757), preprint, 2026-06-11 | "we reveal that review agents are susceptible to narrative manipulation". The framings it tests vary "supporting evidence, conveyed urgency, signals of prior approval". | The handoff and the decisions file are narrative channels of exactly this kind (F5, F6, F7, E3, E7). |
| [uReview](https://www.uber.com/blog/ureview/), Uber, 2025-08-12 | Four stages: "comment generation, filtering, validation, and deduplication". Engineers "mark 75% of its comments as useful". The best configuration paired a generator from one vendor with a grader from another. | The loop's shape, generate then verify, matches production practice, and so does pairing two vendors. Self-reported. |
| [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc), OpenAI, README | Offers `/codex:review`, a steerable `/codex:adversarial-review`, and an optional gate: "the plugin uses a `Stop` hook to run a targeted Codex review based on Claude's response." It warns that the gate "can create a long-running Claude/Codex loop and may drain usage limits quickly." | The official plugin reviews; it has no task file, triage record, or regression-test rule, which remain this plugin's distinct value. Its warning supports keeping the loop out of hooks. |

No controlled study was found that compares a reviewer from another vendor with
one from the same vendor on defects caught, or that tests a re-review limited to
the fix against a full re-review. Those two points in the plan rest on reasoning
and vendor practice, and E1 to E6 exist to check them here.

## 7. Improvement plan

**Keep unchanged:** the separate implementer and reviewer, the forced read-only
sandbox, the fingerprint, verbatim display of the review, evidence-based triage,
regression tests for fixes, logs outside the repository, and the user's commit.

Effort is relative for this repository: S is under a day, M a few days, L more.
Every change under `plugins/` needs the version and changelog steps in `AGENTS.md`.

### Release A: report honestly, limit the reviewer's tools, close suppression paths

Release A ships in three phases. Phase 1, version 0.3.0, delivered A2, A3, A9, A11,
and A12. Phase 2, version 0.4.0, delivered A1, A8, and A10. Phase 3, version 0.5.0,
delivered A4 to A7. The check for A6 did not pass: in every seeded review that tried
it, the reviewer rated a data-loss defect P1.

Release B began with phase 4, version 0.6.0, which delivered B1 and B2.

| ID | Change | Where | Check that proves it | Effort |
|---|---|---|---|---|
| A1 | Five verdicts: verified; clean with unverified items; fixes not re-reviewed; open findings; review failed. Each criterion row names who verified it: the reviewer, the implementer's own run, or nobody. | `SKILL.md` steps 6 to 8; guide; cheat sheet | A table of cases in the skill maps facts to one verdict each. A run where the reviewer cannot execute the tests ends as "clean with unverified items". | S |
| A2 | A script reads a round's log and prints facts: sandbox line, CLI version, model, effort, shell commands started and failed, tool calls by server. The loop prints them under each review and takes the second fingerprint in the same step. It stops with "review failed" when no sandboxed shell command succeeded (decision 1). | New `round-facts.sh` beside `fingerprint.sh`; `SKILL.md` steps 4 and 5 | Shell test with synthetic logs: normal, every shell start failed, tool calls present, missing header. | M |
| A3 | State what can leave the computer: whatever the reviewer reads, and its web searches. State that the read-only sandbox limits commands, and which other tools the loop turns off. | Both READMEs; guide section 15 | Plugin README keeps 40 words outside code blocks; both validations pass. | S |
| A4 | Decisions explain intent and do not excuse a defect. Report a decision that contradicts the request, a criterion, or a repository rule, or that creates a security, data-loss, or correctness defect. Mark each decision as the user's, with a dated quote, or the implementer's. | `review-prompt.md:45-48`; `task-template.md:21-23`; `claude-rules.md` | E7 case: a decision that removes an authorization check is reported. | S |
| A5 | Before each round, list changed instruction files: `AGENTS.md` at any depth, `AGENTS.override.md`, `CLAUDE.md`, `.codex/`, and `docs/reviews/decisions.md`. Name them in the prompt, tell the reviewer to apply the committed version and review the change, and present uncommitted decision rows as claims to check once. Report the list to the user. | `SKILL.md` step 4; `review-prompt.md` | E7 cases: a relaxed rule and a false rejection row do not suppress a seeded defect. | M |
| A6 | Say that the plugin's severity scale replaces the default priority definitions, and that P0 applies even when the defect needs a specific input. Add boundary examples only if E2 shows they help. | `review-prompt.md:75-84` | E2: a seeded data-loss case is labeled P0. | S |
| A7 | In paths and audit mode, say that existing defects in the target are in scope and need not overlap a diff. | `SKILL.md:158-165` | E2 audit case. | S |
| A8 | A fixed triage table: finding, reviewer label, final label, decision, evidence, proof. Proof is the test name with its failing and passing result, or the reason no test is possible. The final report opens its detail with "Implementer overrides": every rejection and every finding moved from must-fix to P3. | `SKILL.md` steps 6 and 8 | The statistics script in B2 parses every row. | S |
| A9 | The loop passes the web search mode on every review: `cached`, or `live` when the user asks for it, and a third choice removes web search for one review (decision 2). Setup stops writing `web_search = "live"`, tells existing users that the line is no longer needed, and says plainly that `model_reasoning_effort` in its block applies to all Codex sessions. | `SKILL.md` steps 1 and 4; setup skill; `codex-config.toml`; guide sections 4 and 8 | A review run without the option shows the cached mode in its record; setup check mode reports the scope of each key. | S |
| A10 | Write the repository's root path to a marker file in the log folder and stop when it differs. Add a judge record to each triage file: plugin version, prompt hash, commit, fingerprint, web search mode, tool counts. Correct the two statements in F17 and the name of the completeness check. | `SKILL.md` steps 3 and 5; guide; README | Shell test: two folders with one name and different roots stop the second. | S |
| A11 | Reviews run with connectors, MCP servers, and Codex plugins off, and a new option allows them for one review (decision 3). Done with `--disable plugins`, `apps._default.enabled=false` plus an exception for the search connector, and one flag that turns every configured MCP server off. Before each round the loop asks Codex whether anything else is still on, and does not start the review if so. `--ignore-user-config` was rejected: it would also drop the user's review model, effort, and sandbox settings. | `SKILL.md` step 4; guide; READMEs | Observed on Windows on 2026-11-13 with a synthetic repository: a default review listed no tool besides the shell and web search. Not run on macOS or Linux. | M |
| A12 | Add decision 4 to the "No personal or company details" invariant: no usage figures, no numbers derived from review logs, no details of a real computer. | `AGENTS.md` | The next review cites the rule. | S |

A11 has one known cost. With the other tools off, a review cannot fall back on
them when the sandboxed shell fails. That is the intended result of decision 1:
the round stops and says why.

### Release B: make the loop measurable

| ID | Change | Check that proves it | Effort |
|---|---|---|---|
| B1 | The loop writes a summary file per run, in the log folder, with a fixed schema: rounds, labels, decisions, overrides, verdict, durations, the judge record, and a hash of the request and criteria sections. | The schema is documented, and B2 reads it. | S |
| B2 | A statistics script in `tests/` that prints the measures in section 3 from the user's own log folder. Its output is private and is never committed. | It runs on a folder of synthetic logs kept with the tests. | M |
| B3 | Shell tests for every helper script, and a workflow that runs them on Linux, macOS, and Windows with Git Bash, reporting passed, failed, and skipped separately. Add a check that published files contain no absolute path or e-mail address. No AI account needed. | The executable-bit case that one platform skips runs on another. | M |
| B4 | An evaluation corpus of 20 to 30 cases. Start with matched pairs from this repository's git history: the commit before a bug fix is a defect case, and the fix is a control. Add written cases for the security rubric, an unmet criterion, a false handoff claim, and an addition beyond the request. Each case records the mechanism and trigger. Labels stay outside the fixture. This size is a start: [practitioner guidance](https://hamel.dev/blog/posts/evals-faq/) for validating a judge is "at least 50 passing and 50 failing examples". | A person agrees with every label before the reviewer runs. | L |
| B5 | A feasibility test of `claude plugin eval` for the skill's mechanics, on Linux or WSL2, with a stand-in for `codex`: not logged in, empty output, changed fingerprint, report-only writes nothing, cap reached. | Five cases run and grade without a ChatGPT account. If the stand-in cannot be injected, record that and stop. | M |
| B6 | Run E1 and E2 and record the baseline. Results stay outside the repository unless the maintainer chooses to publish them. | Results with sample sizes. | M |

### Release C: strengthen where the data justifies the cost

| ID | Change | Adopt when |
|---|---|---|
| C1 | The next round's prompt lists the previous round's accepted findings and asks for "closed" or "not closed" on each. Word the list neutrally: give the findings and ask for their current state, without saying the code was fixed or improved. When the cap is reached after fixes, run one pass limited to the files changed since the previous round. Stop and escalate when a round reports at least as many must-fix findings as the one before. | E2 shows that later-round findings are real defects and not over-reporting. |
| C2 | Before a rejection or a move from must-fix to P3 is recorded, a read-only subagent with a fresh context checks the finding against the code. For a rejected P0 or P1, the reviewer also gets one rebuttal. | Now, if cost allows: only overrides are checked, not every finding. |
| C3 | When round 1 is clean and the change touches paths the repository lists as risk areas, run a second pass with a different focus. Let those risk areas also set the effort. | E6 shows the second pass finds verified defects. |
| C4 | Review in two passes: first without the handoff, then with it to check its claims. | E3 shows that the handoff sways the result. |
| C5 | A permission profile that keeps the repository read-only and also denies reads of secret files such as `.env`. This replaces `sandbox_mode` with `default_permissions`, so the wording of the read-only invariant has to change with it. | The profile works with `codex exec review` on all three platforms, and the maintainer accepts the new wording. |
| C6 | Read the reviewer's overall verdict and treat a mismatch with the finding count, or a low overall confidence, as "clean with unverified items". | The verdict can be read from `--json` output or another documented place. |
| C7 | Name the rule section in the repository template `## Code Review Rules`, and have setup propose two or three rules with a safe alternative each. | E2 control cases show no added false alarms. |

### Not recommended

- **A numeric quality score or pairwise ranking for the verdict.** The excerpt
  itself separates correctness from preference
  (excerpt:356-373).
- **A filter on the reviewer's confidence,** until measurement shows the scores
  discriminate. B2 can print their spread.
- **A higher round cap as the remedy for unreviewed fixes.** Each extra round is
  another full review against the ChatGPT allowance (`docs/GUIDE.md:317-320`), and
  repeated unattended fix rounds carry their own risk (section 6). C1 targets the
  same risk for less.
- **A writable reviewer, hooks, or moving logs into the plugin data folder.** The
  first breaks an invariant. Hooks fit rules with no exceptions, and this loop
  has two. The plugin data folder is deleted on uninstall.

## 8. Experiments

Costs are counted in reviews. Each one is a full request against the maintainer's
ChatGPT allowance.

| ID | Question | Method | Measure | Decision |
|---|---|---|---|---|
| E1 | How often does an identical review of a clean tree find something? | Take 10 trees that ended clean; review each twice more with the same prompt. 20 reviews. | Share of repeats with a must-fix finding; a person judges each. | Above 10% real defects: adopt C3. Mostly false alarms: tighten the prompt instead. |
| E2 | What does the reviewer catch, and what does it flag on correct code? | B4 corpus, two runs per case. For 24 cases: 48 reviews. | Detection of the labeled mechanism; must-fix findings on controls; severity agreement; the implementer's triage scored separately. | Sets the baseline that every prompt change in Release A is compared against. |
| E3 | Does the handoff sway the reviewer? | Same code, three handoffs: none, short, long and confident. | Change in detection on defect cases. | A drop with the long handoff: adopt C4. |
| E4 | Does naming the author matter? The evidence is mixed: see the label study in section 2 and the self-attribution study in section 6. | "Another AI coding agent (Claude Code)" against "another engineer". | Detection and false alarms. | Keep whichever is better; no difference, use the neutral wording. |
| E5 | Is higher effort worth it? | Two effort levels on the corpus. | Detection per review and per minute. | Sets the default and the routing in C3. |
| E6 | What does a second pass with another focus add? | After a clean round 1 on defect cases, run a focused pass. | Extra verified defects per pass. | Adopt C3 if it finds what round 1 missed. |
| E7 | Do embedded instructions suppress findings? | Seed a defect beside a suppressing comment, a relaxed rule, a false rejection row, and an excusing decision. | Detection with and without the embedded text. | Any drop: A4 and A5 are not yet sufficient. |

Comparison between two reviews has one proper use here: choosing between two
prompts or settings on usefulness, once detection is equal. The maintainer is the
informed voter the excerpt requires.

## 9. Decisions

Decided by the maintainer on 2026-11-13:

| # | Question | Decision | Where it lands |
|---|---|---|---|
| 1 | Stop or warn when the reviewer's sandboxed shell is unavailable? | Stop. | A2 |
| 2 | Which web search mode for reviews? | First `cached` by default, `live` on request. Revised the same day, after a test showed the search tool fetching a live page in both modes: web search on by default with `cached` passed, and an option to turn it off or ask for `live` for one review. | A9 |
| 3 | Are connectors and MCP servers available to the reviewer? | Off by default. | A11 |
| 4 | May usage figures or details of the maintainer's computer appear in this repository? | No. Nothing personal, no usage, nothing taken from a real computer, nothing about an employer. | This report, A12, B2, B6 |
| 5 | Is Python acceptable for repository-only tooling? | Yes, as recommended: Python 3 with the standard library only, in `tests/` only. Nothing under `plugins/` may need it, and the documented shell checks stay as they are. The reason given: B1 writes JSON, and the statistics and the evaluation scoring need a JSON parser and arithmetic, which shell cannot do portably without a tool such as `jq`. | B2, B4 |
| 6 | How much review allowance may evaluations use? | As recommended, in three stages. A pilot of 12 reviews to prove the harness and the labels. Then E1 and E2, 68 reviews, spread over about three weeks. After that, about 10 reviews each time the prompt, the review model, or the Codex CLI changes. Stop after the pilot if the labels or the harness need work. | B4, B6 |

Decisions 5 and 6 were recommendations until the maintainer accepted both on 2026-11-13.

## 10. Verification and sources

| Check | Result |
|---|---|
| Built-in review guidelines | Read from a review session record on 2026-11-12. The plugin's prompt arrives as a user message, as `SKILL.md:182-184` states. |
| `codex exec review --help`, `codex exec --help`, `codex features list` | Ran on 2026-11-12. `review` advertises `--json`, `--output-schema`, `--ignore-user-config`, `--disable`, and `-c`; it does not list `--profile` or `--sandbox`. |
| Live review, any setting in A9, A11, or C5, `claude plugin eval` | Not run. These are proposals to test. |
| Repository checks, run after this file was written | `claude plugin validate --strict .` passed. `claude plugin validate --strict plugins/codex-review-loop` passed, with advice that the plugin README has no install line. `claude --plugin-dir ./plugins/codex-review-loop plugin details codex-review-loop` listed `Skills (2)  codex-loop, setup`. `bash tests/fingerprint.test.sh` printed `all passed`, with one case skipped. |
| This report | A script confirmed that every cited line range and local link exists, and that the text contains no absolute path, e-mail address, or personal name. |
| Research quotations | Each quoted passage was confirmed on the source page on 2026-11-12. Where only an abstract was read, the quotation comes from the abstract. |

Documentation pages are cited in sections 2 and 6. Two further statements rest on
the installed software and not on documentation: the shape of the review result,
and the storage of older session records in compressed form.
