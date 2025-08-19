#!/usr/bin/env bash

# Log out information about the build that we can detect without accessing package.json
log_initial_state() {
  if "$YARN"; then
    meta_set "node_package_manager" "yarn"
    meta_set "has_node_lock_file" "true"
  elif "$PNPM"; then
    meta_set "node_package_manager" "pnpm"
    meta_set "has_node_lock_file" "true"
  else
    meta_set "node_package_manager" "npm"
    meta_set "has_node_lock_file" "$NPM_LOCK"
  fi

  # add any active features to the metadata set
  # prefix the key with "feature-"
  features_list | tr ' ' '\n' | while read -r key; do
    if [[ -n $key ]]; then
      meta_set "feature_$key" "$(features_get "$key")"
    fi
  done
}
