#!/usr/bin/env bash

# variable shared by this whole module
BUILD_DATA_FILE=""
PREVIOUS_BUILD_DATA_FILE=""

meta_create() {
  local cache_dir="$1"
  BUILD_DATA_FILE="$cache_dir/build-data/nodejs"
  PREVIOUS_BUILD_DATA_FILE="$cache_dir/build-data/nodejs-prev"

  # if the file already exists because it's from the last build, save it
  if [[ -f "$BUILD_DATA_FILE" ]]; then
    cp "$BUILD_DATA_FILE" "$PREVIOUS_BUILD_DATA_FILE"
  fi

  kv_create "$BUILD_DATA_FILE"
  # make sure this doesnt grow over time
  kv_clear "$BUILD_DATA_FILE"
}

meta_get() {
  kv_get "$BUILD_DATA_FILE" "$1"
}

meta_set() {
  kv_set "$BUILD_DATA_FILE" "$1" "$2"
}

# similar to mtime from stdlib
meta_time() {
  local key="$1"
  local start="$2"
  local end="${3:-$(nowms)}"
  local time
  time="$(echo "${start}" "${end}" | awk '{ printf "%.3f", ($2 - $1)/1000 }')"
  kv_set "$BUILD_DATA_FILE" "$key" "$time"
}

# similar to mtime from stdlib
meta_time() {
  local key="$1"
  local start="$2"
  local end="${3:-$(nowms)}"
  local time
  time="$(echo "$start" "$end" | awk '{ printf "%.3f", ($2 - $1)/1000 }')"
  kv_set "$BUILD_DATA_FILE" "$1" "$time"
}

# Retrieve a value from a previous build if it exists
# This is useful to give the user context about what changed if the 
# build has failed. Ex:
#   - changed stacks
#   - deployed with a new major version of Node
#   - etc
meta_prev_get() {
  kv_get "$PREVIOUS_BUILD_DATA_FILE" "$1"
}

log_meta_data() {
  # print all values on one line in logfmt format
  # https://brandur.org/logfmt
  # the echo call ensures that all values are printed on a single line
  # shellcheck disable=SC2005 disable=SC2046
  echo $(kv_list "$BUILD_DATA_FILE")
}
