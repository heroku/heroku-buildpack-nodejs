#!/usr/bin/env bash

YQ="$BP_DIR/lib/vendor/yq-4.52.4-$(get_os)"

read_yaml() {
  local file="$1"
  local key="$2"
  $YQ "$key" "$file"
}
