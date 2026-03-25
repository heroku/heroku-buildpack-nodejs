#!/usr/bin/env bash

ANSI_RED=$'\e[1;31m'
ANSI_RESET=$'\e[0m'

# TODO: deprecated these in favor of https://github.com/heroku/heroku-buildpack-python/blob/main/lib/output.sh

info() {
  echo "       $*" || true
}

# format output and send a copy to the log
output() {
  local logfile="$1"

  while IFS= read -r LINE;
  do
    # do not indent headers that are being piped through the output
    if [[ "$LINE" =~ ^-----\>.* ]]; then
      echo "$LINE" || true
    else
      echo "       $LINE" || true
    fi
    echo "$LINE" >> "$logfile" || true
  done
}

header() {
  echo "" || true
  echo "-----> $*" || true
}

bright_header() {
  echo "" || true
  echo -e "\033[1;33m-----> $* \033[0m"
}

header_skip_newline() {
  echo "-----> $*" || true
}

error() {
  echo " !     $*" >&2 || true
  echo "" || true
}

# Output a styled multi-line error message to stderr.
#
# Usage:
# ```
# output_error <<-EOF
# 	Error: The error summary.
#
# 	Detailed description.
# EOF
# ```
output::error() {
  echo >&2
  sed --unbuffered "s/^/${ANSI_RED} !     /" | sed --unbuffered "s/$/${ANSI_RESET}/" >&2
  echo >&2
}
