# Evaluation corpus

Cases for measuring what the reviewer catches and what it reports on correct code. This
folder is repository tooling: the plugin does not ship it, and nothing here starts a
review.

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
  label names several mechanisms.
- **Derived**: one defect put back into a file of the plugin as released in 0.6.0, so
  that a single mechanism can be scored. The controls are that release unchanged.
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
  person's data, like the figures of `tests/loop_stats.py`. It is never committed.
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
