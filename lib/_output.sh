#!/usr/bin/env bash

# Legacy, non-namespaced output helpers awaiting migration/elimination. These are still called
# by un-migrated scripts (`bin/compile`). New code should use the namespaced
# `output::*` functions in `lib/output.sh` instead. Once every caller has moved off `output` and
# `header`, this file can be deleted.

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
