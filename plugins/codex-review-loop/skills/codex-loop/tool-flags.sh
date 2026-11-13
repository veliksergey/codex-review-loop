#!/usr/bin/env bash
# Prints, on one line, the Codex flags that limit a review to its sandboxed shell and
# web search, after asking Codex whether those flags do what they should.
# Usage: tool-flags.sh [cached|live|off]   the web search mode; cached when left out.
# The check uses Codex's own reading of every configuration layer: a connector that
# any layer turns on by name, or an MCP server the flags leave on, makes this script
# print nothing and exit non-zero, so the review does not start.
set -uo pipefail

fail() { echo "tool-flags: $1" >&2; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || fail "cannot find its own folder"

mode="${1:-cached}"
case "$mode" in
  cached | live)
    # Web search reaches the reviewer as this one connector; the others are turned off.
    flags="--disable plugins -c 'apps._default.enabled=false' -c 'apps.connector_openai_search_service.enabled=true' -c 'web_search=\"$mode\"'"
    allowed="mcp__codex_apps__search_service" ;;
  off)
    flags="--disable plugins --disable apps -c 'web_search=\"disabled\"'"
    allowed="" ;;
  *) fail "unknown web search mode; use cached, live, or off" ;;
esac

mcp="$(bash "$here/mcp-off-flags.sh")" || fail "the configured MCP servers cannot be turned off"
[ -z "$mcp" ] || flags="$flags $mcp"

# The flags are built above from fixed text and from names mcp-off-flags.sh has
# checked, so the shell can undo their quoting.
eval "set -- $flags"

# No MCP server may still be enabled with the flags applied.
servers="$(codex mcp list --json "$@" 2>/dev/null)" || fail "Codex could not list its MCP servers with the flags applied"
case "$servers" in "["*) ;; *) fail "Codex did not print a list of MCP servers" ;; esac
# awk reads the whole reply before it answers; a reader that stops at the first match
# would end the pipe early and, with pipefail, look like "no match".
if printf '%s\n' "$servers" | LC_ALL=C awk '/"enabled"[ \t]*:[ \t]*true/ { on = 1 } END { exit on ? 0 : 1 }'; then
  fail "an MCP server is still on with the flags applied"
fi

# No tool that reaches the model through MCP may be offered except web search. Codex
# names every such tool mcp__<source>, whether a connector, a plugin, or a configured
# server brings it.
view="$(codex debug prompt-input "$@" check 2>/dev/null)" || fail "Codex could not show which tools a session would have; update Codex"
case "$view" in "["*) ;; *) fail "Codex did not print the tools a session would have" ;; esac
# Codex's reply is JSON, and it declares tools in three places: as the value of a key
# called name, in the text that begins with <tools>, its list of tools loaded on demand,
# and inside a tool description, for scripts. A name that text merely mentions is no tool.
extra="$(printf '%s\n' "$view" | LC_ALL=C awk -v allowed="$allowed" '
  # Undoes the escapes of a JSON string. Anything a tool name cannot hold becomes a space.
  function unesc(s,    out, k, c, v, d, j) {
    out = ""
    while ((k = index(s, "\\")) > 0) {
      out = out substr(s, 1, k - 1); c = substr(s, k + 1, 1); s = substr(s, k + 2)
      if (c == "u") {
        v = 0
        for (j = 1; j <= 4; j++) {
          d = index("0123456789abcdef", tolower(substr(s, j, 1)))
          v = (d > 0 && v >= 0) ? v * 16 + d - 1 : -1
        }
        c = (v > 32 && v < 127) ? sprintf("%c", v) : " "; s = substr(s, 5)
      } else if (c != "\"" && c != "\\" && c != "/") c = " "
      out = out c
    }
    return out s
  }
  function note(name) { if (!(name in seen)) { seen[name] = 1; order[++count] = name } }
  # A string that is a value, with the key it belongs to when it has one.
  function value(key, raw,    text, found) {
    if (key == "name") { tools++; text = unesc(raw); if (text ~ /^mcp__/ && text != allowed) note(text) }
    # A tool that scripts can call is declared in a description. There the name is the
    # tool, not its source, so web search cannot be told apart and none is let through.
    if (key == "description") {
      text = unesc(raw)
      while (match(text, /declare const tools: *[{] *mcp__[A-Za-z0-9_$-]+/)) {
        found = substr(text, RSTART, RLENGTH); text = substr(text, RSTART + RLENGTH)
        note(substr(found, index(found, "mcp__")))
      }
    }
    if (unesc(substr(raw, 1, 80)) ~ /^ *<tools>/) {
      text = unesc(raw)
      while (match(text, /mcp__[A-Za-z0-9_-]+/)) {
        found = substr(text, RSTART, RLENGTH); text = substr(text, RSTART + RLENGTH)
        if (found != allowed) note(found)
      }
    }
  }
  # A quote ends each record, so records alternate: the text between two strings, then
  # a string. One field per line keeps a long string from becoming thousands of fields.
  BEGIN { RS = "\""; FS = "\n" }
  !instring {
    # The string before this text is a key when a colon follows it.
    if ($0 ~ /^[ \t\r\n]*:/) key = ($0 ~ /^[ \t\r\n]*:[ \t\r\n]*$/) ? unesc(tok) : ""
    else { value(key, tok); key = "" }
    n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (c == "[" || c == "{") depth++; else if (c == "]" || c == "}") depth--
    }
    instring = 1; tok = ""
    next
  }
  {
    tok = tok $0
    # An odd number of backslashes before the quote makes the quote part of the string.
    if (match($0, /\\+$/) && RLENGTH % 2 == 1) { tok = tok "\""; next }
    instring = 0
  }
  END {
    # A reply cut short could be missing the part that names a tool.
    if (depth != 0) exit 3
    # Every session has at least its shell tool. None found: this is not a list of tools.
    if (tools == 0) exit 4
    for (k = 1; k <= count; k++) print order[k]
  }')"
case $? in
  0) ;;
  4) fail "Codex listed no tool at all, so the tools a session would have cannot be checked; update Codex or this plugin" ;;
  *) fail "could not read the tools Codex showed" ;;
esac
[ -z "$extra" ] || fail "still offered to the reviewer with the flags applied: $(printf '%s' "$extra" | tr '\n' ' ')"

printf '%s\n' "$flags"
