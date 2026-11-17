# Task: search in the list of notes

## Request (verbatim)

Add search to the list of notes: GET /notes?q=<text>.

## Acceptance criteria

1. `GET /notes?q=<text>` returns only those of the user's notes whose title or body holds the text.
2. The match ignores case.
3. A `q` that is present but empty is answered with 400 and an error message.
4. Without `q` the list is as before.

## Out of scope

- Search across users.
- Ranking or paging of the result.

## Decisions during implementation

- [implementer] The text is compared with `casefold()`, which also folds letters that `lower()` leaves.

## Handoff

Files:

- `notes/app.py`: `_list()` reads `q`.
- `tests/test_app.py`: the tests below.
- `README.md`: the route in the table.

Tests and what each proves:

- `test_search_finds_text_in_title_or_body`: criterion 1, and that another user's note is not found.
- `test_search_ignores_case`: criterion 2.
- `test_list_without_q_is_unchanged`: criterion 4.

Assumptions: none.

Checks:

- `python -m unittest tests.test_app`: passed, `OK`, 12 tests.

Risks: none known.
