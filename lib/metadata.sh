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

log_build_script_opt_in() {
  local opted_in="$1"
  local build_dir="$2"
  local has_build_script has_heroku_build_script

  has_build_script=$(read_json "$build_dir/package.json" ".scripts.build")
  has_heroku_build_script=$(read_json "$build_dir/package.json" ".scripts[\"heroku-postbuild\"]")

  # if this app will be affected by the change
  if [[ -z "$has_heroku_build_script" ]] && [[ -n "$has_build_script" ]]; then
    mcount "affected-by-build-change"

    if [[ "$opted_in" = "true" ]]; then
      mcount "affected-by-build-change-opted-in"
      bd_set "affected-but-opted-in" "true"
    else
      bd_set "affected-but-opted-in" "false"
    fi

  fi

  if [[ "$opted_in" = true ]]; then
    bd_set "build-script-opt-in" "true"
  else
    bd_set "build-script-opt-in" "false"
  fi
}