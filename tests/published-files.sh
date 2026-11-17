#!/usr/bin/env bash
# Looks for two kinds of private detail in the files git would publish from a repository:
# a path into a person's home folder, and an e-mail address. Prints where each one is, as
# path:line: kind, and never the text itself. Usage: published-files.sh [folder]
# Exit 0: none found. Exit 1: at least one found. Exit 2: the files could not be read.
set -uo pipefail

fail() { echo "published-files: $1" >&2; exit 2; }

cd "${1:-.}" 2>/dev/null || fail "cannot open the folder ${1:-.}"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
cd "$root" 2>/dev/null || fail "cannot open the repository at $root"

tmp="$(mktemp -d)" || fail "cannot create a temporary folder"
{ [ -n "$tmp" ] && [ -d "$tmp" ]; } || fail "cannot create a temporary folder"
trap 'rm -rf -- "${tmp:?}"' EXIT

# search <file> <option>: every line of every file, one block for each file: its name, a
# number:text line for each line, and an empty line. -I leaves out files git takes for
# binary, and a link is not read. The two --no options and the setting keep the user's
# own git settings from colouring the lines, from refusing the search, and from adding a
# column number. Every line is read because the lines around a detail tell what it stands
# in: an element of markup, a block of shell.
search() {
  LC_ALL=C git -c grep.column=false grep -n -I -E --no-color --no-recurse-submodules \
    --heading --break "$2" -e '^' > "$1" 2> "$tmp/messages"
  # git exits 1 when it printed no line. A file it could not read leaves a message
  # and no other sign, so any message means that the search is not complete.
  if [ $? -gt 1 ] || [ -s "$tmp/messages" ]; then
    cat "$tmp/messages" >&2
    fail "git could not read every file of $root"
  fi
}
# The files as they are in the folder, untracked ones that are not ignored included, and
# the files as they are staged, which is what the next commit holds.
search "$tmp/folder" --untracked
search "$tmp/staged" --cached

LC_ALL=C awk '
  BEGIN {
    # A name starts with a letter of any alphabet, a digit, or an underscore. A
    # placeholder in its place, <you> or $USER, starts with a mark.
    first = "[^\001-/:-@[-^`{-\177]"
    # A path starts a word when a space, an opening mark, or a quote stands before it.
    mark = "[ !\"$-(,:-@[^`{|]"
    # Between the two may stand one plus sign or number sign, a hyphen with or without
    # the letters of an option, or the marks of emphasis: a diff, a comment,
    # ${ROOT:-/home/<name>}, -I/home/<name>, _/home/<name>_, **/home/<name>**. After a
    # letter or a slash these continue a word, as in c++/home/page and src/*/home/page,
    # except where a shell variable is cut or given a default: ${ROOT-/home/<name>}.
    start = "(" mark "([+#]|-[A-Za-z]*|_+|[*]+|~~)?|[$][{][A-Za-z_][A-Za-z0-9_]*[-+#]#?)/"
    # The elements of HTML. A name in angle brackets that is none of them, and is not
    # closed on its line or later in its file, is a placeholder: <repo>.
    elements = " a abbr address area article aside audio b base bdi bdo big blockquote body br button" \
      " canvas caption center cite code col colgroup data datalist dd del details dfn dialog div dl dt" \
      " em embed fieldset figcaption figure font footer form h1 h2 h3 h4 h5 h6 head header hgroup hr" \
      " html i iframe img input ins kbd label legend li link main map mark menu meta meter nav" \
      " noscript object ol optgroup option output p picture pre progress q rp rt ruby s samp script" \
      " search section select slot small source span strike strong style sub summary sup table tbody" \
      " td template textarea tfoot th thead time title tr track tt u ul var video wbr "
    # A drive letter starts a word when no letter and no digit stands before it, or the
    # letters of an option: -I after a hyphen, or one or two letters after a slash, /I.
    drive = "([ -/:-@[-`{-~]|" mark "(-[A-Za-z]+|/[A-Za-z][A-Za-z]?))[A-Za-z]:/"
    users = "[Uu][Ss][Ee][Rr][Ss]/"
    # A host is made of letters of any alphabet, digits, dots, and hyphens.
    host_chars = "^[^\001-,/:-@[-`{-\177]+"
    # The marks a local part may end in, besides letters and digits.
    local_marks = "._%+-!#$*?^~"
    # A string in double quotes with a slash after it. A shell command or a variable in
    # braces inside it is whole, with the strings of its own: a command may hold two
    # more, as in "$(dirname "$(pwd)")"/.
    command = "[(]([^()]|[(]([^()]|[(][^()]*[)])*[)])*[)]"
    string = "\"([^\"$]|[$]" command "|[$][{][^}]*[}]|[$][^({\"])*[$]?\"[/\\\\]"
    # A variable inside such a string: of a shell, between percent signs, or at signs.
    variable = "[$][A-Za-z_0-9@*#?$!{(-]|%[A-Za-z_][A-Za-z0-9_]*%|@[A-Za-z_][A-Za-z0-9_]*@"
    # The languages of a fenced block of Markdown that are a shell.
    shells = " sh bash zsh ksh shell console shell-session "
  }
  # word(c, marks): c is a letter of any alphabet, a digit, or one of the marks.
  function word(c, marks) {
    return c ~ /^[A-Za-z0-9]$/ || c > "\177" || (c != "" && index(marks, c) > 0)
  }
  # quotes(text, escaped): how many double quotes of the text a backslash escapes, or
  # how many it holds that none escapes. Two backslashes are a backslash and escape
  # nothing, so a quote is escaped after an odd number of them.
  function quotes(text, escaped,    n) {
    gsub(/\\\\/, "", text)
    n = gsub(/\\"/, "", text)
    return escaped ? n : gsub(/"/, "", text)
  }
  # escapes(text): the text ends in an odd number of backslashes, so the last of them
  # escapes the mark that follows.
  function escapes(text,    n, count) {
    for (n = length(text); n > 0 && substr(text, n, 1) == "\\"; n--) count++
    return count % 2
  }
  # context(text): reads a line of a file for where it stands, and says whether it is a
  # line of a shell: in a shell script, in a fenced block of Markdown whose language is
  # a shell, or in the value of a run: key of YAML, on its line or indented below it.
  function context(text,    line, c, n, info) {
    line = text
    sub(/[ \t\r]+$/, "", line)
    if (match(line, /^[ \t>]*(```|~~~)/)) {
      c = substr(line, RLENGTH, 1)
      info = substr(line, RLENGTH - 2)
      match(info, c == "~" ? "^~+" : "^`+")
      n = RLENGTH
      info = tolower(substr(info, n + 1))
      if (fence == "") {
        # What follows a fence of backticks holds no backtick: that is a code span.
        if (c == "~" || !index(info, "`")) {
          fence = c; fence_length = n; run_column = -1
          sub(/^[ \t]+/, "", info)
          sub(/[^a-z0-9-].*$/, "", info)
          shell_fence = (index(shells, " " info " ") > 0)
          return 0
        }
      } else if (c == fence && n >= fence_length && info == "") {
        fence = ""; shell_fence = 0; run_column = -1
        return 0
      }
    }
    # The value of a run: key ends at a line that is indented no more than the key.
    if (run_column >= 0 && line != "") {
      match(line, /^[ \t]*/)
      if (RLENGTH <= run_column) run_column = -1
    }
    if (run_column < 0 && match(line, /^[ \t]*(-[ \t]+)*run:([ \t]|$)/)) {
      match(line, /^[ \t]*(-[ \t]+)*/)
      run_column = RLENGTH
    }
    return script || shell_fence || run_column >= 0
  }
  # home(text): one of the words of the line holds a home folder with a name in it:
  # /Users/<name>, /home/<name>, <drive>:\Users\<name> with either slash, and that folder
  # as Git Bash, WSL, and Cygwin spell it.
  function home(text,    words, count, i, read, name, keeps, between, later, n, plain, slashed) {
    # A path right after a quoted string that holds a variable, as in "$ROOT"/home/page,
    # "build$ROOT"/home/page, or "%ROOT%"\Users\page, continues a longer path: a letter
    # takes the place of the quote that closes it. A quote opens a string when an even
    # number of quotes stands before it; one that a backslash escapes is counted apart.
    read = ""
    plain = slashed = 0
    while (match(text, string)) {
      between = substr(text, 1, RSTART - 1)
      keeps = escapes(between)
      n = 1
      if (((keeps ? slashed : plain) + quotes(between, keeps)) % 2 == 0 &&
        substr(text, RSTART + 1, RLENGTH - 3) ~ variable) n = RLENGTH - 1
      # Read on after the whole string, or after its first quote where it is none.
      between = substr(text, 1, RSTART + n - 1)
      plain += quotes(between, 0)
      slashed += quotes(between, 1)
      read = read (n > 1 ? substr(between, 1, length(between) - 1) "v" : between)
      text = substr(text, RSTART + n)
    }
    text = read text
    # The same for a variable between percent signs or at signs without quotes:
    # %ROOT%/home/page. The slash may be either one.
    while (match(text, /(%[A-Za-z_][A-Za-z0-9_]*%|@[A-Za-z_][A-Za-z0-9_]*@)[\/\\]/))
      text = substr(text, 1, RSTART + RLENGTH - 3) "v" substr(text, RSTART + RLENGTH - 1)
    # And for backticks that close a command, as in `pwd`/home/page. Backticks close
    # where others stand open before them and what is between the two starts as a
    # command does, with a letter or a path; any other backticks open, and a path after
    # them starts a word.
    read = ""
    for (later = 0; match(text, /`+/); ) {
      i = RSTART + RLENGTH
      between = substr(text, 1, RSTART - 1)
      keeps = 1
      if (later && between ~ /^[A-Za-z_.\/~$]/) { later = 0; keeps = (substr(text, i, 1) !~ /^[\/\\]$/) }
      else later = 1
      read = read between (keeps ? substr(text, RSTART, RLENGTH) : "v")
      text = substr(text, i)
    }
    text = read text
    # And for a placeholder in angle brackets, <repo>/home/page. An element of markup is
    # no placeholder: it is an element of HTML, or its name is closed on this line or
    # on a later line of the file.
    read = ""
    while (match(text, /<[A-Za-z][A-Za-z0-9 _-]*>[\/\\]/)) {
      name = tolower(substr(text, RSTART + 1, RLENGTH - 3))
      read = read substr(text, 1, RSTART + RLENGTH - 3)
      text = substr(text, RSTART + RLENGTH - 1)
      keeps = index(elements, " " name " ") || closed[source, path, name] >= number + 0
      read = read (keeps ? ">" : "v")
    }
    text = read text
    count = split(text, words, /[ \t]+/)
    for (i = 1; i <= count; i++) if (home_word(words[i])) return 1
    return 0
  }
  # url_end(rest, before): where a URL ends in the rest of its word, given the text that
  # stands before it, or 0 for nowhere. A URL in quotes or backticks ends at the same
  # mark, and one after < at >. Any other URL ends at a double quote, an angle bracket,
  # a backtick, or a bar, as between the cells of a table; an apostrophe is part of it.
  # A semicolon is part of a URL, except where it ends a statement of a shell: the
  # line is one of a shell, and the URL is the value of a variable, NAME=. A semicolon
  # that closes &amp; or the like never ends it.
  function url_end(rest, before,    n, c, ends) {
    ends = substr(before, length(before))
    if (ends == "<") ends = ">"
    else if (!index("\"\047`", ends) || ends == "") ends = "\"<>|`"
    for (n = 1; n <= length(rest); n++) {
      c = substr(rest, n, 1)
      if (index(ends, c)) return n
      if (c == ";" && shell && before ~ /[A-Za-z_][A-Za-z0-9_]*=$/ &&
        substr(rest, 1, n - 1) !~ /&#?[A-Za-z0-9]+$/) return n
    }
    return 0
  }
  function home_word(w,    read, scheme, rest, tail, n, c) {
    # A URL names no path of this computer, except a file URL after its host. A letter
    # stands in for it, and the word is read on from where the URL ends.
    read = ""
    while (match(w, /[A-Za-z][A-Za-z0-9+.-]+:\/\//)) {
      scheme = tolower(substr(w, RSTART, RLENGTH))
      read = read substr(w, 1, RSTART - 1)
      rest = substr(w, RSTART + RLENGTH)
      tail = ""
      n = url_end(rest, read)
      if (n) { tail = substr(rest, n); rest = substr(rest, 1, n - 1) }
      # A path right after the quote that closes a URL continues that URL. The quote
      # closes it when the same quote stands right before the URL.
      if (tail ~ /^["\047`]\// && substr(read, length(read)) == substr(tail, 1, 1)) tail = substr(tail, 2)
      read = read ((scheme == "file://" && sub(/^[^\/]*\//, "/", rest)) ? " " rest : "u")
      w = tail
    }
    w = read w
    # Nor does the query or the fragment of a URL that is written without its host: what
    # follows a ? or a # after a path character, up to a quote or an angle bracket. The
    # ?= of a Makefile and the # in ${PWD#/x} are no such marks, and stay.
    read = ""
    while (match(w, /[A-Za-z0-9\/._~%-][?#]/)) {
      read = read substr(w, 1, RSTART)
      c = substr(w, RSTART + 1, 1)
      w = substr(w, RSTART + 2)
      if (c == "?" ? w ~ /^=/ : read ~ /[$][{][A-Za-z_][A-Za-z0-9_]*$/) { read = read c; continue }
      # It ends as a URL does. What stands before it stands before the path it follows.
      tail = read
      sub(/[A-Za-z0-9\/._~%-]*$/, "", tail)
      n = url_end(w, tail)
      w = n ? substr(w, n) : ""
    }
    w = read w
    # One spelling for both slashes, single or doubled.
    gsub(/\\/, "/", w)
    gsub(/\/+/, "/", w)
    w = " " w
    return w ~ (start "(Users|home)/" first) || w ~ (drive users first) ||
      w ~ (start "(mnt/|cygdrive/)?[A-Za-z]/" users first)
  }
  # mail(text): one of the at signs of the line stands in an address to report.
  function mail(text,    left, right, at) {
    left = ""
    right = text
    while ((at = index(right, "@")) > 0) {
      left = left substr(right, 1, at - 1)
      right = substr(right, at + 1)
      if (address(left, right)) return 1
      left = left "@"
    }
    return 0
  }
  # quoted(left): the text ends in a local part in quotes, without the quote that closes
  # it. Back to the quote that opens it stands text that holds a letter or a digit,
  # starts as a local part may, and does not end as the text between two strings does:
  # in a space or one of , + = : ( [ { ; & |. A backslash may escape either quote.
  function quoted(left,    n, inner) {
    sub(/\\$/, "", left)
    for (n = length(left); n > 0; n--) if (substr(left, n, 1) == "\"") break
    if (!n) return 0
    inner = substr(left, n + 1)
    return word(substr(inner, 1, 1), local_marks) && inner !~ /[ \t,+=:([{;&|]$/ &&
      (inner ~ /[A-Za-z0-9]/ || inner ~ /[^\001-\177]/)
  }
  # host(right): how many characters at the start of the text are the host of an address
  # to report; 0 when they are none.
  function host(right,    name, last) {
    # An address literal in place of a name: [192.0.2.1], [IPv6:2001:db8::1].
    if (match(right, /^\[(IPv6:)?[0-9A-Fa-f]*[.:][0-9A-Fa-f:.]*\]/)) return RLENGTH
    if (!match(right, host_chars)) return 0
    name = substr(right, 1, RLENGTH)
    sub(/[.-]+$/, "", name)
    # A package and its version: name@1.2.3, name@v1.2.3-beta.next.
    if (name ~ /^[vV]?[0-9]+\.[0-9]+([.-]|$)/) return 0
    # A name has a dot, and its last label is letters: two or more of them, the coded
    # form of letters of another alphabet, or such letters themselves.
    last = name
    if (name ~ /^[.-]/ || !sub(/^.*\./, "", last)) return 0
    # A last label that starts in ASCII ends there: what follows is a mark of another
    # alphabet, not a letter of the name.
    if (match(last, /^[A-Za-z0-9-]+/) && RLENGTH < length(last)) {
      name = substr(name, 1, length(name) - length(last) + RLENGTH)
      last = substr(last, 1, RLENGTH)
    }
    if (last !~ /^[A-Za-z][A-Za-z]+$/ && tolower(last) !~ /^xn--[a-z0-9-]+$/ &&
      last !~ /[^\001-\177]/) return 0
    # The names reserved for examples. The dot in front lets each label start with one.
    last = "." tolower(name)
    if (last ~ /\.example\.(com|org|net)$/ || last ~ /\.(example|test|invalid|localhost)$/) return 0
    return length(name)
  }
  # address(left, right): the text before an at sign and the text after it.
  function address(left, right,    c, n, k, before) {
    # A local part ends in a letter, a digit, or one of a few marks, or it is in quotes.
    c = substr(left, length(left), 1)
    if (c == "\"" ? !quoted(substr(left, 1, length(left) - 1)) : !word(c, local_marks)) return 0
    n = host(right)
    if (!n) return 0
    # What stands before the local part, back to a space, a quote, or an angle bracket.
    k = length(left)
    while (k > 0 && word(substr(left, k, 1), local_marks)) k--
    before = tolower(substr(left, 1, k))
    # The user git right after the command ssh and its options is an SSH login, as in
    # ssh -T git@host and ssh -p 22 git@host.
    if (tolower(substr(left, k + 1)) == "git" &&
      (" " before) ~ /[^a-z0-9]ssh( +-[^ ]+( +[^- ][^ ]*)?)* +$/) return 0
    sub(/^.*[ \t"\047`<>]/, "", before)
    # In a URL only the user of an SSH URL is passed over: ssh://user@host/path.
    if (before ~ /:\/\//) return before !~ /ssh:\/\/$/
    # Without a scheme, an SSH remote is user@host:path with the path at the colon.
    return !(substr(right, n + 1, 1) == ":" && word(substr(right, n + 2, 1), "._~/-"))
  }
  # report <kind>: one line for a place, also when both searches found it.
  function report(kind,    place) {
    place = path ":" number ": " kind
    if (!(place in seen)) { seen[place] = 1; print place }
  }
  # The two searches are read twice: pass 1 notes where the elements of each file are
  # closed, pass 2 looks for the details. source tells the two searches apart.
  FNR == 1 { path = "" }
  $0 == "" { path = ""; next }
  path == "" {
    path = $0
    # A shell script by its name: the ending, or one of the files a shell reads.
    script = (path ~ /\.(sh|bash|zsh|ksh|bats|envrc)"?$/ ||
      ("/" path) ~ /\/\.(profile|bashrc|zshrc|bash_profile)"?$/)
    fence = ""; shell_fence = 0; run_column = -1
    next
  }
  {
    colon = index($0, ":")
    number = substr($0, 1, colon - 1)
    text = substr($0, colon + 1)
  }
  pass == 1 {
    # The last line of the file on which each name is closed, as in </name>.
    while (match(text, /<\/[A-Za-z][A-Za-z0-9 _-]*>/)) {
      closed[source, path, tolower(substr(text, RSTART + 2, RLENGTH - 3))] = number + 0
      text = substr(text, RSTART + RLENGTH)
    }
    next
  }
  {
    shell = context(text)
    # Only a line with one of these can hold a detail.
    if (text !~ /@|[Uu][Ss][Ee][Rr][Ss]|home/) next
    # A colour code of a terminal, and every other control character, ends a word.
    gsub(/\033\[[0-9;]*[A-Za-z]/, " ", text)
    gsub(/[\001-\037\177]/, " ", text)
    # A mark or a space outside ASCII ends a word as an ASCII space does: the marks of
    # general use, of Latin-1, and of East Asian text, the mark at the start of a file,
    # and the full-width forms of the ASCII marks.
    gsub(/\342\200.|\342\201.|\302.|\343\200.|\357\273\277/, " ", text)
    gsub(/\357\274[\201-\217\232-\240\273-\277]|\357\275[\200\233-\245]/, " ", text)
    # A slash that JSON escapes with a backslash is a slash, also in a URL.
    gsub(/\\\//, "/", text)
    # A line break or a tab that JSON writes as \n, \r, or \t ends a word where a path
    # follows it. Before a letter it may be a folder of a Windows path, and stays.
    while (match(text, /\\[nrt](\/|[A-Za-z]:[\\\/])/))
      text = substr(text, 1, RSTART - 1) " " substr(text, RSTART + 2)
    if (home(text)) report("home-folder path")
    if (mail(text)) report("e-mail address")
  }
  END { for (place in seen) exit 1 }' \
  pass=1 source=1 "$tmp/folder" source=2 "$tmp/staged" \
  pass=2 source=1 "$tmp/folder" source=2 "$tmp/staged"

case $? in
  0) echo "no home-folder path or e-mail address found" ;;
  1) echo "published-files: found in the places above; the text itself is not printed" >&2; exit 1 ;;
  *) fail "awk could not read the search result" ;;
esac
