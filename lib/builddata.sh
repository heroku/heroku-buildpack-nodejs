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

# Log out information about the build that we can read from package.json
log_project_info() {
  local time
  local build_dir="$1"

  # Does this project use "workspaces"?
  meta_set "uses_workspaces" "$(json_has_key "$build_dir/package.json" "workspaces")"
  # What workspaces are defined? Logs as: `["packages/*","a","b"]`
  meta_set "workspaces" "$(read_json "$build_dir/package.json" ".workspaces")"

  # just to be sure this isn't disruptive, let's time it. This can be removed later once we've
  # established that this is quick for all projects.
  time=$(nowms)
  # Count # of js, jsx, ts, coffee, vue, and html files to approximate project size, exclude any files in node_modules
  meta_set "num_project_files" "$(find "$build_dir" -name '*.js' -o -name '*.ts' -o -name '*.jsx' -o -name '*.coffee' -o -name '*.vue' -o -name '*.html' | grep -cv node_modules | tr -d '[:space:]')"
  meta_time "count_file_time" "$time"
}
