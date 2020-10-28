#!/usr/bin/env bash

JQ="/usr/bin/jq"
if ! test -f "$JQ"; then
  curl -Ls https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 > "/usr/bin/jq" \
      && chmod +x "/usr/bin/jq"
fi

read_json() {
  local file="$1"
  local key="$2"

  if test -f "$file"; then
    # -c = print on only one line
    # -M = strip any color
    # --raw-output = if the filter’s result is a string then it will be written directly
    #                to stdout rather than being formatted as a JSON string with quotes
    # shellcheck disable=SC2002
    cat "$file" | $JQ -c -M --raw-output "$key // \"\"" || return 1
  else
    echo ""
  fi
}

json_has_key() {
  local file="$1"
  local key="$2"

  if test -f "$file"; then
    # shellcheck disable=SC2002
    cat "$file" | $JQ ". | has(\"$key\")"
  else
    echo "false"
  fi
}

has_script() {
  local file="$1"
  local key="$2"

  if test -f "$file"; then
    # shellcheck disable=SC2002
    cat "$file" | $JQ ".[\"scripts\"] | has(\"$key\")"
  else
    echo "false"
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
