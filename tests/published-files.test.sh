#!/usr/bin/env bash
# Regression test for tests/published-files.sh. Run from anywhere:
#   bash tests/published-files.test.sh
# PUBLISHED_FILES=<script> runs the same cases against another implementation.
# Every repository below is made in a temporary folder, except in the last case.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pf="${PUBLISHED_FILES:-$here/published-files.sh}"
fails=0
skips=0

abort() { echo "setup failed: $1" >&2; exit 2; }
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
skip() { echo "skip - $1"; skips=$((skips + 1)); }

tmp="$(mktemp -d)" || abort "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || abort "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT
export GIT_CEILING_DIRECTORIES="$tmp"

g() { git -C "$repo" -c user.name=test -c user.email=test -c core.autocrlf=false "$@"; }
repo="$tmp/repo"
mkdir -p "$repo" || abort "mkdir"
g init -q . || abort "git init"
# The ignore rules of the person who runs this test do not reach the files it writes.
: > "$tmp/no-ignore" || abort "write"
g config core.excludesFile "$tmp/no-ignore" || abort "git config"

# Joined when the test runs, so this file holds no text that the check reports.
U="Users"
u="users"
H="home"
at="@"
clean="no home-folder path or e-mail address found"

# check [folder]: runs the script; its output is in $out and its exit code in $rc.
check() { out="$(bash "$pf" "${1:-$repo}" 2>"$tmp/err")"; rc=$?; }
# fresh: a repository with nothing staged and no file.
fresh() {
  { g rm -r -q -f --cached --ignore-unmatch . &&
    find "$repo" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf -- {} +; } || abort "empty the repository"
}
# note <line>: a file, notes.md, whose third line is the given text.
note() { fresh; printf 'first\nsecond\n%s\nlast\n' "$1" > "$repo/notes.md" || abort "write notes.md"; }
# reports <kind> <name> <line>: the line is reported with its place. A case is named by
# what the line is, so the made-up text itself is not printed with the results.
reports() {
  note "$3"; check
  if [ $rc -eq 1 ] && [ "$out" = "notes.md:3: $1" ]; then pass "reported as $1: $2"
  else fail "reported as $1: $2: exit $rc, output: $out"; fi
}
# allows <name> <line>: the line is not reported.
allows() {
  note "$2"; check
  if [ $rc -eq 0 ] && [ "$out" = "$clean" ]; then pass "not reported: $1"
  else fail "not reported: $1: exit $rc, output: $out"; fi
}

# --- A home folder with a name in it ----------------------------------------------------
kind="home-folder path"
reports "$kind" "a macOS home folder in a sentence" "see /$U/alex/notes.txt for more"
reports "$kind" "a Linux home folder at the start of a line" "/$H/alex/project"
reports "$kind" "a home folder after an equals sign" "HOME=/$H/alex"
reports "$kind" "a home folder in quotes, with nothing below it" "open \"/$U/alex\" first"
reports "$kind" "a home folder in brackets" "(/$H/alex)"
reports "$kind" "a home folder in square brackets" "[/$H/alex]"
reports "$kind" "a home folder in braces" "{/$U/alex}"
reports "$kind" "a home folder in backticks" "\`/$U/alex\`"
reports "$kind" "a home folder in a table cell" "|/$H/alex|"
reports "$kind" "a home folder in a file URL" "file:///$U/alex/page.html"
reports "$kind" "a Linux home folder in a file URL" "file:///$H/alex/page.html"
reports "$kind" "a Windows home folder" "C:\\$U\\alex\\notes.txt"
reports "$kind" "a Windows home folder in small letters" "c:\\$u\\alex"
reports "$kind" "a Windows home folder with forward slashes, on another drive" "D:/$U/alex/notes.txt"
reports "$kind" "a Windows home folder with forward slashes, in small letters" "c:/$u/alex"
reports "$kind" "a Windows home folder with doubled backslashes" "\"C:\\\\$U\\\\alex\\\\notes\""
reports "$kind" "a home folder as Git Bash spells it" "/c/$U/alex/notes.txt"
reports "$kind" "a home folder as Git Bash spells it, in small letters" "cd /c/$u/alex"
reports "$kind" "a home folder as WSL spells it" "/mnt/c/$U/alex"
reports "$kind" "a home folder as Cygwin spells it" "/cygdrive/d/$U/alex"
reports "$kind" "a name that starts with an underscore" "/$U/_build/out"
reports "$kind" "a name that starts with a digit" "/$H/9lives"
reports "$kind" "a name that starts with a letter outside ASCII" "$(printf '/%s/\303\251lodie/project' "$U")"
reports "$kind" "a Windows home folder with such a name" "$(printf 'C:\\%s\\\303\251lodie\\project' "$U")"
reports "$kind" "a home folder in the first line of a script" "#!/$H/alex/bin/python"
reports "$kind" "a home folder with escaped slashes" "\"\\/$H\\/alex\\/notes\""
reports "$kind" "a Windows home folder with two forward slashes" "C://$U/alex"
reports "$kind" "a home folder in a quote inside another quote" "'\"/$H/alex\"'"
reports "$kind" "a file URL with a host" "file://localhost/$U/alex/page.html"
reports "$kind" "a file URL of a Windows folder" "file:///C:/$U/alex/page.html"
reports "$kind" "a home folder before a question mark" "/$H/alex/page?x=1"
reports "$kind" "a home folder before a URL in the same word" "/$H/alex,https://site.example/"
reports "$kind" "a home folder after a URL on the same line" "https://site.example/ and /$H/alex"
reports "$kind" "a home folder in escaped quotes" "run \\\"/$H/alex\\\" now"
reports "$kind" "a home folder in single quotes" "'/$H/alex'"
reports "$kind" "a file URL in capitals" "FILE:///$U/alex/page.html"
reports "$kind" "a file URL after an underscore" "see_file:///$U/alex/page.html"
reports "$kind" "a file URL after another URL in the same word" "\"https://a.example/x\",\"file:///$U/alex/x\""
reports "$kind" "a Windows home folder in small letters in quotes" "\"c:\\$u\\alex\""
reports "$kind" "a home folder after a URL in the same word" "{\"url\":\"https://site.example/a\",\"dir\":\"/$H/alex\"}"
reports "$kind" "a home folder after a URL in single quotes in the same word" "{'url':'https://site.example/a','dir':'/$H/alex'}"
reports "$kind" "a home folder after a URL in backticks in the same word" "\`https://site.example/a\`,\`/$H/alex\`"
reports "$kind" "a home folder after a URL in angle brackets" "<https://site.example/a>/$H/alex"
reports "$kind" "a home folder between the tags of a link" "<a href=\"https://site.example/\">/$H/alex</a>"
reports "$kind" "a home folder after a query in the same word" "{\"next\":\"/page?x=1\",\"dir\":\"/$H/alex\"}"
reports "$kind" "a home folder in a string with a letter before its quote" "r\"/$H/alex/project\""
reports "$kind" "a home folder in a string with a letter before a single quote" "r'/$H/alex/project'"
reports "$kind" "a home folder in a formatted string" "f\"/$U/alex/{name}\""
reports "$kind" "a home folder in a string joined to a variable" "\$ROOT\"/$H/alex\""
reports "$kind" "a home folder after a quoted command that holds a quote" "\"\$(cat \"/$H/alex/notes\")\""
reports "$kind" "a home folder read by a quoted command" "value=\"\$(cat /$H/alex/notes)\""
reports "$kind" "a home folder in a quoted command with a path after it" "\"\$(cat /$H/alex/notes)\"/sub"
reports "$kind" "a home folder as the default of a quoted variable" "value=\"\${ROOT:-/$H/alex}\""
reports "$kind" "a home folder as the default of a variable without a colon" "\${ROOT-/$H/alex}"
reports "$kind" "a removed line of a diff that starts with a home folder" "-/$H/alex/old.txt"
reports "$kind" "a home folder right after the letter of an option" "cc -I/$H/alex/include main.c"
reports "$kind" "a home folder after a comma and the letter of an option" "-Wl,-L/$U/alex/lib"
reports "$kind" "a Windows home folder in small letters after the letter of an option" "cl -Ic:\\$u\\alex\\include"
reports "$kind" "a home folder after an escaped line break" "{\"log\":\"start\\n/$H/alex/project\"}"
reports "$kind" "a home folder after an escaped tab" "{\"log\":\"start\\t/$H/alex/project\"}"
reports "$kind" "a home folder after an escaped carriage return" "{\"log\":\"start\\r/$H/alex/project\"}"
reports "$kind" "a Windows home folder in small letters after an escaped line break" "{\"log\":\"start\\nc:\\\\$u\\\\alex\"}"
reports "$kind" "a Windows home folder whose name starts with n" "C:\\$U\\nina\\notes"
reports "$kind" "a Windows home folder in small letters whose name starts with t" "c:\\$u\\tom"
reports "$kind" "a Windows home folder whose name starts with r" "C:\\$U\\rita"
reports "$kind" "an added line of a diff that starts with a home folder" "+/$H/alex/new.txt"
reports "$kind" "a home folder as the other value of a shell variable" "\${ROOT:+/$H/alex}"
reports "$kind" "a home folder as the other value of a variable without a colon" "\${ROOT+/$H/alex}"
reports "$kind" "a home folder in a comment without a space" "#/$H/alex/data"
reports "$kind" "a home folder cut off a shell variable with two number signs" "\${PWD##/$H/alex/}"
reports "$kind" "a home folder in the first line of a script, in quotes" "\"#!/$H/alex/bin/python\""
reports "$kind" "a home folder in bold" "**/$H/alex/notes**"
reports "$kind" "a Windows home folder in small letters after a slash and the letter of an option" "cl /Ic:\\$u\\alex\\include /c source.cpp"
reports "$kind" "a Windows home folder in small letters after a slash and two letters of an option" "cl /Foc:\\$u\\alex\\out"
reports "$kind" "a home folder in a template string after a backtick in quotes" "const mark = \"\`\"; const dir = \`/$H/alex/project\`;"
reports "$kind" "a home folder in a code span after another code span" "\`a\` and \`/$H/alex\`"
reports "$kind" "a home folder in a code span after a command in backticks with a path below it" "\`pwd\`/build and \`/$H/alex/project\`"
reports "$kind" "a home folder in a code span after a lone backtick" "use the \` mark and \`/$H/alex/x\`"
reports "$kind" "a home folder in a code span after a span that starts with a hyphen" "run \`--help\` or see \`/$U/alex/x\`"
reports "$kind" "a home folder in a quoted string after a quoted variable" "\"\$ROOT\" \"/$H/alex\""
reports "$kind" "a home folder in quotes after a quoted variable and an unquoted one" "cp \"\$SRC\"\$FILE \"/$H/alex/x\""
reports "$kind" "a home folder in quotes after a string that ends in a space and a variable" "cp \"a \" \$ROOT \"/$H/alex\""
reports "$kind" "a home folder in quotes after a path below a quoted variable" "x=\"\$A\"/$H/page y=\"/$H/alex\""
reports "$kind" "a home folder in a quoted string after a string that ends in a variable" "\"build \$ROOT\" \"/$H/alex\""
reports "$kind" "a home folder in quotes after a string that ends in an escaped backslash" "printf \"\\\\\"; cp \"\$SRC\"/file \$FLAGS \"/$H/alex\""
reports "$kind" "a home folder in quotes after a Windows folder that ends in two backslashes" "x=\"C:\\\\dir\\\\\" y=\"\$A\"/$H/page z=\"/$H/alex\""
reports "$kind" "a home folder in a statement after a quoted URL and a semicolon" "URL=\"https://site.example\";HOME=/$H/alex"
reports "$kind" "a home folder in the cell after a URL in a table without spaces" "|https://site.example|/$H/alex/project|"
reports "$kind" "a home folder inside an element with a simple name" "<code>/$H/alex/x</code>"
reports "$kind" "a home folder inside an element of a property list" "<string>/$U/alex/Library</string>"
reports "$kind" "a home folder inside an element whose name is closed in capitals" "<Path>/$H/alex/x</PATH>"
reports "$kind" "a home folder after a list item that stays open" "<li>/$H/alex/notes"
reports "$kind" "a home folder in a code span of two backticks" "\`\`/$H/alex/project\`\`"
reports "$kind" "a home folder in a code span of two backticks after another such span" "\`\`a\`\` and \`\`/$U/alex/project\`\`"
reports "$kind" "a home folder after a text area that is closed on another line" "<textarea>/$H/alex/project"
reports "$kind" "a home folder after an option that is closed on another line" "<option>/$U/alex/project"
reports "$kind" "a home folder after an element that is closed on another line" "<pre>/$H/alex/project"
reports "$kind" "a home folder after a code element that is closed on another line" "<CODE>/$U/alex/project"
reports "$kind" "a home folder in backticks after a link" "[manual](https://site.example),\`/$H/alex\`"
reports "$kind" "a home folder between underscores" "_/$H/alex/project_"
reports "$kind" "a home folder between two underscores on each side" "__/$H/alex/project__"
reports "$kind" "a home folder struck through" "~~/$H/alex/old~~"
reports "$kind" "a home folder after a redirect" "echo done >/$H/alex/out.txt"
reports "$kind" "a home folder after a percent sign that closes no variable" "100% of /$H/alex"
reports "$kind" "a home folder after a carriage return in the middle of a line" "$(printf 'status\r/%s/alex/project' "$H")"
reports "$kind" "a home folder after a form feed" "$(printf 'status\f/%s/alex/project' "$H")"
reports "$kind" "a home folder after a vertical tab" "$(printf 'status\v/%s/alex/project' "$U")"
reports "$kind" "a home folder after a colour code of a terminal" "$(printf '\033[32m/%s/alex/project\033[0m' "$H")"
reports "$kind" "a home folder right after an option of several letters" "cc -isystem/$H/alex/include main.c"
reports "$kind" "a Windows home folder in small letters after such an option" "cl -isystemc:\\$u\\alex\\include"
reports "$kind" "a home folder after the ?= of a Makefile" "PREFIX?=/$H/alex/.local"
reports "$kind" "a Windows home folder in small letters after the ?= of a Makefile" "PREFIX?=c:\\$u\\alex\\local"
reports "$kind" "a home folder after a dotted name and ?=" "install.dir?=/$H/alex/local"
reports "$kind" "a home folder cut off the front of a shell variable" "\${PWD#/$H/alex/}"
reports "$kind" "a home folder in one arm of a choice after a dotted name" "a.b?\"/$H/alex/x\":c"
reports "$kind" "a home folder in quotation marks outside ASCII" "$(printf '\342\200\234/%s/alex\342\200\235' "$H")"
reports "$kind" "a home folder after a dash outside ASCII" "$(printf 'see\342\200\224/%s/alex' "$H")"
reports "$kind" "a home folder after a mark that takes no room" "$(printf 'see\342\201\240/%s/alex' "$H")"
reports "$kind" "a home folder after a Latin-1 mark" "$(printf '\302\253/%s/alex\302\273' "$H")"
reports "$kind" "a home folder after an East Asian mark" "$(printf '\343\200\214/%s/alex\343\200\215' "$U")"
reports "$kind" "a home folder after the mark at the start of a file" "$(printf '\357\273\277/%s/alex' "$H")"
reports "$kind" "a home folder in full-width brackets" "$(printf '\357\274\210/%s/alex\357\274\211' "$H")"
reports "$kind" "a home folder after a full-width colon" "$(printf 'see\357\274\232/%s/alex' "$U")"
reports "$kind" "a home folder in a quoted string that starts with a variable" "\"\$PREFIX /$H/alex\""

# --- What is not such a path ------------------------------------------------------------
allows "a placeholder in angle brackets for the name" "/$U/<you>/notes.txt"
allows "a shell variable for the name" "/$H/\$USER/project"
allows "a shell variable in braces for the name" "/$H/\${USER}/project"
allows "a placeholder for the name in a Windows path" "C:\\$U\\<you>\\notes.txt"
allows "a Windows variable for the name" "C:\\$U\\%USERNAME%\\notes.txt"
allows "a placeholder for the name in a Git Bash path" "/c/$U/<you>"
allows "a placeholder in square brackets for the name" "/$U/[name]/notes.txt"
allows "a placeholder in braces for the name" "/$H/{name}/notes.txt"
allows "the folder of all home folders in backticks" "\`/$U/\` holds them"
allows "the folder of all home folders, without a name" "/$U/ is where macOS keeps home folders"
allows "a folder called home inside a relative path" "docs/$H/alex.md"
allows "a folder called home inside a URL" "https://site.example/$H/alex"
allows "a folder called Users inside a relative path" "src/$U/alex.ts"
allows "paths that start with a dot" "./$H/alex and ../$U/alex"
allows "a path below the tilde" "~/$H/alex"
allows "a path below a shell variable" "\$ROOT/$H/alex"
allows "a path below a shell variable in braces" "\${ROOT}/$H/alex"
allows "a path below the output of a command" "\$(pwd)/$U/alex"
allows "a path below a folder that ends in a digit" "v2/$H/alex"
allows "a path below a folder that ends in an underscore" "build_/$H/alex"
allows "a path below a folder that ends in a hyphen" "build-/$U/alex"
allows "a longer path below a folder that ends in a hyphen" "generated-/$H/templates/page.md"
allows "a path below a folder that ends in a hyphen and a letter" "build-x/$H/alex"
allows "a path below a folder that ends in plus signs" "src/c++/$H/page.md"
allows "a path below a folder that ends in a number sign" "src/c#/$U/page.md"
allows "a path below a folder that ends in a letter outside ASCII" "$(printf 'dossi\303\251/%s/alex' "$H")"
allows "a tab where the name would be" "$(printf '/%s/\tthen more' "$U")"
allows "a home-like path in a URL whose host is an address in brackets" "http://[::1]/$H/page"
allows "a home-like path in the query of a URL" "https://app.example/login?next=/$H/page"
allows "a home-like path in the fragment of a URL" "https://app.example/#/$H/page"
allows "a home-like path in the query of a URL without its host" "/login?next=/$H/page"
allows "a home-like path in the fragment of a URL without its host" "docs/page#/$H/page"
allows "a home-like path in the fragment of a page without a folder" "index.html#/$H/page"
allows "a home-like path in the query of a page without a folder or an ending" "search?next=/$H/page"
allows "a home-like path in the fragment of a page without a folder or an ending" "page#/$H/page"
allows "a home-like path after a character reference in a URL" "https://site.example/a?b=1&amp;c=/$H/page"
allows "a home-like path after a numbered character reference in a URL" "https://site.example/a?b=1&#38;c=/$H/page"
allows "a home-like path in a URL with escaped slashes" "\"https:\\/\\/site.example\\/a=\\/$H\\/page\""
allows "a path below a variable in quotes" "\"\$ROOT\"/$H/page"
allows "a path below a variable in braces in quotes" "\"\${ROOT}\"/$H/page"
allows "a path below a command in quotes" "\"\$(pwd)\"/$U/page"
allows "a path below a quoted command with spaces in it" "\"\$(git rev-parse --show-toplevel)\"/$H/page"
allows "two quoted variables, each with a path below it" "\"\$A\"/$H/page \"\$B\"/$U/page"
allows "a path below a variable between percent signs" "%ROOT%/$H/page"
allows "a path below a variable between at signs" "@PREFIX@/$U/page"
allows "a path below a placeholder in angle brackets" "<repo>/$H/page"
allows "a path below a placeholder of two words" "<your repo>/$H/page"
allows "a path below a placeholder in capitals" "<REPO>/$H/page"
allows "a path below a placeholder that mixes small letters and capitals, in a code span" "\`<RepoRoot>/$H/page\`"
allows "a path below a placeholder in a comment" "<!-- copy from <repo>/$H/page -->"
allows "a home-like path after apostrophes in the query of a URL" "https://site.example/?name='tag'&next=/$H/page"
allows "a home-like path after apostrophes in the query of a quoted URL" "{\"u\":\"https://site.example/?name='tag'&next=/$H/page\"}"
allows "a Windows path below a variable between percent signs" "%PROJECT_ROOT%\\$H\\page"
allows "a Windows path below a variable between percent signs, with the other folder" "%PROJECT_ROOT%\\$U\\page"
allows "a Windows path below a placeholder in angle brackets" "<repo>\\$H\\page"
allows "a Windows path below a quoted variable" "\"\$ROOT\"\\$H\\page"
allows "a Windows path below a command in backticks" "\`pwd\`\\$U\\page"
allows "a home-like path after a semicolon and a name in capitals in the URL of a setting" "base_url=https://site.example/login?lang=en;NEXT=/$H/page"
allows "a path below a quoted variable with a folder after it" "\"\$ROOT/sub\"/$H/page"
allows "a path below a quoted variable with a folder of two words after it" "\"\$ROOT/build output\"/$H/page"
allows "a Windows path below a quoted variable with a folder of two words after it" "\"\$ROOT\\build output\"\\$U\\page"
allows "a path below a command in backticks after a code span" "see \`notes\` and \`pwd\`/$H/page"
allows "a Windows path below a quoted variable between percent signs" "copy \"%PROJECT_ROOT%\"\\$U\\guide.txt out"
allows "a path below a quoted string that ends in a variable" "cp \"build\$ROOT\"/$H/page out"
allows "a path below a quoted variable between at signs" "\"@ROOT@\"/$H/page"
allows "a path below a quoted variable after another string" "echo \"x\" \"\$ROOT\"/$H/page"
allows "a path below a quoted variable inside a string of JSON" "\"cmd\": \"cp \\\"\$ROOT\\\"/$H/page\""
allows "a path below a quoted variable after a string that ends in an escaped backslash" "printf \"\\\\\"; cp \"\$SRC\"/$H/page out"
allows "a path below a string that holds an escaped backslash and an escaped quote" "echo \"a\\\\\\\"b \$X\"/$H/page"
allows "a path below a command in backticks" "\`pwd\`/$H/page"
allows "a path below a command in backticks that is written with its folder" "\`/bin/pwd\`/$H/page"
allows "a path below a command in two backticks" "\`\`pwd\`\`/$H/page"
allows "a home-like path after a semicolon in the URL of a setting" "base_url=https://site.example/login?lang=en;next=/$H/page"
allows "a path below a URL in backticks" "\`https://site.example\`/$H/page"
allows "a path below a star between slashes" "src/*/$H/page"
allows "a path below the first argument of a script in quotes" "\"\$1\"/$H/page"
allows "a path below all arguments of a script in quotes" "\"\$@\"/$U/page"
allows "a home-like path after a semicolon in a URL that nothing encloses" "see https://site.example/login?x=1;next=/$H/page"
allows "a home-like path after a semicolon and a name in capitals in a URL" "https://site.example/login?lang=en;NEXT=/$H/page"
allows "a home-like path after a semicolon in a URL without its host that nothing encloses" "/login?x=1;next=/$H/page"
allows "a home-like path after a character reference in the URL of a variable" "URL=https://site.example/a?b=1&amp;c=/$H/page"
allows "a path below a quoted command that holds another" "\"\$(dirname \"\$(pwd)\")\"/$H/page"
allows "a path below a quoted command that holds two more" "\"\$(a \"\$(b \"\$(c)\")\")\"/$U/page"
allows "a home-like path after a semicolon in a quoted URL" "{\"url\":\"https://site.example/login?x=1;next=/$H/page\"}"
allows "a home-like path after a semicolon in a URL in a link" "[text](https://site.example/a;b=/$H/page)"
allows "a home-like path after a semicolon in the query of a quoted URL without its host" "\"/login?x=1;next=/$H/page\""
allows "the folder of all home folders in quotation marks outside ASCII" "$(printf '\342\200\234/%s/\342\200\235' "$U")"
allows "a path below an index in square brackets" "list[0]/$H/page"
allows "a route with a word and a colon before it" "api:/$u/list"
allows "a URL whose host is called Users" "https://$U/alex"
allows "a URL of another kind whose name ends in file" "profile:///$U/alex"
allows "a path below a URL in quotes" "\"https://site.example\"/$H/page"
allows "a home-like path in the query of a quoted URL without its host" "\"/login?next=/$H/page\""
allows "two URLs in one word, the second with a home-like path after an equals sign" "<https://a.example/x><https://b.example/a=/$H/page>"
allows "two queries in one word, the second with a home-like path" "{\"a\":\"/p?x=1\",\"b\":\"/q?next=/$H/page\"}"
allows "an escape character where the name would be" "$(printf '/%s/\033[0m' "$U")"
allows "a word that ends in home" "my-$H/alex"
allows "absolute paths outside any home folder" "C:\\src\\tool and /usr/bin/env and /dev/null"
allows "the words users and home in a sentence" "the users of the plugin feel at home/office"
allows "a path of a web service that starts with users" "GET /users/42"
allows "a one-letter folder inside a relative path" "lib/c/$U/alex"

# --- An e-mail address ------------------------------------------------------------------
kind="e-mail address"
reports "$kind" "an address in a sentence" "write to alex${at}corp.io"
reports "$kind" "an address with dots and a plus sign, at a host of four labels" "<first.last+tag${at}mail.corp.co.uk>"
reports "$kind" "an address in a mailto link" "mailto:alex_1${at}corp-site.io"
reports "$kind" "an address at a host in capitals" "alex${at}CORP.IO"
reports "$kind" "an address after an allowed one on the same line" "test${at}example.com, alex${at}corp.io"
reports "$kind" "an address after one at a reserved host on the same line" "a${at}host.test and alex${at}corp.io"
reports "$kind" "an address after an SSH remote on the same line" "git${at}host.io:owner/repo and alex${at}corp.io"
reports "$kind" "a host that only ends like an example host" "alex${at}notexample.com"
reports "$kind" "a host that only starts like an example host" "alex${at}example.com.corp.io"
reports "$kind" "a host whose last label only starts like an example host" "alex${at}example.community"
reports "$kind" "a host whose last label only ends like a reserved one" "alex${at}corp.latest"
reports "$kind" "a host with a reserved label in the middle" "alex${at}host.test.corp.io"
reports "$kind" "a local part in quotes" "\"person\"${at}corp.io"
reports "$kind" "a local part in quotes after a word in quotes" "\"name\" \"person\"${at}corp.io"
reports "$kind" "a local part in quotes inside a longer string" "\"\"\"Contact \"person\"${at}corp.io for access.\"\"\""
reports "$kind" "a local part in quotes in a JSON string" "{\"mail\":\"\\\"person\\\"${at}corp.io\"}"
reports "$kind" "a local part in quotes with a space in it" "\"john doe\"${at}corp.io"
reports "$kind" "a local part in quotes with a comma in it" "\"last,first\"${at}corp.io"
reports "$kind" "a local part in quotes with square brackets in it" "\"first[last]\"${at}corp.io"
reports "$kind" "a local part in quotes of letters outside ASCII" "$(printf '"\320\270\320\262\320\260\320\275"%scorp.io' "$at")"
reports "$kind" "an address in quotation marks outside ASCII" "$(printf '\342\200\234alex%scorp.io\342\200\235' "$at")"
reports "$kind" "a host with a letter outside ASCII inside a label" "$(printf 'alex%sm\303\274nchen.de' "$at")"
reports "$kind" "a local part that ends in a letter outside ASCII" "$(printf 'jos\303\251%scorp.io' "$at")"
reports "$kind" "a local part that ends in a mark" "alex!${at}corp.io"
reports "$kind" "a host of letters outside ASCII" "$(printf 'alex%s\320\277\320\276\321\207\321\202\320\260.\321\200\321\204' "$at")"
reports "$kind" "a host in the coded form of such letters" "alex${at}xn--e1afmkfd.xn--p1ai"
reports "$kind" "an address literal in place of a host" "alex${at}[192.168.10.20]"
reports "$kind" "an address literal of the newer kind" "alex${at}[IPv6:2001:db8::1]"
reports "$kind" "an address literal before a colon and a space" "alex${at}[192.168.10.20]: hello"
reports "$kind" "a host that starts with a number" "alex${at}163.com"
reports "$kind" "an address at the end of a sentence" "write to alex${at}corp.io."
reports "$kind" "the user git in a mailto link" "mailto:git${at}corp.io"
reports "$kind" "the user git as the address of an author" "email = git${at}corp.io"
reports "$kind" "the user git as an address on a line that names ssh elsewhere" "{\"service\":\"ssh\",\"email\":\"git${at}corp.io\"}"
reports "$kind" "the user git after the word ssh in a sentence" "we moved from ssh to mail: git${at}corp.io"
reports "$kind" "a user whose name only starts with git" "write to gitea${at}corp.io"
reports "$kind" "a user whose name only ends in git" "write to my.git${at}corp.io"
reports "$kind" "an address before a colon and a space" "write to alex${at}corp.io: no answer yet"
reports "$kind" "an address before a colon at the end of the line" "ask alex${at}corp.io:"
reports "$kind" "an address before a colon and a bracket" "(ask alex${at}corp.io:)"
reports "$kind" "a user name in a URL that is not an SSH one" "https://alex${at}corp.io/owner/repo"
reports "$kind" "an address as the user of such a URL, with a colon after it" "https://alex${at}corp.io:placeholder${at}proxy.example/repo"
reports "$kind" "an address in the path of a URL, with a colon after it" "https://site.example/a/alex${at}corp.io:b"
reports "$kind" "an address in the path of an SSH URL" "ssh://host.io/owner/alex${at}corp.io"
reports "$kind" "an address after an SSH URL on the same line" "ssh://git${at}host.io/owner/repo and alex${at}corp.io"
reports "$kind" "an address after an SSH URL without a user on the same line" "ssh://host.io/owner/repo and alex${at}corp.io"

# --- What is not an address to report ---------------------------------------------------
allows "an address at example.com" "test${at}example.com"
allows "addresses at example.org and below example.net" "a${at}example.org and b${at}sub.example.net"
allows "an example host in capitals" "a${at}EXAMPLE.COM"
allows "a host that ends in .example" "a${at}corp.example"
allows "hosts that end in .test, .invalid, and .localhost" "a${at}host.test and b${at}thing.invalid and c${at}my.localhost"
allows "the user of an SSH remote" "git${at}host.io:owner/repo.git"
allows "the user git at a host, as an SSH login is written" "Test it with ssh -T git${at}host.io first"
allows "the user git in capitals at a host" "ssh GIT${at}host.io"
allows "the user git after ssh with an option and its value" "ssh -p 2222 git${at}host.io"
allows "the user of an SSH remote who is not git" "deploy${at}code.host.io:owner/repo"
allows "an SSH remote whose path starts with a slash" "deploy${at}code.host.io:/srv/repo.git"
allows "an SSH URL" "ssh://git${at}host.io/owner/repo.git"
allows "an SSH URL in capitals" "SSH://git${at}host.io/owner/repo.git"
allows "an SSH URL whose user has a dot in it" "ssh://first.last${at}host.io/owner/repo"
allows "an SSH URL whose host is an address in brackets" "ssh://git${at}[2001:db8::1]/repo.git"
allows "an SSH remote whose host is an address in brackets" "git${at}[2001:db8::1]:repo.git"
allows "an SSH URL with escaped slashes" "\"ssh:\\/\\/git${at}code.host.io\\/owner\\/repo.git\""
allows "an SSH remote after a URL in the same word" "{\"url\":\"https://site.example\",\"remote\":\"git${at}host.io:owner/repo\"}"
allows "an SSH remote after a URL in single quotes in the same word" "{'url':'https://site.example','remote':'git${at}host.io:owner/repo'}"
allows "an SSH URL with another word before it" "git+ssh://deploy${at}code.host.io/owner/repo"
allows "a package with a version" "name${at}1.2.3"
allows "a scoped package with a version" "${at}scope/tool${at}2.0.1"
allows "a version that ends in one letter" "tool${at}2.1.x"
allows "a package with a version that has words in it" "package${at}1.2.3-beta.canary"
allows "a package with a v before such a version" "owner/tool${at}v1.2.3-beta.canary"
allows "a package with two numbers and words" "tool${at}2.1-next.build"
allows "an SSH remote whose path starts with a letter outside ASCII" "$(printf 'git%shost.io:\320\277\321\200\320\276/repo.git' "$at")"
allows "a string that starts with an at sign and a dotted name" "use \"${at}scope.name/tool\" here"
allows "strings joined before a string that starts with an at sign" "\"a\" + \"${at}scope.name\""
allows "two strings in a list, the second starting with an at sign" "[\"${at}scope.one\",\"${at}scope.two\"]"
allows "a quote with nothing in it before an at sign" "\"\"${at}scope.name"
allows "a named value before a string that starts with an at sign" "call(\"a\", key=\"${at}scope.name\")"
allows "strings joined around a name before a string that starts with an at sign" "\"a\"+name+\"${at}scope.name\""
allows "a word between two strings before a string that starts with an at sign" "puts(\"a\" name\"${at}scope.name\")"
allows "a dot between two strings before a string that starts with an at sign" "\"a\".\"${at}scope.name\""
allows "an example address in quotation marks outside ASCII" "$(printf '\342\200\234test%sexample.com\342\200\235' "$at")"
allows "an example address in single quotation marks outside ASCII" "$(printf '\342\200\230test%shost.test\342\200\231' "$at")"
allows "an example address before a comma outside ASCII" "$(printf 'test%sexample.com\357\274\214\350\260\242' "$at")"
allows "an example address before a closing mark and more text" "$(printf 'see test%sexample.com\342\200\235.Then' "$at")"
allows "a decorator in backticks" "\`${at}decorator.name\` marks it"
allows "a decorator in single quotes" "'${at}decorator.name'"
allows "a decorator after an opening bracket" "run(${at}decorator.name)"
allows "an index in square brackets after an at sign" "list${at}[0]"
allows "a name that starts with a dot after an at sign" "name${at}.hidden.file"
allows "a last label with a digit in it" "alex${at}corp.h2"
allows "a last label of one letter" "alex${at}corp.x"
allows "the at sign in shell and git syntax" "\"\$${at}\" and \${list[${at}]} and HEAD${at}{1}"
allows "a user at a host without a dot" "ssh alex${at}server"
allows "an at sign with spaces around it" "a ${at} b.io"
allows "a name that starts with an at sign" "${at}decorator.name"

# --- Both kinds, places, and the files that are read --------------------------------------
note "/$H/alex wrote alex${at}corp.io"; check
if [ $rc -eq 1 ] && [ "$out" = "notes.md:3: home-folder path
notes.md:3: e-mail address" ]; then pass "a line with both kinds is reported as both"
else fail "a line with both kinds: exit $rc, output: $out"; fi

if grep -q "found in the places above" "$tmp/err" && ! grep -q alex "$tmp/err" && [ "${out#*alex}" = "$out" ]; then
  pass "a finding: the message says where to look, and the text is printed nowhere"
else fail "a finding: output: $out, message: $(cat "$tmp/err")"; fi

fresh
mkdir -p "$repo/docs/user guide" || abort "mkdir"
printf 'one\n/%s/alex\nthree\nfour\n/%s/sam\n' "$U" "$H" > "$repo/docs/user guide/a b.md" || abort "write"
printf 'alex%scorp.io\r\nsecond\r\n' "$at" > "$repo/crlf.txt" || abort "write"
printf 'nothing here\n' > "$repo/plain.txt" || abort "write"
check
if [ $rc -eq 1 ] && [ "$out" = "crlf.txt:1: e-mail address
docs/user guide/a b.md:2: home-folder path
docs/user guide/a b.md:5: home-folder path" ]; then
  pass "several files: each place is named once, with its folder and its line"
else fail "several files: exit $rc, output: $out"; fi

fresh
printf 'see /%s/\r\nand C:\\%s\\\r\n' "$U" "$U" > "$repo/crlf.txt" || abort "write"
check
if [ $rc -eq 0 ] && [ "$out" = "$clean" ]; then pass "a Windows line ending where the name would be is not a name"
else fail "a Windows line ending where the name would be: exit $rc, output: $out"; fi
# Some awk builds drop the carriage return themselves; there the case above cannot tell.
if [ "$(printf 'ab\r\n' | LC_ALL=C awk '{ print length($0) }')" != 3 ]; then
  skip "a carriage return where the name would be: this awk drops carriage returns itself"
fi

fresh
mkdir -p "$repo/docs/user guide" || abort "mkdir"
printf 'alex%scorp.io\r\nsecond\r\n' "$at" > "$repo/crlf.txt" || abort "write"
check "$repo/docs/user guide"
if [ $rc -eq 1 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = "crlf.txt:1: e-mail address" ]; then
  pass "started in a subfolder: the whole repository is read"
else fail "started in a subfolder: exit $rc, output: $out"; fi

out="$(cd "$repo/docs" && bash "$pf" 2>/dev/null)"; rc=$?
if [ $rc -eq 1 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = "crlf.txt:1: e-mail address" ]; then
  pass "without a folder: the repository of the current folder is read"
else fail "without a folder: exit $rc, output: $out"; fi

# In a shell script, by its name, a semicolon after the URL or the query of a variable
# ends a statement, whatever the next name looks like. In any other file it is part of
# the URL, also before a name in capitals. A file named .env is a file of settings: a
# URL with a parameter is one value there.
fresh
mkdir -p "$repo/bin" || abort "mkdir"
for name in bin/run.sh settings.properties .env .envrc bin/notes.shell; do
  printf 'url=https://site.example;dir=/%s/alex\nURL=https://site.example/a;NEXT=/%s/alex\nQUERY=/page?x=1;HOME=/%s/alex\n' \
    "$H" "$H" "$H" > "$repo/$name" || abort "write $name"
done
check
if [ $rc -eq 1 ] && [ "$out" = ".envrc:1: home-folder path
.envrc:2: home-folder path
.envrc:3: home-folder path
bin/run.sh:1: home-folder path
bin/run.sh:2: home-folder path
bin/run.sh:3: home-folder path" ]; then
  pass "a statement after the URL of a variable is read in a shell script by its name, and not in .env or another file"
else fail "a statement after the URL of a variable, by file name: exit $rc, output: $out"; fi

# A person's own ignore rules, here for .env, do not hide a file this test writes.
fresh
mkdir -p "$tmp/user" || abort "mkdir"
printf '.env\n' > "$tmp/user/ignore" || abort "write"
git config --file "$tmp/user/.gitconfig" core.excludesFile "$tmp/user/ignore" || abort "git config"
printf 'HOME=/%s/alex\n' "$H" > "$repo/.env" || abort "write"
out="$(HOME="$tmp/user" XDG_CONFIG_HOME="$tmp/user/none" GIT_CONFIG_GLOBAL="$tmp/user/.gitconfig" \
  bash "$pf" "$repo" 2>"$tmp/err")"; rc=$?
if [ $rc -eq 1 ] && [ "$out" = ".env:1: home-folder path" ]; then
  pass "a file of this test is read whatever the ignore rules of the person who runs it"
else fail "a file of this test under a person's own ignore rules: exit $rc, output: $out"; fi

# A line of a shell stands in other files too: in a fenced block of Markdown whose
# language is a shell, and in the value of a run: key. There a semicolon after the URL
# or the query of a variable ends a statement; on every other line it is part of the URL.
fresh
mkdir -p "$repo/.github/workflows" || abort "mkdir"
printf 'text\n```bash\nURL=https://site.example;HOME=/%s/alex\n```\nbase_url=https://site.example/a;next=/%s/page\n```ini\nbase_url=https://site.example/a;next=/%s/page\n```\n~~~console\n$ QUERY=/page?x=1;HOME=/%s/alex\n~~~\n> ```sh\n> URL=https://site.example;HOME=/%s/alex\n> ```\n````md\n```bash\n```\nbase_url=https://site.example/a;next=/%s/page\n````\n```\nbase_url=https://site.example/a;next=/%s/page\n```\n' \
  "$H" "$H" "$H" "$H" "$H" "$H" "$H" > "$repo/README.md" || abort "write"
printf 'jobs:\n  build:\n    steps:\n      - run: URL=https://site.example;HOME=/%s/alex\n      - name: second\n        run: |\n          echo\n\n          URL=https://site.example/a;NEXT=/%s/alex\n        env:\n          args: base_url=https://site.example/login?lang=en;next=/%s/page\n      - run: echo\n        with:\n          args: base_url=https://site.example/login?lang=en;next=/%s/page\n' \
  "$H" "$H" "$H" "$H" > "$repo/.github/workflows/build.yml" || abort "write"
check
if [ $rc -eq 1 ] && [ "$out" = ".github/workflows/build.yml:4: home-folder path
.github/workflows/build.yml:9: home-folder path
README.md:3: home-folder path
README.md:10: home-folder path
README.md:13: home-folder path" ]; then
  pass "a statement after the URL of a variable is read in a fenced block of a shell and under a run key, and on no other line"
else fail "a statement after the URL of a variable, in a block of shell: exit $rc, output: $out"; fi

# A name in angle brackets is an element where it is closed on a later line of the same
# file, and a placeholder where it is not: in a comment, in a code span, in another file.
fresh
printf '<settings>\n  <localRepository>/%s/alex/.m2/repository\n  </localRepository>\n</settings>\n' "$H" \
  > "$repo/settings.xml" || abort "write"
printf '<!-- copy from <repo>/%s/page -->\n<localRepository>/%s/page\n' "$H" "$H" > "$repo/other.xml" || abort "write"
printf 'see `<RepoRoot>/%s/page`\n' "$H" > "$repo/notes.md" || abort "write"
check
if [ $rc -eq 1 ] && [ "$out" = "settings.xml:2: home-folder path" ]; then
  pass "a home folder after an element that is closed on a later line of its file, and nowhere else"
else fail "a home folder after an element closed on a later line: exit $rc, output: $out"; fi
# The same for the staged text of a file that was cleaned in the folder.
g add settings.xml || abort "git add"
printf '<settings>\n</settings>\n' > "$repo/settings.xml" || abort "write"
check
if [ $rc -eq 1 ] && [ "$out" = "settings.xml:2: home-folder path" ]; then
  pass "an element closed on a later line is read in the staged text too"
else fail "an element closed on a later line, staged: exit $rc, output: $out"; fi

# Untracked, staged, and committed files are all read.
note "alex${at}corp.io"; g add notes.md || abort "git add"; check
if [ $rc -eq 1 ] && [ "$out" = "notes.md:3: e-mail address" ]; then pass "a staged file is read, and its place is named once"
else fail "a staged file: exit $rc, output: $out"; fi
g commit -q -m one || abort "git commit"; check
if [ $rc -eq 1 ] && [ "$out" = "notes.md:3: e-mail address" ]; then pass "a committed file is read"
else fail "a committed file: exit $rc, output: $out"; fi

# The staged text is what the next commit holds, even when the file was cleaned later.
printf 'first\nsecond\nthird\nlast\n' > "$repo/notes.md" || abort "write"; check
if [ $rc -eq 1 ] && [ "$out" = "notes.md:3: e-mail address" ]; then pass "a staged address is reported after the file itself was cleaned"
else fail "a staged address, file cleaned: exit $rc, output: $out"; fi
rm -f "$repo/notes.md" || abort "rm"; check
if [ $rc -eq 1 ] && [ "$out" = "notes.md:3: e-mail address" ]; then pass "a staged address is reported after the file itself was deleted"
else fail "a staged address, file deleted: exit $rc, output: $out"; fi
# The staged place keeps its own file name when the search of the folder ended in another.
printf 'test%sexample.com\n' "$at" > "$repo/zebra.txt" || abort "write"; check
if [ $rc -eq 1 ] && [ "$out" = "notes.md:3: e-mail address" ]; then pass "a staged address is named by its own file, after a clean file in the folder"
else fail "a staged address after a clean file: exit $rc, output: $out"; fi
rm -f "$repo/zebra.txt" || abort "rm"
# And the file as it is in the folder is read when the staged text is clean.
printf 'clean\n' > "$repo/notes.md" || abort "write"; g add notes.md || abort "git add"
printf 'clean\nalex%scorp.io\n' "$at" > "$repo/notes.md" || abort "write"; check
if [ $rc -eq 1 ] && [ "$out" = "notes.md:2: e-mail address" ]; then pass "an address added after staging is reported"
else fail "an address added after staging: exit $rc, output: $out"; fi

# Ignored and binary files are not read.
fresh
printf 'private/\n*.log\n' > "$repo/.gitignore" || abort "write"
mkdir -p "$repo/private" || abort "mkdir"
printf 'alex%scorp.io\n' "$at" > "$repo/private/list.txt" || abort "write"
printf '/%s/alex\n' "$H" > "$repo/run.log" || abort "write"
check
if [ $rc -eq 0 ] && [ "$out" = "$clean" ]; then pass "a file that git ignores is not read"
else fail "an ignored file: exit $rc, output: $out"; fi
fresh
printf 'alex%scorp.io\000\001\002\n' "$at" > "$repo/image.bin" || abort "write"
check
if [ $rc -eq 0 ] && [ "$out" = "$clean" ]; then pass "a file that git takes for binary is not read"
else fail "a binary file: exit $rc, output: $out"; fi

# A link is not followed: the file it points to, outside the repository, is not read.
fresh
printf 'alex%scorp.io\n' "$at" > "$tmp/outside.txt" || abort "write"
if MSYS=winsymlinks:nativestrict ln -s "$tmp/outside.txt" "$repo/link.txt" 2>/dev/null && [ -L "$repo/link.txt" ]; then
  check
  if [ $rc -eq 0 ] && [ "$out" = "$clean" ]; then pass "a link to a file outside the repository: that file is not read"
  else fail "a link to a file outside the repository: exit $rc, output: $out"; fi
else
  skip "a link to a file outside the repository: this system cannot create a link"
fi

fresh; check
if [ $rc -eq 0 ] && [ "$out" = "$clean" ]; then pass "a repository without files: exits 0"
else fail "a repository without files: exit $rc, output: $out"; fi

# --- The git settings of the person who runs it ---------------------------------------------
# setting <name> <value> <case>: with that setting in the repository, an address is still
# reported at its place, and clean files still pass.
setting() {
  g config "$1" "$2" || abort "git config $1"
  note "alex${at}corp.io /$H/alex"; check
  local found="$rc $out"
  note "nothing private about users at home"; check
  g config --unset "$1" || abort "git config --unset $1"
  if [ "$found" = "1 notes.md:3: home-folder path
notes.md:3: e-mail address" ] && [ $rc -eq 0 ] && [ "$out" = "$clean" ]; then pass "$3"
  else fail "$3: with a finding: $found; without: exit $rc, output: $out"; fi
}
setting color.ui always "colour forced for every command: the lines are read as without it"
setting color.grep always "colour forced for searches: the lines are read as without it"
setting submodule.recurse true "submodules followed by default: the search still runs"
setting grep.column true "column numbers switched on for searches: the lines are read as without them"
# With a column number before each line, a fence would no longer start its line.
g config grep.column true || abort "git config grep.column"
fresh
printf '```bash\nURL=https://site.example;HOME=/%s/alex\n```\n  - run: URL=https://site.example;HOME=/%s/alex\n' \
  "$H" "$H" > "$repo/notes.md" || abort "write"
check
g config --unset grep.column || abort "git config --unset grep.column"
if [ $rc -eq 1 ] && [ "$out" = "notes.md:2: home-folder path
notes.md:4: home-folder path" ]; then
  pass "column numbers switched on for searches: a block of shell is still told by its fence or its key"
else fail "column numbers switched on for searches, a block of shell: exit $rc, output: $out"; fi

# --- What cannot be read -----------------------------------------------------------------
mkdir -p "$tmp/plain folder" || abort "mkdir"
check "$tmp/plain folder"
if [ $rc -eq 2 ] && [ -z "$out" ] && grep -q "not inside a git repository" "$tmp/err"; then
  pass "a folder outside any repository: exits 2 and says why"
else fail "a folder outside any repository: exit $rc, output: $out"; fi
check "$tmp/no such folder"
if [ $rc -eq 2 ] && [ -z "$out" ] && grep -q "cannot open the folder" "$tmp/err"; then
  pass "a folder that does not exist: exits 2 and says why"
else fail "a folder that does not exist: exit $rc, output: $out"; fi
# git itself fails: a stand-in that fails every search and passes the rest on.
mkdir -p "$tmp/badgit" || abort "mkdir"
real_git="$(command -v git)" || abort "git not found"
{ printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = grep ] && exit 2; done\nexec "%s" "$@"\n' "$real_git" > "$tmp/badgit/git" &&
  chmod +x "$tmp/badgit/git"; } || abort "write the stand-in for git"
note "alex${at}corp.io"
out="$(PATH="$tmp/badgit:$PATH" bash "$pf" "$repo" 2>"$tmp/err")"; rc=$?
if [ $rc -eq 2 ] && [ -z "$out" ] && grep -q "git could not read every file" "$tmp/err"; then
  pass "a search that fails: exits 2, and does not call the files clean"
else fail "a search that fails: exit $rc, output: $out"; fi
# git reads what it can, says which file it could not read, and exits as if all were read.
{ printf '#!/usr/bin/env bash\nsearch=0; for a in "$@"; do [ "$a" = grep ] && search=1; done\n"%s" "$@"; code=$?\n' "$real_git" &&
  printf '[ $search -eq 1 ] && echo "error: could not read locked.md" >&2\nexit $code\n'; } > "$tmp/badgit/git" ||
  abort "write the stand-in for git"
# unread <name> <line>: with that stand-in and that line in a file that can be read.
unread() {
  note "$2"
  out="$(PATH="$tmp/badgit:$PATH" bash "$pf" "$repo" 2>"$tmp/err")"; rc=$?
  if [ $rc -eq 2 ] && [ -z "$out" ] && grep -q "could not read locked.md" "$tmp/err" &&
    grep -q "git could not read every file" "$tmp/err"; then pass "$1: exits 2 and shows what git said"
  else fail "$1: exit $rc, output: $out"; fi
}
unread "a file git could not read, beside clean files" "nothing private"
unread "a file git could not read, beside a file with an address" "alex${at}corp.io"
# The same with a file that really cannot be read, where the system has such files.
note "nothing private"
printf 'alex%scorp.io\n' "$at" > "$repo/locked.md" || abort "write"
chmod 000 "$repo/locked.md" || abort "chmod"
if cat "$repo/locked.md" > /dev/null 2>&1; then
  skip "a file whose permissions deny reading: this system lets the file be read anyway"
else
  check
  if [ $rc -eq 2 ] && [ -z "$out" ] && grep -q "git could not read every file" "$tmp/err"; then
    pass "a file whose permissions deny reading: exits 2, and does not call the files clean"
  else fail "a file whose permissions deny reading: exit $rc, output: $out"; fi
fi
chmod 644 "$repo/locked.md" || abort "chmod"

# --- This repository ---------------------------------------------------------------------
check "$here/.."
if [ $rc -eq 0 ] && [ "$out" = "$clean" ]; then pass "this repository: no home-folder path and no e-mail address"
else fail "this repository: exit $rc, output: $out"; fi

if [ $fails -ne 0 ]; then
  echo "$fails failed"
  exit 1
elif [ $skips -ne 0 ]; then
  echo "all passed, $skips skipped"
else
  echo "all passed"
fi
