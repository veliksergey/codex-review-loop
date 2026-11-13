#!/usr/bin/env bash
# Prints one Codex flag that turns every configured MCP server off for a single run:
# -c 'mcp_servers={"<id>"={enabled=false},...}'. Servers that plugins provide are left
# out, because the review runs with plugins disabled. Prints nothing when no server is
# configured. Prints nothing and exits non-zero if the server list cannot be read in
# full or a name is not safe to paste.
set -uo pipefail

fail() { echo "mcp-off-flags: $1" >&2; exit 1; }

json="$(codex mcp list --json --disable plugins 2>/dev/null)" ||
  fail "codex mcp list failed, so the configured MCP servers are unknown"

# Checks that the reply is one JSON array of objects and prints the name of each
# object, one per line. Anything else, an object without exactly one readable name
# included, is an error: a list read only in part would leave a server on.
names="$(printf '%s\n' "$json" | LC_ALL=C awk '
  function closed_value() { if (depth == 0) done = 1; else st[depth] = "next" }
  { text = text $0 "\n" }
  END {
    n = length(text); i = 1; depth = 0; done = 0; bad = 0; count = 0
    while (i <= n && !bad) {
      c = substr(text, i, 1)
      if (index(" \t\r\n", c) > 0) { i++; continue }
      if (done || (depth == 0 && c != "[")) { bad = 1; break }
      cur = (depth == 0) ? "value" : st[depth]
      if (c == "\"") {
        tok = ""; esc = 0; shut = 0; i++
        while (i <= n) {
          ch = substr(text, i, 1)
          if (ch == "\\") { esc = 1; i += 2; continue }
          if (ch == "\"") { shut = 1; i++; break }
          tok = tok ch; i++
        }
        if (!shut) { bad = 1; break }
        if (depth > 0 && stack[depth] == "{" && (cur == "key" || cur == "first")) {
          key[depth] = tok; st[depth] = "colon"
        } else if (cur == "value" || (cur == "first" && stack[depth] == "[")) {
          if (depth == 1) { bad = 1; break }
          if (depth == 2 && key[2] == "name") {
            if (esc || tok == "" || named) { bad = 1; break }
            name = tok; named = 1
          }
          closed_value()
        } else { bad = 1; break }
        continue
      }
      if (c == "{" || c == "[") {
        if (!(cur == "value" || (cur == "first" && stack[depth] == "["))) { bad = 1; break }
        if ((depth == 0 && c != "[") || (depth == 1 && c != "{")) { bad = 1; break }
        depth++; stack[depth] = c; st[depth] = "first"
        if (depth == 2) named = 0
        i++; continue
      }
      if (c == "}" || c == "]") {
        if (depth == 0 || stack[depth] != (c == "}" ? "{" : "[")) { bad = 1; break }
        if (!(cur == "first" || cur == "next")) { bad = 1; break }
        if (depth == 2) { if (!named) { bad = 1; break }; names[++count] = name }
        depth--; i++; closed_value(); continue
      }
      if (c == ":") { if (cur != "colon") { bad = 1; break }; st[depth] = "value"; i++; continue }
      if (c == ",") {
        if (cur != "next") { bad = 1; break }
        st[depth] = (stack[depth] == "{") ? "key" : "value"; i++; continue
      }
      # A number or one of true, false, null.
      if (!(cur == "value" || (cur == "first" && stack[depth] == "[")) || depth == 1) { bad = 1; break }
      rest = substr(text, i, 64)
      if (match(rest, /^(true|false|null)/) || match(rest, /^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?/)) {
        i += RLENGTH; closed_value(); continue
      }
      bad = 1
    }
    if (bad || !done || depth != 0) exit 3
    for (k = 1; k <= count; k++) print names[k]
  }')" || fail "codex mcp list did not print a list of servers that can be read in full"

# One inline table for all servers. Codex keeps only the last -c mcp_servers={...}
# override, and splits a key written as mcp_servers."a.b" at the dot.
entries=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  # Only letters, digits, underscore, hyphen, and dot can be pasted into a command line.
  case "$name" in *[!A-Za-z0-9_.-]*) fail "the MCP server name is not safe to pass on a command line" ;; esac
  entries="$entries${entries:+,}\"$name\"={enabled=false}"
done <<EOF
$names
EOF

[ -z "$entries" ] || printf "%s\n" "-c 'mcp_servers={$entries}'"
