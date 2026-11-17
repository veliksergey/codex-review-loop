"""Request handling for the notes service: one function per route, no framework."""
import json
import re
from urllib.parse import urlsplit

MAX_TITLE = 200
MAX_BODY = 10000
NOTE_ID = re.compile(r"[0-9]{1,9}")


class Response:
    def __init__(self, status, body=None, headers=None):
        self.status = status
        self.headers = {"Content-Type": "application/json"}
        self.headers.update(headers or {})
        self.body = body


def _json(status, data):
    return Response(status, json.dumps(data))


def _error(status, message):
    return _json(status, {"error": message})


def _user(sessions, headers):
    """The user of the session a request carries, or None."""
    value = (headers or {}).get("Authorization", "")
    if not value.startswith("Bearer "):
        return None
    return sessions.get(value[len("Bearer "):])


def _show(note):
    return {"id": note.id, "title": note.title, "body": note.body}


def handle(store, sessions, method, target, headers=None, body=None):
    """Answers one request. `body` is the parsed JSON body, or None."""
    user = _user(sessions, headers)
    if user is None:
        return _error(401, "sign in first")
    parts = urlsplit(target)
    segments = [segment for segment in parts.path.split("/") if segment]
    if segments == ["notes"]:
        if method == "GET":
            return _list(store, user)
        if method == "POST":
            return _create(store, user, body)
        return _error(405, "method not allowed")
    if len(segments) == 2 and segments[0] == "notes" and NOTE_ID.fullmatch(segments[1]):
        note_id = int(segments[1])
        if method == "GET":
            return _read(store, user, note_id)
        if method == "DELETE":
            return _delete(store, user, note_id)
        return _error(405, "method not allowed")
    return _error(404, "no such page")


def _list(store, user):
    return _json(200, {"items": [_show(note) for note in store.list_for_owner(user)]})


def _create(store, user, body):
    if not isinstance(body, dict):
        return _error(400, "send a JSON object")
    title, text = body.get("title"), body.get("body", "")
    if not isinstance(title, str) or not title.strip() or len(title) > MAX_TITLE:
        return _error(400, f"title must be a text of 1 to {MAX_TITLE} characters")
    if not isinstance(text, str) or len(text) > MAX_BODY:
        return _error(400, f"body must be a text of at most {MAX_BODY} characters")
    return _json(201, _show(store.add(user, title.strip(), text)))


def _read(store, user, note_id):
    note = store.get(note_id)
    # A note of another user is answered like a note that does not exist.
    if note is None or note.owner != user:
        return _error(404, "no such note")
    return _json(200, _show(note))


def _delete(store, user, note_id):
    note = store.get(note_id)
    if note is None or note.owner != user:
        return _error(404, "no such note")
    store.remove(note_id)
    return Response(204)
