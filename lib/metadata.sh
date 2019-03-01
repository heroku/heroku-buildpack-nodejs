#!/usr/bin/env bash

log_initial_state() {
  if "$YARN"; then
    bd_set "node-package-manager" "yarn"
    bd_set "has-node-lock-file" "true"
  else
    bd_set "node-package-manager" "npm"
    bd_set "has-node-lock-file" "$NPM_LOCK"
  fi

  bd_set "stack" "$STACK"
}

generate_uuids() {
  # generate a unique id for each build
  bd_set "build-uuid" "$(uuid)"

  # propagate an app-uuid forward unless the cache is cleared
  if [[ -n "$(bd_prev_get "app-uuid")" ]]; then
    bd_set "app-uuid" "$(bd_prev_get "app-uuid")"
  else
    bd_set "app-uuid" "$(uuid)"
  fi
}
