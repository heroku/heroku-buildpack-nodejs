#!/usr/bin/env bash

read_json() {
  local file="$1"
  local key="$2"

  if test -f "$file"; then
    # -c = print on only one line
    # -M = strip any color
    # --raw-output = if the filter’s result is a string then it will be written directly
    #                to stdout rather than being formatted as a JSON string with quotes
    # shellcheck disable=SC2002
    cat "$file" | jq -c -M --raw-output "$key // \"\"" || return 1
  else
    echo ""
  fi
}

json_has_key() {
  local file="$1"
  local key="$2"

  if test -f "$file"; then
    # shellcheck disable=SC2002
    cat "$file" | jq ". | has(\"$key\")"
  else
    echo "false"
  fi
}

has_script() {
  local file="$1"
  local key="$2"

  if test -f "$file"; then
    # shellcheck disable=SC2002
    cat "$file" | jq ".[\"scripts\"] | has(\"$key\")"
  else
    echo "false"
  fi
}

is_invalid_json_file() {
  local file="$1"
  # shellcheck disable=SC2002
  if ! cat "$file" | jq "." 1>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}
