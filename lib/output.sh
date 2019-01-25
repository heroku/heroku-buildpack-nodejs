#!/usr/bin/env bash

# TODO: Merge these with the output helpers in buildpack-stdlib:
# https://github.com/heroku/buildpack-stdlib

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

error() {
  echo " !     $*" >&2 || true
  echo "" || true
}

pipeError() {
  local c="2,999 s/^/ !     /"
	# send all of our output to stderr
	exec 1>&2

	echo -e "\033[1;31m" # bold; red
	echo -n " !     ERROR: "
	# this will be fed from stdin
  case $(uname) in
		Darwin) sed -l "$c";; # mac/bsd sed: -l buffers on line boundaries
		*)      sed -u "$c";; # unix/gnu sed: -u unbuffered (arbitrary) chunks of data
	esac
	echo -e "\033[0m" # reset style
	exit 1
}
