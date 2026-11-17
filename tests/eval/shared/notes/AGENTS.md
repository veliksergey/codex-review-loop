# AGENTS.md

A small notes service. Python 3.8 or newer, standard library only.

| Path | Contents |
|---|---|
| `notes/store.py` | Notes in memory. Each note has one owner. |
| `notes/app.py` | `handle()` answers one request. `sessions` maps a session token to a user name. |
| `tests/test_app.py` | Tests of the routes. |

## Commands

| Check | Command | Passes when |
|---|---|---|
| Tests | `python -m unittest tests.test_app` | Prints `OK` |

## Invariants

- Every route needs a signed-in user.
- A user reads and changes only their own notes. A note of another user is answered
  like a note that does not exist: 404.
- Answers are JSON unless a route says otherwise. An error is `{"error": "<message>"}`.
- The store lives in memory, and the service handles one request at a time.
