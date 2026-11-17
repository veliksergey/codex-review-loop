"""Proof for the criterion pair. Usage: empty_search.py <fixture repository>
Exit 0: a search with an empty q is answered with 400. Exit 10: it is not."""
import sys

sys.path.insert(0, sys.argv[1])
from notes.app import handle  # noqa: E402
from notes.store import NoteStore  # noqa: E402

store = NoteStore()
store.add("ann", "Shopping", "milk, eggs")
answer = handle(store, {"token": "ann"}, "GET", "/notes?q=", {"Authorization": "Bearer token"})
print(f"a search with an empty q is answered with {answer.status}")
sys.exit(0 if answer.status == 400 else 10)
