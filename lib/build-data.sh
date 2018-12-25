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

log_build_data() {
  # print all values on one line in logfmt format
  # https://brandur.org/logfmt
  # the echo call ensures that all values are printed on a single line
  # shellcheck disable=SC2005 disable=SC2046
  echo $(kv_list "$BUILD_DATA_FILE")
}
