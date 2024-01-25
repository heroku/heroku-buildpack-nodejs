#!/usr/bin/env bash

get_node_major_version() {
  node --version | cut -d "." -f 1 | sed 's/^v//'
}

get_node_minor_version() {
  node --version | cut -d "." -f 2
}

install_plugin() {
  local major
  local bp_dir="$1"
  local build_dir="$2"
  major=$(get_node_major_version)
  minor=$(get_node_minor_version)

  if (( major < 14 )) || (( major == 14 && minor < 10 )); then
    install_native_plugin "$bp_dir" "$build_dir" "$major"
  else
    if [[ -n "$HEROKU_LEGACY_NODE_PLUGIN" ]] && (( major < 21 )); then
      warn "The native addon for Node.js language metrics is no longer supported. Unset the HEROKU_LEGACY_NODE_PLUGIN environment variable to migrate to the new metrics collector."
      install_native_plugin "$bp_dir" "$build_dir" "$major"
    else
      install_script_plugin "$bp_dir" "$build_dir"
    fi
  fi
}

# Node.js versions < 14.10.0 must use the prebuilt native addon
install_native_plugin() {
  local bp_dir="$1"
  local build_dir="$2"
  local major="$3"
  local plugin="${bp_dir}/plugin/heroku-nodejs-plugin-node-${major}.tar.gz"
  # If we have a version of the plugin compiled for this version of node, and the
  # user has not opted out of including the plugin, copy it into the slug.
  # It will be included at runtime once the user opts into the Node metrics feature
  if [[ -f "${plugin}" ]] && [[ -z "$HEROKU_SKIP_NODE_PLUGIN" ]]; then
    mkdir -p "${build_dir}/.heroku/"
    tar -xzf "${plugin}" -C "${build_dir}/.heroku/"
  fi
}
# Node.js versions >= 14.10.0 can use the metrics script
install_script_plugin() {
  local bp_dir="$1"
  local build_dir="$2"
  local pluginScript="${bp_dir}/metrics/metrics_collector.cjs"
  if [[ -f "${pluginScript}" ]] && [[ -z "$HEROKU_SKIP_NODE_PLUGIN" ]]; then
      mkdir -p "${build_dir}/.heroku/metrics"
      cp "${pluginScript}" "${build_dir}/.heroku/metrics/"
  fi
}
