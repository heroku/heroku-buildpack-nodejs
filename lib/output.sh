info() {
  echo "$*" || true
}

# format output and send a copy to the log
output() {
  local logfile="$1"

  while read LINE;
  do
    echo "$LINE" || true
    echo "$LINE" >> "$logfile" || true
  done
}

header() {
  echo "" || true
  puts_step "$*"
}

warn() {
  local message=${1:-}
  local suggestion=${2:-https://devcenter.heroku.com/articles/nodejs-support}
  echo "" || true
  puts_warn $message
  echo "$suggestion"
}

error() {
  echo "" || true
  puts_error "$*" >&2
}
