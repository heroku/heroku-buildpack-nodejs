#!/usr/bin/env bash

get_node_major_version() {
  local node_version

  node_version="$(node --version)"
  # major_string will be ex: "6." "8." "10"
  local major_string=${node_version:1:2}
  # strip any "."s from major_string
  local major=${major_string//.}
  echo "$major"
}

install_plugin() {
  local major
  local bp_dir="$1"
  local build_dir="$2"
  major=$(get_node_major_version)
  local plugin="${bp_dir}/plugin/heroku-nodejs-plugin-node-${major}.tar.gz"

  # If we have a version of the plugin compiled for this version of node, and the
  # user has not opted out of including the plugin, copy it into the slug.
  # It will be included at runtime once the user opts into the Node metrics feature
  if [[ -f "${plugin}" ]] && [[ -z "$HEROKU_SKIP_NODE_PLUGIN" ]]; then
    mkdir -p "${build_dir}/.heroku/"
    tar -xzf "${plugin}" -C "${build_dir}/.heroku/"
  fi
}
