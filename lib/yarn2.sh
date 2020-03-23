#!/usr/bin/env bash

YQ="$BP_DIR/vendor/yq-$(get_os)"

detect_yarn2() {
  local uses_yarn="$1"
  local build_dir="$2"

  local is_yml=$($YQ v "$build_dir/yarn.lock" 2>&1)

  if [[ "$uses_yarn" == "true" && "$is_yml" == "" ]]; then
    echo "true"
  else
    echo "false"
  fi
}
