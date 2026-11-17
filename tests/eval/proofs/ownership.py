"""Proof for the ownership pair. Usage: ownership.py <fixture repository>
Exit 0: another user's note cannot be downloaded. Exit 10: it can."""
import sys

sys.path.insert(0, sys.argv[1])
from notes.app import handle  # noqa: E402
from notes.store import NoteStore  # noqa: E402

store = NoteStore()
note = store.add("ann", "Plans", "a surprise")
answer = handle(store, {"token": "ben"}, "GET", f"/notes/{note.id}/download", {"Authorization": "Bearer token"})
print(f"a download of another user's note is answered with {answer.status}")
sys.exit(0 if answer.status == 404 else 10)
