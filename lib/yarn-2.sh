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

has_release_script() {
  local build_dir="$1"
  local yarn_path
  yarn_path=$($YQ r "$build_dir/.yarnrc.yml" yarnPath 2>&1)
  [[ -n "$yarn_path" ]] && [ -f "$build_dir/$yarn_path" ]
}

has_yarn_cache() {
  local build_dir="$1"
  local yarn_cache="$build_dir/.yarn/cache"
  [[ -d "$yarn_cache" ]] && [[ -n "$(ls -A "$yarn_cache")" ]]
}

has_yarn_workspace_plugin_installed() {
  local has_workspace_plugin=$(yarn plugin runtime | grep plugin-workspace-tools)
  [[ ! "$has_workspace_plugin" == "" ]]
}

get_yarn_path() {
  local build_dir="$1"
  $YQ r "$build_dir/.yarnrc.yml" yarnPath 2>&1
}

use_yarn_app_cache() {
  local build_dir="$1"
  if has_yarn_cache "$build_dir" || ! node_modules_enabled "$build_dir"; then
    return
  fi
  false
}

node_modules_enabled() {
  local build_dir="$1"
  local node_linker

  node_linker=$($YQ r "$build_dir/.yarnrc.yml" nodeLinker 2>&1)

  [[ "$node_linker" == "node-modules" ]]
}

get_yarn_major_version() {
  local build_dir="$1"
  local package_manager yarn_engine version_string

  # Check packageManager field first (e.g., "yarn@4.0.0")
  package_manager=$(read_json "$build_dir/package.json" ".packageManager")
  if [[ "$package_manager" == yarn@* ]]; then
    version_string="${package_manager#yarn@}"
    # Extract major version (e.g., "4.0.0" -> "4", "4.0.0+sha256.abc" -> "4")
    echo "$version_string" | cut -d "." -f 1
    return
  fi

  # Check engines.yarn field (e.g., "4.x", "^4.0.0", ">=4.0.0")
  yarn_engine=$(read_json "$build_dir/package.json" ".engines.yarn")
  if [[ -n "$yarn_engine" ]]; then
    # Extract major version, ignoring any non-numeric prefix
    version_string=$(echo "$yarn_engine" | sed -E 's/^[^0-9]*([0-9]+)\.?.*/\1/')
    if [[ -n "$version_string" ]]; then
      echo "$version_string"
      return
    fi
  fi

  # If we can't determine version, return empty string
  echo ""
}
