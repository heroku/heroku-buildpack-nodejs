#!/usr/bin/env bash

log_initial_state() {
  if "$YARN"; then
    bd_set "node-package-manager" "yarn"
    bd_set "has-node-lock-file" "true"
  else
    bd_set "node-package-manager" "npm"
    bd_set "has-node-lock-file" "$NPM_LOCK"
  fi

  bd_set "new-build-script-opt-in" "false"

  bd_set "stack" "$STACK"
}

log_build_script_opt_in() {
  local opted_in="$1"
  if [[ "$opted_in" = true ]]; then
    bd_set "build-script-opt-in" "true"
  else
    bd_set "build-script-opt-in" "false"
  fi
}