#!/usr/bin/env bash
# Regression test for plugins/codex-review-loop/skills/codex-loop/tool-flags.sh.
# Run from anywhere: bash tests/tool-flags.test.sh
# TOOL_FLAGS=<script> runs the same cases against another implementation.
# A stand-in named codex is put first on PATH for every case but the last one, which
# runs the real Codex CLI, if it is installed, in a temporary Codex home.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tf="${TOOL_FLAGS:-$here/../plugins/codex-review-loop/skills/codex-loop/tool-flags.sh}"
fails=0
skips=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
skip() { echo "skip - $1"; skips=$((skips + 1)); }

tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT

# The stand-in answers three questions from three files, each with its own exit code:
# the first server list (list), the server list with the flags applied (verify), and
# the tools a session would have (view). It records each call on one line: the number
# of arguments, then every argument between < and >. Two arguments can then not be
# taken for one argument that holds a space.
mkdir -p "$tmp/bin" || abort "mkdir bin"
cat > "$tmp/bin/codex" <<EOF || abort "write the stand-in"
#!/usr/bin/env bash
{ printf '%s:' "\$#"; printf '<%s>' "\$@"; printf '\n'; } >> "$tmp/calls"
case "\$1 \$2" in
  "mcp list") if [ "\$#" -eq 5 ] && [ "\$*" = "mcp list --json --disable plugins" ]; then f=list; else f=verify; fi ;;
  "debug prompt-input") f=view ;;
  *) exit 64 ;;
esac
cat "$tmp/\$f.json"
exit "\$(cat "$tmp/\$f.rc")"
EOF
chmod +x "$tmp/bin/codex" || abort "chmod the stand-in"
answer() { printf '%s' "$2" > "$tmp/$1.json"; printf '%s' "${3:-0}" > "$tmp/$1.rc"; }

# What Codex prints for a session is a list. Its first entry declares tools by name;
# the other entries are messages. One text part, the one that begins with <tools>,
# lists the tools that are loaded on demand. The description of the tool that runs
# scripts declares each tool a script can call. The replies below have that shape.
# scripts: that description, with Codex's own example of a call and one of its own tools.
scripts='Run JavaScript code. Nested tools are on the global `tools` object, for example `await tools.mcp__ologs__get_profile(...)`.\n\n### `exec_command`\nRuns a command.\n\nexec tool declaration:\n```ts\ndeclare const tools: { exec_command(args: {\n  cmd: string;\n}): Promise<{ output: string; }>; };\n```'
# for_scripts <tool>...: the same description, declaring these tools for scripts as well.
for_scripts() {
  local d="$scripts" t
  for t in "$@"; do
    d="$d\\n\\n### \`$t\`\\nDoes something.\\n\\nexec tool declaration:\\n\`\`\`ts\\ndeclare const tools: { $t(args: {}): Promise<CallToolResult>; };\\n\`\`\`"
  done
  printf '%s' "$d"
}
# declared [<namespace>...]: the entry that declares Codex's own tools, and these. The
# description of the script tool is taken from executor when that is set.
executor=""
declared() {
  local more="" n
  for n in "$@"; do
    more="$more, {\"type\": \"namespace\", \"name\": \"$n\", \"tools\": [{\"type\": \"function\", \"name\": \"run\"}]}"
  done
  printf '{"type": "additional_tools", "role": "developer", "tools": [{"type": "namespace", "name": "functions", "description": "Shell tools.", "tools": [{"type": "custom", "name": "exec", "description": "%s"}]}%s]}' "${executor:-$scripts}" "$more"
}
# part <text>: one text part. The text is given as it stands inside a JSON string.
part() { printf '{"type": "input_text", "text": "%s"}' "$1"; }
# on_demand <namespace>...: the text part that lists these as loaded on demand.
on_demand() {
  local body='<tools>\nDeferred tool namespaces:' n
  for n in "$@"; do body="$body\\n- $n: What it does."; done
  part "$body\\n</tools>"
}
# reply <developer parts> [<user parts>] [<declaring entry>]: a whole reply.
reply() {
  printf '[\n  %s,\n  {"type": "message", "role": "developer", "content": [%s]},\n  {"type": "message", "role": "user", "content": [%s]}\n]' \
    "${3:-$(declared)}" "$1" "${2:-$(part check)}"
}
rules="$(part 'You are Codex. Follow the rules.')"
search="$(reply "$rules, $(on_demand mcp__codex_apps__search_service)")"
none="$(reply "$rules")"
# usual: one server that the flags turn off, and web search as the only tool besides
# Codex's own.
usual() {
  answer list '[{"name": "srv", "enabled": true}]'
  answer verify '[{"name": "srv", "enabled": false}]'
  answer view "$search"
}
run() { : > "$tmp/calls"; out="$(PATH="$tmp/bin:$PATH" bash "$tf" "$@" 2>"$tmp/err")"; rc=$?; }
prints() {
  if [ $rc -eq 0 ] && [ "$out" = "$2" ]; then pass "$1"
  else fail "$1: exit $rc, output: $out, message: $(cat "$tmp/err")"; fi
}
# refused <name> [<text>]: non-zero exit, nothing printed, and the message holds the text.
refused() {
  if [ $rc -eq 0 ] || [ -n "$out" ]; then fail "$1: exit $rc, output: $out"
  elif [ -n "${2:-}" ] && ! grep -qF -- "$2" "$tmp/err"; then
    fail "$1: the message does not hold '$2': $(cat "$tmp/err")"
  else pass "$1: exits non-zero and prints nothing"; fi
}
# asked <name> <argument>...: Codex was called exactly once with exactly these arguments.
asked() {
  local name="$1" want; shift
  want="$(printf '%s:' "$#"; printf '<%s>' "$@")"
  if [ "$(grep -cxF -- "$want" "$tmp/calls")" = 1 ]; then pass "$name"
  else fail "$name: wanted $want, the calls were: $(tr '\n' ' ' < "$tmp/calls")"; fi
}

on="--disable plugins -c 'apps._default.enabled=false' -c 'apps.connector_openai_search_service.enabled=true'"
srv="-c 'mcp_servers={\"srv\"={enabled=false}}'"
cached="$on -c 'web_search=\"cached\"' $srv"
off="--disable plugins --disable apps -c 'web_search=\"disabled\"' $srv"

usual; run
prints "no argument: the cached mode, web search kept, the server turned off" "$cached"

# Each flag must reach Codex as one argument of its own, with the quoting undone, the
# way the review command passes the printed line.
asked "the servers are listed first, with plugins disabled" mcp list --json --disable plugins
asked "the server list is checked with each flag as one argument" mcp list --json \
  --disable plugins -c apps._default.enabled=false -c apps.connector_openai_search_service.enabled=true \
  -c 'web_search="cached"' -c 'mcp_servers={"srv"={enabled=false}}'
asked "the session's tools are checked with each flag as one argument" debug prompt-input \
  --disable plugins -c apps._default.enabled=false -c apps.connector_openai_search_service.enabled=true \
  -c 'web_search="cached"' -c 'mcp_servers={"srv"={enabled=false}}' check
if [ "$(wc -l < "$tmp/calls")" -eq 3 ]; then pass "Codex is called three times and no more"
else fail "Codex was not called three times: $(tr '\n' ' ' < "$tmp/calls")"; fi
# The printed line, split by a shell as the review command splits it, gives the very
# arguments that were checked.
eval "set -- $out"
asked "the printed line, read by a shell, gives the arguments that were checked" debug prompt-input "$@" check

usual; run cached
prints "cached" "$cached"
usual; run live
prints "live" "$on -c 'web_search=\"live\"' $srv"
asked "live: the session's tools are checked with the live flag" debug prompt-input \
  --disable plugins -c apps._default.enabled=false -c apps.connector_openai_search_service.enabled=true \
  -c 'web_search="live"' -c 'mcp_servers={"srv"={enabled=false}}' check
usual; answer view "$none"; run off
prints "off: the apps feature disabled, no connector kept" "$off"
asked "off: the server list is checked with the off flags" mcp list --json \
  --disable plugins --disable apps -c 'web_search="disabled"' -c 'mcp_servers={"srv"={enabled=false}}'
asked "off: the session's tools are checked with the off flags" debug prompt-input \
  --disable plugins --disable apps -c 'web_search="disabled"' -c 'mcp_servers={"srv"={enabled=false}}' check

usual; answer list '[]'; answer verify '[]'; run
prints "no MCP server configured: no server flag" "$on -c 'web_search=\"cached\"'"
asked "no MCP server configured: Codex is asked without a server flag" debug prompt-input \
  --disable plugins -c apps._default.enabled=false -c apps.connector_openai_search_service.enabled=true \
  -c 'web_search="cached"' check

# Web search can be missing, for example after Codex renames its connector. The review
# then has no web search; nothing that should be off is on.
usual; answer view "$none"; run
prints "no web search in the cached mode still passes" "$cached"
# Web search can be declared outright instead of being loaded on demand.
usual; answer view "$(reply "$rules" "" "$(declared mcp__codex_apps__search_service)")"; run
prints "web search declared outright is kept" "$cached"

# Text that only mentions a tool is not a tool. Instructions may name a connector, in
# the developer's text or the repository's, even inside a copy of a tool list.
mention="$(part 'Never use mcp__codex_apps__github during reviews.')"
usual; answer view "$(reply "$mention, $(on_demand mcp__codex_apps__search_service)")"; run
prints "instructions that name a connector do not stop a review" "$cached"
usual; answer view "$(reply "$mention")"; run off
prints "instructions that name a connector do not stop a review without web search" "$off"
agents='# AGENTS.md instructions\n\n<INSTRUCTIONS>\nTools to avoid:\n- mcp__codex_apps__github: never.\n<tools>\n- mcp__codex_apps__sites: never.\n</tools>\ndeclare const tools: { mcp__codex_apps__pets(args: {}): Promise<unknown>; };\n</INSTRUCTIONS>'
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service)" "$(part "$agents"), $(part check)")"; run
prints "repository instructions that copy a tool list and a declaration do not stop a review" "$cached"
described="$(declared | sed 's/Shell tools[.]/Prefer these over mcp__codex_apps__github./')"
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service)" "" "$described")"; run
prints "a tool description that names a connector does not stop a review" "$cached"
# Only the value of a key called name is a declared name: not a text beside such a
# pair, and not a text inside a list that the key holds.
usual; answer view '[{"type": "additional_tools", "tools": [{"name": "functions"}, "mcp__beside_a_name", {"name": ["mcp__inside_a_list"]}]}]'; run
prints "a text that is not the value of a name key is not a declared name" "$cached"

# A tool that should be off and is still declared. The review must not start, and the
# message names the tool.
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service mcp__codex_apps__other_app)")"; run
refused "a second connector is on" "mcp__codex_apps__other_app"
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__other_app)")"; run
refused "another connector is on in place of web search" "mcp__codex_apps__other_app"
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service_extra)")"; run
refused "a connector whose name only starts like web search" "mcp__codex_apps__search_service_extra"
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service-2)")"; run
refused "a connector whose name goes on after a hyphen" "mcp__codex_apps__search_service-2"
usual; run off
refused "web search is still on in the off mode" "mcp__codex_apps__search_service"
usual; answer view "$(reply "$rules" "" "$(declared mcp__codex_apps__search_service)")"; run off
refused "web search is declared outright in the off mode" "mcp__codex_apps__search_service"
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service mcp__some_server)")"; run
refused "a server's tools are still listed as loaded on demand" "mcp__some_server"
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service)" "" "$(declared mcp__some_server)")"; run
refused "a server's tools are still declared outright" "mcp__some_server"

# A configuration can hide a tool from both lists and leave it to scripts. It is then
# declared only in the description of the script tool, and it is still on.
executor="$(for_scripts mcp__some_server__run)"
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service)")"; run
refused "a server's tool that only scripts can call" "mcp__some_server__run"
usual; answer view "$(reply "$rules")"; run off
refused "a server's tool that only scripts can call, in the off mode" "mcp__some_server__run"
executor="$(for_scripts mcp__codex_apps__other_app_run mcp__codex_apps__other_app_write)"
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service)")"; run
refused "a connector's tools that only scripts can call: the first" "mcp__codex_apps__other_app_run"
refused "a connector's tools that only scripts can call: the second" "mcp__codex_apps__other_app_write"
# Declared for scripts, a tool carries its own name, not its connector's. Web search
# cannot be told apart there, so it stops the review like any other.
executor="$(for_scripts mcp__codex_apps__search_service_web_run)"
usual; answer view "$(reply "$rules")"; run
refused "web search declared for scripts only" "mcp__codex_apps__search_service_web_run"
executor="$scripts"'\n\ndeclare const tools: {mcp__some_server__run(args: {}): Promise<unknown>; };'
usual; answer view "$(reply "$rules, $(on_demand mcp__codex_apps__search_service)")"; run
refused "a declaration for scripts without a space after its brace" "mcp__some_server__run"
executor=""

# A quote or a backslash inside a text must not shift where strings begin and end. Read
# wrongly, the list after such a text would be taken for something else.
tricky="$(part 'Use a 6\" pipe and the folder C:\\tools\\')"
usual; answer view "$(reply "$tricky, $(on_demand mcp__codex_apps__search_service)")"; run
prints "a quote and a backslash in a text: web search alone still passes" "$cached"
usual; answer view "$(reply "$tricky, $(on_demand mcp__codex_apps__other_app)")"; run
refused "a quote and a backslash in a text: a connector after it is still found" "mcp__codex_apps__other_app"

# The same reply without a space or a line break outside its strings.
compact() {
  local list='<tools>\n- '"$1"': x\n</tools>'
  printf '[{"type":"additional_tools","tools":[{"type":"namespace","name":"functions","tools":[{"name":"exec"}]}]},{"type":"message","role":"developer","content":[{"type":"input_text","text":"%s"}]}]' "$list"
}
usual; answer view "$(compact mcp__codex_apps__search_service)"; run
prints "a reply without spaces: web search alone passes" "$cached"
usual; answer view "$(compact mcp__codex_apps__other_app)"; run
refused "a reply without spaces: a connector is still found" "mcp__codex_apps__other_app"
usual; answer view '[{"type":"additional_tools","tools":[{"name":"functions"},{"name":"mcp__some_server"}]}]'; run
refused "a reply without spaces: a declared server is still found" "mcp__some_server"
# A space may also stand between a key and its colon.
usual; answer view '[{"type" : "additional_tools", "tools" : [{"name" : "functions"}, {"name" : "mcp__some_server"}]}]'; run
refused "a reply with a space before each colon: a declared server is still found" "mcp__some_server"

# Windows line endings, here between a key and its value.
usual; answer view "$(printf '[{"type": "additional_tools", "tools": [{"name":\r\n "functions"}, {"name":\r\n "mcp__some_server"}]}]\r\n')"; run
refused "a reply with Windows line endings: a declared server is still found" "mcp__some_server"
# Some awk builds drop the carriage return themselves; there the case above cannot
# tell whether the script handles it.
if [ "$(printf 'ab\r\n' | LC_ALL=C awk '{ print length($0) }')" != 3 ]; then
  skip "the script's own carriage-return handling: this awk drops carriage returns itself"
fi

# A name can be written with JSON escapes; it is the same name.
usual; answer view "$(reply "$rules" "" "$(declared 'mcp\u005f_some_server')")"; run
refused "a declared name written with an escape" "mcp__some_server"
usual; answer view '[{"type": "additional_tools", "tools": [{"name": "functions"}, {"na\u006de": "mcp__some_server"}]}]'; run
refused "a name key written with an escape" "mcp__some_server"
usual; answer view "$(reply "$rules, $(part '\u003ctools\u003e\n- mcp__codex_apps__other_app: x\n\u003c/tools\u003e')")"; run
refused "a list of on-demand tools written with escapes" "mcp__codex_apps__other_app"

# A reply that is cut short may have lost the part that names a tool.
usual; answer view "${search%Follow the rules*}"; run
refused "a reply cut off inside a text" "could not read"
usual; answer view "[$(declared),"; run
refused "a reply cut off between two entries" "could not read"
# Every session has at least its shell tool. A reply that declares no tool at all is
# not a list of tools, so it shows nothing about them.
usual; answer view '[{"type": "message", "role": "developer", "content": [{"type": "input_text", "text": "No tool is shown here."}]}]'; run
refused "a reply that declares no tool at all" "no tool at all"
usual; answer view "$search" 1; run
refused "Codex cannot show the session's tools"
usual; answer view ''; run
refused "Codex shows nothing"
usual; answer view 'error: unknown subcommand'; run
refused "Codex shows something that is not a list"

# An MCP server that the flags did not turn off.
usual; answer verify '[{"name": "srv", "enabled": true}]'; run
refused "a server is still enabled"
usual; answer verify '[{"name":"srv","enabled":true}]'; run
refused "a server is still enabled, compact JSON"
usual; answer verify '[{"name": "srv", "enabled": false}]' 1; run
refused "Codex cannot list the servers with the flags applied"
usual; answer verify 'error'; run
refused "the server list with the flags applied is not a list"
# The enabled server comes first and a long reply follows. A check that stops reading
# at the first match would break the pipe and take that for "no server is on".
pad="$(head -c 200000 /dev/zero | tr '\0' 'x')"
usual; answer verify "[{\"name\": \"srv\", \"enabled\": true}, {\"name\": \"big\", \"enabled\": false, \"pad\": \"$pad\"}]"; run
refused "a server is still enabled at the start of a long reply"
# Where the system lets a writer finish although its reader has left, the case above
# cannot tell the two kinds of check apart.
if (set -o pipefail; printf '%s\n' "x$pad$pad" | grep -q x) 2>/dev/null; then
  skip "an early-exit reader breaking the pipe: this system does not break it"
fi

# The first server list cannot be used.
usual; answer list '[{"name": "srv"}]' 1; run
refused "Codex cannot list the servers"
usual; answer list '[{"name": "bad name"}]'; run
refused "a server name that cannot be passed on a command line"

usual; run sometimes
refused "an unknown mode"
if [ -s "$tmp/calls" ]; then fail "an unknown mode still called Codex: $(cat "$tmp/calls")"
else pass "an unknown mode does not call Codex"; fi

# The real Codex CLI, in a temporary Codex home with three made-up servers and no
# account: the script must find the servers, turn them off, and pass its own checks.
if command -v codex >/dev/null 2>&1; then
  home="$tmp/codex-home"
  mkdir -p "$home" || abort "mkdir codex-home"
  printf '[mcp_servers.plain]\ncommand = "echo"\n\n[mcp_servers."a.b"]\ncommand = "echo"\n\n[mcp_servers.third]\ncommand = "echo"\n' \
    > "$home/config.toml" || abort "write the temporary config"
  out="$(cd "$tmp" && CODEX_HOME="$home" bash "$tf" 2>/dev/null)"; rc=$?
  want="$on -c 'web_search=\"cached\"' -c 'mcp_servers={\"a.b\"={enabled=false},\"plain\"={enabled=false},\"third\"={enabled=false}}'"
  if [ $rc -eq 0 ] && [ "$out" = "$want" ]; then
    pass "the real Codex CLI: three made-up servers are turned off and the checks pass"
  else
    fail "the real Codex CLI: exit $rc, output: $out"
  fi
else
  skip "the real Codex CLI: not installed, so the checks were not run against it"
fi

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
elif [ $skips -ne 0 ]; then
  echo "all passed, $skips skipped"
else
  echo "all passed"
fi
