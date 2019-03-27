#!/usr/bin/env bash

log_initial_state() {
  if "$YARN"; then
    meta_set "node-package-manager" "yarn"
    meta_set "has-node-lock-file" "true"
  else
    meta_set "node-package-manager" "npm"
    meta_set "has-node-lock-file" "$NPM_LOCK"
  fi

  meta_set "stack" "$STACK"
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
      meta_set "affected-but-opted-in" "true"
    else
      meta_set "affected-but-opted-in" "false"
    fi

  fi

  if [[ "$opted_in" = true ]]; then
    meta_set "build-script-opt-in" "true"
  else
    meta_set "build-script-opt-in" "false"
  fi
}