import json
import unittest

from notes.app import handle
from notes.store import NoteStore

SESSIONS = {"token-ann": "ann", "token-ben": "ben"}


def call(store, token, method, target, body=None):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return handle(store, SESSIONS, method, target, headers, body)


class AppTest(unittest.TestCase):
    def setUp(self):
        self.store = NoteStore()
        self.mine = self.store.add("ann", "Shopping", "milk, eggs")
        self.theirs = self.store.add("ben", "Plans", "a surprise")

    def test_signed_out_is_refused(self):
        self.assertEqual(call(self.store, None, "GET", "/notes").status, 401)
        self.assertEqual(call(self.store, "token-nobody", "GET", "/notes").status, 401)

    def test_list_holds_own_notes_only(self):
        answer = call(self.store, "token-ann", "GET", "/notes")
        self.assertEqual(answer.status, 200)
        self.assertEqual(json.loads(answer.body),
                         {"items": [{"id": self.mine.id, "title": "Shopping", "body": "milk, eggs"}]})

    def test_create(self):
        answer = call(self.store, "token-ann", "POST", "/notes", {"title": " Ideas ", "body": "one"})
        self.assertEqual(answer.status, 201)
        self.assertEqual(json.loads(answer.body)["title"], "Ideas")
        self.assertEqual(len(self.store.list_for_owner("ann")), 2)

    def test_create_refuses_a_bad_note(self):
        for body in (None, {}, {"title": "  "}, {"title": "x" * 201}, {"title": "t", "body": 5},
                     {"title": "t", "body": "x" * 10001}):
            self.assertEqual(call(self.store, "token-ann", "POST", "/notes", body).status, 400, body)
        self.assertEqual(len(self.store.list_for_owner("ann")), 1)

    def test_read_own_note(self):
        answer = call(self.store, "token-ann", "GET", f"/notes/{self.mine.id}")
        self.assertEqual(answer.status, 200)
        self.assertEqual(json.loads(answer.body)["body"], "milk, eggs")

    def test_read_foreign_note_is_not_found(self):
        self.assertEqual(call(self.store, "token-ann", "GET", f"/notes/{self.theirs.id}").status, 404)

    def test_delete_own_note(self):
        self.assertEqual(call(self.store, "token-ann", "DELETE", f"/notes/{self.mine.id}").status, 204)
        self.assertEqual(self.store.list_for_owner("ann"), [])

    def test_delete_foreign_note_is_not_found(self):
        self.assertEqual(call(self.store, "token-ann", "DELETE", f"/notes/{self.theirs.id}").status, 404)
        self.assertEqual(len(self.store.list_for_owner("ben")), 1)

    def test_unknown_method_and_page(self):
        self.assertEqual(call(self.store, "token-ann", "PUT", "/notes").status, 405)
        self.assertEqual(call(self.store, "token-ann", "PUT", f"/notes/{self.mine.id}").status, 405)
        self.assertEqual(call(self.store, "token-ann", "GET", "/other").status, 404)
        self.assertEqual(call(self.store, "token-ann", "GET", "/notes/abc").status, 404)


if __name__ == "__main__":
    unittest.main()
