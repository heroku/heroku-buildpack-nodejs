#!/usr/bin/env bash

JQ="$BP_DIR/vendor/jq-$(get_os)"

read_json() {
  local file="$1"
  local key="$2"

  if test -f "$file"; then
    # shellcheck disable=SC2002
    cat "$file" | $JQ --raw-output "$key // \"\"" || return 1
  else
    echo ""
  fi
}

is_invalid_json_file() {
  local file="$1"
  # shellcheck disable=SC2002
  if ! cat "$file" | $JQ "." 1>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}