# Notes

A notes service without a framework. `notes.app.handle()` takes a request and returns a
response; a server in front of it parses the JSON body and passes the headers on.

| Route | Answer |
|---|---|
| `GET /notes` | 200, `{"items": [...]}`: the notes of the signed-in user |
| `POST /notes` | 201 and the new note; 400 when the title or the body is not acceptable |
| `GET /notes/<id>` | 200 and the note; 404 when there is none, or it is another user's |
| `DELETE /notes/<id>` | 204; 404 when there is none, or it is another user's |

A request without a valid session is answered with 401. Run the tests with
`python -m unittest tests.test_app`.
