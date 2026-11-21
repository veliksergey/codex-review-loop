# Evaluation corpus

Cases for measuring what the reviewer catches and what it reports on correct code. This
folder is repository tooling: the plugin does not ship it. `tests/eval_corpus.py` builds
and checks the corpus and starts no review. `tests/eval_review.py` runs a review on a
case, one at a time and only when you ask for it; see [Reviews](#reviews).

A **case** is a small git repository, its fixture, that a review can be run on. A
**defect case** holds a known defect; its **control** is the same fixture without it. A
**label** says what is wrong with a fixture: the mechanism, the trigger, the place, the
tag and the severity of a correct finding, and how the label is proved.

| Path | Contents |
|---|---|
| `cases/<case>/case.json` | How the fixture is made: from a commit of this repository, or from the made-up project in `shared/`, with the edits that set it apart. |
| `cases/<case>/task.md` | The task file of a case that is reviewed against a request. |
| `labels/<case>.json` | The label. |
| `proofs/` | Small programs that are run on a fixture: exit code 0 on a control, 10 on its defect case, 77 where the system cannot run them. Any other code means the program itself failed. |
| `shared/notes/` | A made-up notes service, the base of the written cases. |
| `agreed.json` | Which cases a person agreed with, each with a hash of the case and its label. |

## Where the cases come from

- **History**: two pairs from this repository's own commits, the tree before a fix and
  the tree at the fix. One of those commits corrected several defects at once, so its
  label names several mechanisms. These old trees also hold defects that later releases
  corrected. Their labels name those as known defects: a finding on one is right, and it
  is counted apart from the labeled mechanisms and from the false alarms.
- **Derived**: one defect put back into a file of the plugin as released in 0.6.1, so
  that a single mechanism can be scored. The controls are that release unchanged. Its
  fingerprint script holds one defect that 0.6.2 corrected, and the labels of the cases
  made from that script name it as a known defect, as the labels of the old trees do.
- **Written**: four pairs on the made-up notes service: a missing check of the owner,
  an acceptance criterion that is not met, a handoff that names a test which does not
  exist, and a route that the request did not ask for.

A fixture from this repository is the plugin folder of the named commit, as a person
who installs the plugin gets it: no tests and no changelog, which would name the fix.

## Rules

- **Labels stay outside fixtures.** A reviewer reads what the fixture holds, so a
  fixture holds no label, no name of a case, and no other case. `build` refuses a folder
  inside this repository.
- **A person agrees with every label before a review of its case runs.** `sheet` prints
  the labels; `agree` records the agreement. A case or a label that changes afterwards
  counts as not agreed, and so does a case whose proof changes: the program in
  `proofs/`, or the whole file of the regression test it runs.
- **Results stay outside this repository.** What a review of a case says is one
  person's data, like the figures of `tests/loop_stats.py`. It is never committed, and
  `tests/eval_review.py` refuses a results folder inside this repository.
- **A label is proved where it can be.** Most proofs run: a regression test of this
  repository, or a program in `proofs/`. One label is proved by reading only, because
  running its defect would delete files. Some defects show on one kind of system only,
  because a link to a folder is a junction on Windows and a symbolic link elsewhere;
  their labels say so, and their proofs are skipped on the other kind. `check` names
  every proof, and every case of a proof, that did not run on the system.

## Commands

```bash
python tests/eval_corpus.py list                  # every case
python tests/eval_corpus.py check                 # proves every label on its fixture
python tests/eval_corpus.py check --slow          # on Windows, also the proofs by shell tests;
                                                  # EVAL_CORPUS_SLOW=1 does the same, also for the test
python tests/eval_corpus.py sheet                 # every label, to read
python tests/eval_corpus.py build <case> <folder> # the fixture, in a folder outside this repository
python tests/eval_corpus.py agree <case>...       # record that you agree; --all for every case
python tests/eval_corpus.py status                # which cases are agreed with
```

`build` writes `<folder>/repo`, and `<folder>/task.md` for a case with a task file. The
cases from this repository need its history: a clone without the named commits reports
them as not built. `bash tests/eval-corpus.test.sh` runs the tests of the tool and the
check of this corpus.

## Reviews

```bash
python tests/eval_review.py run <case> --dry-run  # everything but the review: the prompt and the flags
python tests/eval_review.py run <case>            # one review of one case
python tests/eval_review.py judge                 # a judgment file for each review that has none
python tests/eval_review.py report                # figures from the reviews that are judged
```

**`run` spends one review of your Codex allowance and sends the fixture and its task
file to OpenAI**, as a review of your own code does. One call is one review. It refuses a
case whose label is not agreed with.

A review of a case runs as the review loop runs one. `run` builds the fixture in a
temporary folder, fills the plugin's `review-prompt.md` with the scope text that
`SKILL.md` gives for the case, the case's task file or the line for a review without
one, and the output of `instruction-changes.sh`. It takes the flags from `tool-flags.sh`
and stops when that script fails. It starts `codex exec review` in the fixture with the
read-only sandbox and those flags, takes the fingerprint of the fixture before and
after, and reads the log with `round-facts.sh`. Nothing that is handed to Codex names
the case. On Windows the fixture is built below the long name of the folder for
temporary files: the system can hand that folder over with a short name in its path,
such as `PROGRA~1`, and Codex's sandbox was seen to deny a reviewer's commands that
named the fixture so.

One thing differs from the loop's default: a review of a case runs **without web
search**, with the flags of `tool-flags.sh off`, which is what the loop's `--web off`
uses. This repository is public, with its labels and with the fix of every defect that
comes from its history, and Codex's log does not say what a search fetched. So a review
with web search could not be shown to be blind to the answer. `--web cached` and
`--web live` after `run <case>` turn web search on; a review in which the reviewer then
searched the web is marked as not usable.

Each review leaves a folder of its own, `<results>/<case>/<date and time>/`: the prompt,
the review, Codex's log, the facts read from the log, the command and the flags Codex
was started with, and `record.json` with the case, the hash of its label, the plugin's
version, the commit of this repository, the web search mode, the time taken, Codex's
exit code, and both fingerprints. `<results>` is the folder `eval` in the
log folder that the review loop keeps for this repository,
`~/.claude/codex-reviews/<repo>/eval`, or the folder named with `--results` before the
command. The record is put in place last, so a folder with a record holds the whole
review. A review that was started and could not be kept in the results, or that you
stopped, is not deleted: it stays in its temporary folder, and the message names that
folder. The folder of a case or of a review below `<results>` may not be a link that
leads into this repository.

A review is marked as not usable in its record, with the reasons, and is never scored,
when Codex ended with an exit code other than 0, the review is empty, no sandboxed
command ran, no command that ran ended with exit code 0, a tool that should be off was
called, the sandbox was not read-only, the reviewer searched the web, the fixture
changed during the review, or the log shows that the reviewer may have read a label.
That last one is there because the sandbox stops
the reviewer from writing, not from reading, and a reviewer that could have read a label
proves nothing. The log holds every command the reviewer ran and what each printed, and
it is searched for the name of the case, for the path of the corpus, of the results
folder, and of this repository, and for the lines of the case's label and definition as
they stand on disk: each line of 30 characters or more that opens with a key. What the
search cannot see: a label read by a path it does not know, such as a short Windows
name, and printed in another form than the file has.

The loop has a person read a log that leaves a doubt; this tool has none to ask and
decides against the review. A line of the log with the shape of a tool call counts as a
call, also where it stands in what a command printed. And a sandboxed command counts as
having run only in a log where every command that started also ran and none failed to
start: a line inside the text of a command can have the shape of a command that ran. One
doubt stays: a reviewer that ran no command at all and wrote both lines of a command in
its own message would be counted as having run one.

A review in which commands ran and not one of them ended with exit code 0 is left out
as well: the reviewer may have read nothing, as where the sandbox denies the folder of
the fixture. This check is coarse in both directions. A command can fail and still print
what it read, so a review that read enough can be left out. And a line with the shape
of a command that succeeded counts as one, also where it stands in the text of a command
or in what a command printed.

`judge` writes `judgment.json` beside each review that can be scored: the findings of
the review with label, tag, title, and place, the mechanisms of the label, and for each
finding the mechanisms in the same file and at the same lines. A person, or the
implementer for a person to confirm, then states in that file what every finding labelled
P0, P1, or P2 is: `mechanism` with the number of a mechanism of the label, `known defect`
for one the label names as known, `other defect` for another real defect, or
`false alarm`; and signs it with `judged_by` and `judged_on`. `judge` never writes over a
judgment. No model judges a finding.

`report` prints, from the reviews that are usable and whose judgment is whole and signed:
how many labeled mechanisms a must-fix finding found, how the severity and the tag of
that finding compare with the label's, what the must-fix findings were, and for controls
how many of them were false alarms. Each figure stands beside the size of its sample, and
the reviews that were left out are counted and named with the reason. It writes no file.
Its output is private; do not commit or publish it.

`bash tests/eval-review.test.sh` runs the tests of the runner. A stand-in takes the
place of Codex there, so the tests start no review and send nothing.
