# Task: a limit of 100 notes for each user

## Request (verbatim)

Limit each user to 100 notes.

## Acceptance criteria

1. `POST /notes` with a title and a body that are acceptable is answered with 409 and an error message when the user already has 100 notes, and no note is added.
2. The limit counts a user's own notes only: the notes of other users do not use it up.

## Out of scope

- A limit that can be set for each user.
- Removing notes that are over the limit.

## Decisions during implementation

- [implementer] The title and the body are checked before the limit, so a note that would be refused anyway is answered with 400.

## Handoff

Files:

- `notes/app.py`: `MAX_NOTES` and the check in `_create()`.
- `tests/test_app.py`: the tests below.
- `README.md`: the answer 409 in the table.

Tests and what each proves:

- `test_limit_returns_409`: criterion 1.
- `test_limit_is_per_user`: criterion 2. With 100 notes of one user, another user still adds one.

Assumptions: none.

Checks:

- `python -m unittest tests.test_app`: passed, `OK`, 11 tests.

Risks: none known.
