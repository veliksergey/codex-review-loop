# Task: download a note as a text file

## Request (verbatim)

Let a signed-in user download one of their notes as a text file.

## Acceptance criteria

1. `GET /notes/<id>/download` is answered with 200 and the content type `text/plain; charset=utf-8`. The body is the title, an empty line, and the note's body, with a line break at the end.
2. The answer carries `Content-Disposition: attachment; filename="note-<id>.txt"`.
3. A request without a valid session is answered with 401, as on every route.
4. An id that names no note is answered with 404.

## Out of scope

- Other formats than plain text.
- Any change to the existing routes.

## Decisions during implementation

- [implementer] The file name holds the id of the note and not its title: a title can hold characters that a header or a file name cannot.

## Handoff

Files:

- `notes/app.py`: the route and `_download()`.
- `tests/test_app.py`: the tests below.
- `README.md`: the route in the table.

Tests and what each proves:

- `test_download_own_note`: criteria 1 and 2.
- `test_download_needs_a_session_and_a_note`: criteria 3 and 4, and 405 for another method.
- `test_download_foreign_note_is_not_found`: a note of another user is answered with 404, as the repository's rule asks.

Assumptions: none.

Checks:

- `python -m unittest tests.test_app`: passed, `OK`, 12 tests.

Risks: none known.
