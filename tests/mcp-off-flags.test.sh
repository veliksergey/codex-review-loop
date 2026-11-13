#!/usr/bin/env bash
# Regression test for plugins/codex-review-loop/skills/codex-loop/mcp-off-flags.sh.
# Run from anywhere: bash tests/mcp-off-flags.test.sh
# MCP_OFF_FLAGS=<script> runs the same cases against another implementation.
# A stand-in named codex is put first on PATH for every case but the last one, which
# asks the real Codex CLI, if it is installed, whether it accepts the flag.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mf="${MCP_OFF_FLAGS:-$here/../plugins/codex-review-loop/skills/codex-loop/mcp-off-flags.sh}"
fails=0
skips=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
skip() { echo "skip - $1"; skips=$((skips + 1)); }

tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT

# The stand-in prints the file reply.json, exits with the number in reply.rc, and
# records its arguments.
mkdir -p "$tmp/bin" || abort "mkdir bin"
cat > "$tmp/bin/codex" <<EOF || abort "write the stand-in"
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$tmp/args"
cat "$tmp/reply.json"
exit "\$(cat "$tmp/reply.rc")"
EOF
chmod +x "$tmp/bin/codex" || abort "chmod the stand-in"
reply() { printf '%s' "$1" > "$tmp/reply.json"; printf '%s' "${2:-0}" > "$tmp/reply.rc"; }
run() { out="$(PATH="$tmp/bin:$PATH" bash "$mf" 2>/dev/null)"; rc=$?; }
# prints <name> <flag>: the last run must have printed exactly that flag and exited 0.
prints() {
  if [ $rc -eq 0 ] && [ "$out" = "$2" ]; then pass "$1"; else fail "$1: exit $rc, output: $out"; fi
}
# refused <name>: the last run must have failed without printing anything.
refused() {
  if [ $rc -ne 0 ] && [ -z "$out" ]; then pass "$1: exits non-zero and prints nothing"
  else fail "$1: exit $rc, output: $out"; fi
}

# Two servers, printed the way the CLI prints them. The nested key called name, the
# braces and quotes inside values, and the other value types must not be taken for a
# server or break the reading.
reply '[
  {
    "name": "first_one",
    "enabled": true,
    "disabled_reason": null,
    "transport": {
      "type": "stdio",
      "command": "run {x} [y] \"z\"",
      "args": ["a", 1, -2.5e3, true, false, null, []],
      "env": { "name": "not-a-server", "OTHER": "} ] \\" }
    },
    "startup_timeout_sec": 10.5,
    "auth_status": "unsupported"
  },
  {
    "name": "second-2",
    "enabled": false,
    "transport": { "type": "stdio", "command": "c", "env": {} }
  }
]'
run
prints "two servers: one flag that names both, nested name ignored" \
  "-c 'mcp_servers={\"first_one\"={enabled=false},\"second-2\"={enabled=false}}'"

if [ "$(cat "$tmp/args")" = "mcp list --json --disable plugins" ]; then
  pass "asks Codex for the server list with plugins disabled"
else
  fail "unexpected Codex arguments: $(cat "$tmp/args")"
fi

reply '[{"name":"solo","enabled":true,"transport":{"env":{"name":"x"}}}]'
run; prints "compact JSON on one line" "-c 'mcp_servers={\"solo\"={enabled=false}}'"

reply '[]'
run; prints "no server configured: prints nothing and exits 0" ""

# A dot is kept inside the quoted key of the one table. Codex splits a key written
# as mcp_servers."a.b" at the dot, so no flag per server can carry it.
reply '[{"name": "a.b"}, {"name": "plain"}]'
run; prints "a name with a dot keeps its dot" "-c 'mcp_servers={\"a.b\"={enabled=false},\"plain\"={enabled=false}}'"

# A name that could end the quoting or start another command is refused, and so is
# the whole flag, the safe names in it included.
reply '[{"name": "good"}, {"name": "x'"'"'; touch '"$tmp"'/pwned; '"'"'"}]'
run; refused "a name with a quote and a command"
reply '[{"name": "has space"}]'
run; refused "a name with a space"
reply '[{"name": "a$(id)"}]'
run; refused "a name with a command substitution"
reply '[{"name": "back\\slash"}]'
run; refused "a name with a backslash"
reply '[{"name": "q\"uote"}]'
run; refused "a name with an escaped quote"
if [ -e "$tmp/pwned" ]; then fail "a server name was executed"; else pass "no server name was executed"; fi

# A server that cannot be named cannot be turned off, so the list is not usable.
reply '[{"name": ""}, {"name": "good"}]'
run; refused "an empty name"
reply '[{"name": null}]'
run; refused "a name that is null"
reply '[{"name": 7}]'
run; refused "a name that is a number"
reply '[{"enabled": true}, {"name": "good"}]'
run; refused "a server without a name"
reply '[{"name": "one", "name": "two"}]'
run; refused "a server with two names"
reply '[{"name": {"name": "inner"}}]'
run; refused "a name that is an object"

# The reply has to be one whole JSON array of objects.
reply '[{"name": "good"}] garbage'
run; refused "text after the list"
reply '[{"name": "a"}] [{"name": "b"}]'
run; refused "two lists"
reply '["good"]'
run; refused "a list of strings"
reply '[1]'
run; refused "a list of numbers"
reply '[[{"name": "x"}]]'
run; refused "a list inside the list"
reply '[{"name": "x"},]'
run; refused "a comma before the end of the list"
reply '[{"name": "x" "enabled": true}]'
run; refused "a missing comma"
reply '[{"name": "x", }]'
run; refused "a comma before the end of a server"
reply '[{"name" "x"}]'
run; refused "a missing colon"
reply '[{"name": "x"}}]'
run; refused "an unbalanced brace"
reply '{"servers": [{"name": "x"}]}'
run; refused "an object in place of the list"
reply '"x"'
run; refused "a string in place of the list"
reply 'error: not logged in'
run; refused "a reply that is not JSON"
reply '[{"name": "x"}, {"name": "y"'
run; refused "a reply that is cut off"
reply '[{"name": "x'
run; refused "a reply cut off inside a name"
reply ''
run; refused "an empty reply"
reply '[{"name": "x"}]' 1
run; refused "Codex exits non-zero"

# Without Codex on PATH nothing can be listed. Only the system folders stay on PATH.
if PATH="/usr/bin:/bin" command -v codex >/dev/null 2>&1; then
  skip "Codex is not installed: the system folders hold a codex command"
else
  out="$(PATH="/usr/bin:/bin" bash "$mf" 2>/dev/null)"; rc=$?
  refused "Codex is not installed"
fi

# The real Codex CLI must accept the flag and turn every server off, the one with a
# dot included. A temporary Codex home holds three made-up servers; nothing of the
# user's own configuration is read or changed.
if command -v codex >/dev/null 2>&1; then
  home="$tmp/codex-home"
  mkdir -p "$home" || abort "mkdir codex-home"
  printf '[mcp_servers.plain]\ncommand = "echo"\n\n[mcp_servers."a.b"]\ncommand = "echo"\n\n[mcp_servers.third]\ncommand = "echo"\n' \
    > "$home/config.toml" || abort "write the temporary config"
  listed="$(CODEX_HOME="$home" codex mcp list --json --disable plugins 2>/dev/null)"
  if [ "$(printf '%s\n' "$listed" | grep -c -E '"enabled": ?true')" -ne 3 ]; then
    skip "the real Codex CLI: it does not list the three made-up servers as enabled"
  else
    flag="$(CODEX_HOME="$home" bash "$mf" 2>/dev/null)"; rc=$?
    # The shell undoes the quoting of the flag, as it does in the review command.
    eval "set -- $flag"
    listed="$(CODEX_HOME="$home" codex mcp list --json --disable plugins "$@" 2>/dev/null)"
    on="$(printf '%s\n' "$listed" | grep -c -E '"enabled": ?true')"
    off="$(printf '%s\n' "$listed" | grep -c -E '"enabled": ?false')"
    if [ $rc -eq 0 ] && [ "$on" -eq 0 ] && [ "$off" -eq 3 ]; then
      pass "the real Codex CLI: the flag turns off all three servers, the dotted name included"
    else
      fail "the real Codex CLI: exit $rc, flag: $flag, still enabled: $on, disabled: $off"
    fi
  fi
else
  skip "the real Codex CLI: not installed, so whether it accepts the flag was not checked"
fi

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
elif [ $skips -ne 0 ]; then
  echo "all passed, $skips skipped"
else
  echo "all passed"
fi
