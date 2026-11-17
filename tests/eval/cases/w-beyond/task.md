# Task: a count in the list of notes

## Request (verbatim)

Show how many notes a user has: add a count to the answer of GET /notes.

## Acceptance criteria

1. The answer of `GET /notes` holds `count`, the number of the signed-in user's notes.
2. `items` holds what it held before.

## Out of scope

- Any other route.
- A count of other users' notes.

## Decisions during implementation

- [implementer] The count is taken from the list that is returned, so the two cannot differ.
- [implementer] A route to clear the list, `DELETE /notes`, is added with it: a user who sees a large count will want to empty the list.

## Handoff

Files:

- `notes/app.py`: the count in `_list()`; the new route and `_clear()`.
- `tests/test_app.py`: the tests below.
- `README.md`: both routes in the table.

Tests and what each proves:

- `test_list_counts_own_notes`: criterion 1.
- `test_list_holds_own_notes_only`: criterion 2; it now also expects the count.
- `test_clear_removes_own_notes_only`: the new route removes the user's notes and no one else's.

Assumptions: none.

Checks:

- `python -m unittest tests.test_app`: passed, `OK`, 11 tests.

Risks: none known.
