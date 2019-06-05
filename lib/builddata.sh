#!/usr/bin/env bash

log_initial_state() {
  meta_set "buildpack" "nodejs"
  if "$YARN"; then
    meta_set "node-package-manager" "yarn"
    meta_set "has-node-lock-file" "true"
  else
    meta_set "node-package-manager" "npm"
    meta_set "has-node-lock-file" "$NPM_LOCK"
  fi

  meta_set "stack" "$STACK"

  # add any active experiments to the metadata set
  # prefix the key with "experiment-"
  experiments_list | tr ' ' '\n' | while read -r key; do
    if [[ -n $key ]]; then
      meta_set "experiment-$key" "$(experiments_get "$key")"
    fi
  done
}

generate_uuids() {
  # generate a unique id for each build
  meta_set "build-uuid" "$(uuid)"

  # propagate an app-uuid forward unless the cache is cleared
  if [[ -n "$(meta_prev_get "app-uuid")" ]]; then
    meta_set "app-uuid" "$(meta_prev_get "app-uuid")"
  else
    meta_set "app-uuid" "$(uuid)"
  fi
}
