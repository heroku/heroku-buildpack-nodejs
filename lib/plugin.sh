#!/usr/bin/env bash

get_node_major_version() {
  node --version | cut -d "." -f 1 | sed 's/^v//'
}

install_plugin() {
  local major
  local bp_dir="$1"
  local build_dir="$2"
  major=$(get_node_major_version)

  if [ "${major}" -lt "21" ]; then
    local plugin="${bp_dir}/plugin/heroku-nodejs-plugin-node-${major}.tar.gz"
    # If we have a version of the plugin compiled for this version of node, and the
    # user has not opted out of including the plugin, copy it into the slug.
    # It will be included at runtime once the user opts into the Node metrics feature
    if [[ -f "${plugin}" ]] && [[ -z "$HEROKU_SKIP_NODE_PLUGIN" ]]; then
      mkdir -p "${build_dir}/.heroku/"
      tar -xzf "${plugin}" -C "${build_dir}/.heroku/"
    fi
  else
    local pluginScript="${bp_dir}/metrics/metrics_collector.cjs"
    if [[ -f "${pluginScript}" ]] && [[ -z "$HEROKU_SKIP_NODE_PLUGIN" ]]; then
        mkdir -p "${build_dir}/.heroku/metrics"
        cp "${pluginScript}" "${build_dir}/.heroku/metrics/"
    fi
  fi
}
