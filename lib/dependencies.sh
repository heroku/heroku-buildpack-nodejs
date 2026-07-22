#!/usr/bin/env bash

list_dependencies() {
  local build_dir="$1"

  cd "$build_dir" || return
  if $YARN; then
    echo ""
    (yarn list --depth=0 || true) 2>/dev/null
    echo ""
  else
    (npm ls --depth=0 | tail -n +2 || true) 2>/dev/null
  fi
}

run_if_present() {
  local build_dir=${1:-}
  local script_name=${2:-}
  local has_script_name
  local script

  has_script_name=$(has_script "$build_dir/package.json" "$script_name")
  script=$(read_json "$build_dir/package.json" ".scripts[\"$script_name\"]")
  monitor_name="${script_name//[^[:alnum:]]/_}_script"

  if [[ "$has_script_name" == "true" ]]; then
    if $YARN || $YARN_2; then
      echo "Running $script_name (yarn)"
      # yarn will throw an error if the script is an empty string, so check for this case
      if [[ -n "$script" ]]; then
        monitor "${monitor_name}" yarn run "$script_name"
      fi
    elif $PNPM; then
      echo "Running $script_name"
      monitor "${monitor_name}" pnpm run --if-present "$script_name"
    else
      echo "Running $script_name"
      monitor "${monitor_name}" npm run "$script_name" --if-present
    fi
  fi
}

run_build_if_present() {
  local build_dir=${1:-}
  local script_name=${2:-}
  local has_script_name
  local script

  has_script_name=$(has_script "$build_dir/package.json" "$script_name")
  script=$(read_json "$build_dir/package.json" ".scripts[\"$script_name\"]")

  if [[ "$script" == "ng build" ]]; then
    warn "\"ng build\" detected as build script. We recommend you use \`ng build --prod\` or add \`--prod\` to your build flags. See https://devcenter.heroku.com/articles/nodejs-support#build-flags"
  fi

  if [[ "$has_script_name" == "true" ]]; then
    if $YARN || $YARN_2; then
      echo "Running $script_name (yarn)"
      # yarn will throw an error if the script is an empty string, so check for this case
      if [[ -n "$script" ]]; then
        if [[ -n $NODE_BUILD_FLAGS ]]; then
          echo "Running with $NODE_BUILD_FLAGS flags"
          monitor "build_script" yarn run "$script_name" "$NODE_BUILD_FLAGS"
        else
          monitor "build_script" yarn run "$script_name"
        fi
      fi
    elif $PNPM; then
      echo "Running $script_name"
      if [[ -n $NODE_BUILD_FLAGS ]]; then
        echo "Running with $NODE_BUILD_FLAGS flags"
        monitor "build_script" pnpm run --if-present "$script_name" -- "$NODE_BUILD_FLAGS"
      else
        monitor "build_script" pnpm run --if-present "$script_name"
      fi
    else
      echo "Running $script_name"
      if [[ -n $NODE_BUILD_FLAGS ]]; then
        echo "Running with $NODE_BUILD_FLAGS flags"
        monitor "build_script" npm run "$script_name" --if-present -- "$NODE_BUILD_FLAGS"
      else
        monitor "build_script" npm run "$script_name" --if-present
      fi
    fi
  fi
}

run_prebuild_script() {
  local build_dir=${1:-}
  local has_heroku_prebuild_script

  has_heroku_prebuild_script=$(has_script "$build_dir/package.json" "heroku-prebuild")

  if [[ "$has_heroku_prebuild_script" == "true" ]]; then
    header "Prebuild"
    run_if_present "$build_dir" 'heroku-prebuild'
  fi
}

run_build_script() {
  local build_dir=${1:-}
  local has_build_script has_heroku_build_script

  has_build_script=$(has_script "$build_dir/package.json" "build")
  has_heroku_build_script=$(has_script "$build_dir/package.json" "heroku-postbuild")
  if [[ "$has_heroku_build_script" == "true" ]] && [[ "$has_build_script" == "true" ]]; then
    echo "Detected both \"build\" and \"heroku-postbuild\" scripts"
    run_if_present "$build_dir" 'heroku-postbuild'
  elif [[ "$has_heroku_build_script" == "true" ]]; then
    run_if_present "$build_dir" 'heroku-postbuild'
  elif [[ "$has_build_script" == "true" ]]; then
    run_build_if_present "$build_dir" 'build'
  fi
}

run_cleanup_script() {
  local build_dir=${1:-}
  local has_heroku_cleanup_script

  has_heroku_cleanup_script=$(has_script "$build_dir/package.json" "heroku-cleanup")

  if [[ "$has_heroku_cleanup_script" == "true" ]]; then
    header "Cleanup"
    run_if_present "$build_dir" 'heroku-cleanup'
  fi
}

has_npm_lock() {
  local build_dir=${1:-}

  if [[ -f "$build_dir/package-lock.json" ]] || [[ -f "$build_dir/npm-shrinkwrap.json" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

should_use_npm_ci() {
  local build_dir=${1:-}
  local npm_version
  local major

  npm_version=$(npm --version)
  major=$(package_managers::npm::version_major)

  # We should only run `npm ci` if all of the manifest files are there, and we are running at least npm 6.x
  # `npm ci` was introduced in the 5.x line in 5.7.0, but this sees very little usage, < 5% of builds
  if [[ -f "$build_dir/package.json" ]] && [[ "$(has_npm_lock "$build_dir")" == "true" ]] && (( major >= 6 )); then
    echo "true"
  else
    echo "false"
  fi
}

npm_rebuild() {
  local build_dir=${1:-}
  local production=${NPM_CONFIG_PRODUCTION:-false}

  # npm 12 removed the --unsafe-perm flag and rejects it with EUNKNOWNCONFIG, so only pass it
  # to the currently-active npm when that npm still accepts it.
  local unsafe_perm=()
  if package_managers::npm::supports_unsafe_perm; then
    unsafe_perm=(--unsafe-perm)
  fi

  if [ -e "$build_dir/package.json" ]; then
    cd "$build_dir" || return
    echo "Rebuilding any native modules"
    npm rebuild 2>&1
    if [ -e "$build_dir/npm-shrinkwrap.json" ]; then
      echo "Installing any new modules (package.json + shrinkwrap)"
    else
      echo "Installing any new modules (package.json)"
    fi
    monitor "npm_rebuild" npm install --production="$production" "${unsafe_perm[@]}" --userconfig "$build_dir/.npmrc" 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}

pnpm_prune_devdependencies() {
  local build_dir=${1:-}

  cd "$build_dir" || return

  if [ "$NODE_ENV" == "test" ]; then
    echo "Skipping because NODE_ENV is 'test'"
    build_data::set_raw "skipped_prune" "true"
    return 0
  elif [ "$NODE_ENV" != "production" ]; then
    echo "Skipping because NODE_ENV is not 'production'"
    build_data::set_raw "skipped_prune" "true"
    return 0
  elif [ "$PNPM_SKIP_PRUNING" == "true" ]; then
    echo "Skipping because PNPM_SKIP_PRUNING is '$PNPM_SKIP_PRUNING'"
    build_data::set_raw "skipped_prune" "true"
    return 0
  elif [[ "$(pnpm_workspace_configured "$build_dir")" == "true" ]]; then
    # Get pnpm projects
    mapfile -t project_paths < <(list_pnpm_workspace_projects)
    # Check if any projects contain lifecycle scripts, and skip pruning if true
    for project_path in "${project_paths[@]}"; do
      if has_pnpm_lifecycle_script "$project_path/package.json"; then
        warn_skipping_unsafe_pnpm_workspace_prune "$project_path"
        build_data::set_raw "skipped_prune" "true"
        return 0
      fi
    done
    # Remove node_modules from each project
    for project_path in "${project_paths[@]}"; do
      rm -rf "$project_path/node_modules"
    done
    # Reinstall with production-only dependencies
    monitor "prune_dev_dependencies" pnpm install --prod --frozen-lockfile 2>&1
    build_data::set_raw "skipped_prune" "false"
    return 0
  fi

  pnpm_version=$(pnpm --version)
  pnpm_major_version=$(echo "$pnpm_version" | cut -d "." -f 1)
  pnpm_minor_version=$(echo "$pnpm_version" | cut -d "." -f 2)
  pnpm_patch_version=$(echo "$pnpm_version" | cut -d "." -f 3)

  pnpm_prune_args=("prune" "--prod")

  # prior to 8.15.6, pnpm prune would execute lifecycle scripts such as `preinstall` and `postinstall`
  # so we should check if we're on that version + there are lifecycle scripts registered and, if so,
  # we'll let the user know that pruning can't be done safely so we're skipping it
  if (( "$pnpm_major_version" < 8 )) || \
    (( "$pnpm_major_version" == 8 && "$pnpm_minor_version" < 15 )) || \
    (( "$pnpm_major_version" == 8 && "$pnpm_minor_version" == 15 && "$pnpm_patch_version" < 6)); then
      if has_pnpm_lifecycle_script "$build_dir/package.json"; then
        warn_skipping_unsafe_pnpm_prune "$pnpm_version"
        build_data::set_raw "skipped_prune" "true"
        return
      fi
  else
    # we're on a version that supports this flag (8.15.6 and higher)
    pnpm_prune_args+=("--ignore-scripts")
  fi

  monitor "prune_dev_dependencies" pnpm "${pnpm_prune_args[@]}" 2>&1

  build_data::set_raw "skipped_prune" "false"
}

pnpm_workspace_configured() {
  local build_dir=${1:-}
  local workspace_file="$build_dir/pnpm-workspace.yaml"
  local result

  if [[ -f "$workspace_file" ]]; then
    # prior to pnpm 10.5.0, the `packages` key was mandatory, but now, you can store
    # other pnpm-related config settings in `pnpm-workspace.yaml`.
    result=$(read_yaml "$workspace_file" '.packages')

    if [[ -n "$result" && "$result" != "null" ]]; then
      echo "true"
      return
    fi
  fi

  echo "false"
}

has_pnpm_lifecycle_script() {
  local package_json=$1
  # the following are lifecycle scripts that will execute on install/prune by pnpm
  [[ -f "$package_json" ]] && \
    jq -e '.scripts | (has("pnpm:devPreinstall") or has("preinstall") or has("install") or has("postinstall") or has("prepare"))' \
    "$package_json" > /dev/null 2>&1
}

list_pnpm_workspace_projects() {
  pnpm list --recursive --json --depth -1 2>/dev/null | jq -r '.[].path'
}
