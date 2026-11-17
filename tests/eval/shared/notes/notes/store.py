"""Notes in memory. Every note belongs to one user."""


class Note:
    def __init__(self, note_id, owner, title, body):
        self.id = note_id
        self.owner = owner
        self.title = title
        self.body = body


class NoteStore:
    def __init__(self):
        self._notes = {}
        self._next_id = 1

    def add(self, owner, title, body):
        note = Note(self._next_id, owner, title, body)
        self._notes[note.id] = note
        self._next_id += 1
        return note

    def get(self, note_id):
        """The note with this id, whoever owns it, or None. The caller checks the owner."""
        return self._notes.get(note_id)

    def list_for_owner(self, owner):
        return [note for note in self._notes.values() if note.owner == owner]

    def remove(self, note_id):
        self._notes.pop(note_id, None)
