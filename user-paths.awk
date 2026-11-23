# Emit user-home path findings with their line context. POSIX awk; invoked by pii-scanner.sh.
{
  rest = $0
  offset = 0
  while (match(rest, /\/(Users|home)\/[A-Za-z0-9._-]+/)) {
    start = offset + RSTART
    path = substr(rest, RSTART, RLENGTH)
    previous = start > 1 ? substr($0, start - 1, 1) : ""
    boundary = start == 1 || previous ~ /[[:space:]"'`(=:>]/ || substr($0, start - 4, 4) == "~/.."
    prefix = substr($0, 1, start - 1)
    # A URL remains a URL through its path and query until a text delimiter.
    in_url = prefix ~ /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^[:space:]"'<>()]*$/
    if (boundary && !in_url)
      print FILENAME ":" FNR ":USER_PATH:" path
    offset = start + RLENGTH - 1
    rest = substr($0, offset + 1)
  }
}
