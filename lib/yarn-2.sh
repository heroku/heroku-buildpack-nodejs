#!/usr/bin/env bash

YQ="$BP_DIR/lib/vendor/yq-$(get_os)"

detect_yarn_2() {
  local uses_yarn="$1"
  local build_dir="$2"
  local yml_metadata
  local version

  yml_metadata=$($YQ r "$build_dir/yarn.lock" __metadata 2>&1)

  # grep for version in case the output is a parsing error
  version=$(echo "$yml_metadata" | grep version)

  if [[ "$uses_yarn" == "true" && "$version" != "" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

has_yarn_cache() {
  local build_dir="$1"
  [[ -d "$build_dir/.yarn/cache" ]]
}

has_yarn_workspace_plugin_installed() {
  local build_dir="$1"
  local plugin_paths=$(get_yarn_plugin_paths "$build_dir")
  [[ ! -n $plugin_paths ]] && echo "$plugin_paths" | grep plugin-workspace-tools
}

get_yarn_plugin_paths() {
  local build_dir="$1"
  $YQ r "$build_dir/.yarnrc.yml" "plugins.[*].path" 2>&1
}

get_yarn_path() {
  local build_dir="$1"
  $YQ r "$build_dir/.yarnrc.yml" yarnPath 2>&1
}

node_modules_enabled() {
  local build_dir="$1"
  local node_linker
  
  node_linker=$($YQ r "$build_dir/.yarnrc.yml" nodeLinker 2>&1)

  [[ "$node_linker" == "node-modules" ]]
}
