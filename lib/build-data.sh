#!/usr/bin/env bash

# variable shared by this whole module
BUILD_DATA_FILE=""

bd_create() {
  local cache_dir="$1"
  BUILD_DATA_FILE="$cache_dir/build-data/node"
  kv_create "$BUILD_DATA_FILE"
}

bd_get() {
  kv_get "$BUILD_DATA_FILE" "$1"
}

bd_set() {
  kv_set "$BUILD_DATA_FILE" "$1" "$2"
}

# similar to mtime from stdlib
bd_time() {
  local key="$1"
  local start="$2"
  local end="${3:-$(nowms)}"
  local time
  time="$(echo "${start}" "${end}" | awk '{ printf "%.3f", ($2 - $1)/1000 }')"
  kv_set "$BUILD_DATA_FILE" "$key" "$time"
}

log_build_data() {
  # print all values on one line in logfmt format
  # https://brandur.org/logfmt
  # the echo call ensures that all values are printed on a single line
  # shellcheck disable=SC2005 disable=SC2046
  echo $(kv_list "$BUILD_DATA_FILE")
}
