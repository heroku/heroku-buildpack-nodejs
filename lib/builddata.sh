#!/usr/bin/env bash

# Log out information about the build that we can detect without accessing package.json
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

  # add any active features to the metadata set
  # prefix the key with "feature-"
  features_list | tr ' ' '\n' | while read -r key; do
    if [[ -n $key ]]; then
      meta_set "feature-$key" "$(features_get "$key")"
    fi
  done
}

# Log out information about the build that we can read from package.json
log_project_info() {
  local time
  local build_dir="$1"

  # Does this project use "workspaces"?
  meta_set "uses-workspaces" "$(json_has_key "$build_dir/package.json" "workspaces")"
  # What workspaces are defined? Logs as: `["packages/*","a","b"]`
  meta_set "workspaces" "$(read_json "$build_dir/package.json" ".workspaces")"

  # just to be sure this isn't disruptive, let's time it. This can be removed later once we've
  # established that this is quick for all projects.
  time=$(nowms)
  # Count # of js, jsx, ts, coffee, vue, and html files to approximate project size, exclude any files in node_modules
  meta_set "num-project-files" "$(find "$build_dir" -name '*.js' -o -name '*.ts' -o -name '*.jsx' -o -name '*.coffee' -o -name '*.vue' -o -name '*.html' | grep -cv node_modules | tr -d '[:space:]')"
  meta_time "count-file-time" "$time"
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
