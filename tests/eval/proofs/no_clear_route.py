"""Proof for the pair about an addition beyond the request.
Usage: no_clear_route.py <fixture repository>
Exit 0: DELETE /notes is not a route, as before the change. Exit 10: it removes notes."""
import sys

sys.path.insert(0, sys.argv[1])
from notes.app import handle  # noqa: E402
from notes.store import NoteStore  # noqa: E402

store = NoteStore()
store.add("ann", "Shopping", "milk, eggs")
answer = handle(store, {"token": "ann"}, "DELETE", "/notes", {"Authorization": "Bearer token"})
left = len(store.list_for_owner("ann"))
print(f"DELETE /notes is answered with {answer.status} and leaves {left} note(s)")
sys.exit(0 if answer.status == 405 and left == 1 else 10)
