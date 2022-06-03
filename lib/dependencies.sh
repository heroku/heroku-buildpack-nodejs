#!/usr/bin/env bash

measure_size() {
  (du -s node_modules 2>/dev/null || echo 0) | awk '{print $1}'
}

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

  if [[ "$has_script_name" == "true" ]]; then
    if $YARN || $YARN_2; then
      echo "Running $script_name (yarn)"
      # yarn will throw an error if the script is an empty string, so check for this case
      if [[ -n "$script" ]]; then
        monitor "${script_name}-script" yarn run "$script_name"
      fi
    else
      echo "Running $script_name"
      monitor "${script_name}-script" npm run "$script_name" --if-present
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
          monitor "${script_name}-script" yarn run "$script_name" "$NODE_BUILD_FLAGS"
        else
          monitor "${script_name}-script" yarn run "$script_name"
        fi
      fi
    else
      echo "Running $script_name"
      if [[ -n $NODE_BUILD_FLAGS ]]; then
        echo "Running with $NODE_BUILD_FLAGS flags"
        monitor "${script_name}-script" npm run "$script_name" --if-present -- "$NODE_BUILD_FLAGS"
      else
        monitor "${script_name}-script" npm run "$script_name" --if-present
      fi
    fi
  fi
}

run_prebuild_script() {
  local build_dir=${1:-}
  local has_heroku_prebuild_script

  has_heroku_prebuild_script=$(has_script "$build_dir/package.json" "heroku-prebuild")

  if [[ "$has_heroku_prebuild_script" == "true" ]]; then
    mcount "script.heroku-prebuild"
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
    mcount "scripts.heroku-postbuild-and-build"
    run_if_present "$build_dir" 'heroku-postbuild'
  elif [[ "$has_heroku_build_script" == "true" ]]; then
    mcount "scripts.heroku-postbuild"
    run_if_present "$build_dir" 'heroku-postbuild'
  elif [[ "$has_build_script" == "true" ]]; then
    mcount "scripts.build"
    run_build_if_present "$build_dir" 'build'
  fi
}

run_cleanup_script() {
  local build_dir=${1:-}
  local has_heroku_cleanup_script

  has_heroku_cleanup_script=$(has_script "$build_dir/package.json" "heroku-cleanup")

  if [[ "$has_heroku_cleanup_script" == "true" ]]; then
    mcount "script.heroku-cleanup"
    header "Cleanup"
    run_if_present "$build_dir" 'heroku-cleanup'
  fi
}

log_build_scripts() {
  local build_dir=${1:-}

  meta_set "build-script" "$(read_json "$build_dir/package.json" ".scripts[\"build\"]")"
  meta_set "postinstall-script" "$(read_json "$build_dir/package.json" ".scripts[\"postinstall\"]")"
  meta_set "heroku-prebuild-script" "$(read_json "$build_dir/package.json" ".scripts[\"heroku-prebuild\"]")"
  meta_set "heroku-postbuild-script" "$(read_json "$build_dir/package.json" ".scripts[\"heroku-postbuild\"]")"
}

yarn_node_modules() {
  local build_dir=${1:-}
  local production=${YARN_PRODUCTION:-false}

  echo "Installing node modules (yarn.lock)"
  cd "$build_dir" || return
  monitor "yarn-install" yarn install --production="$production" --frozen-lockfile --ignore-engines --prefer-offline 2>&1
}

yarn_2_install() {
  local build_dir=${1:-}

  echo "Running 'yarn install' with yarn.lock"
  cd "$build_dir" || return

  monitor "yarn-2-install" yarn install --immutable 2>&1
}

yarn_prune_devdependencies() {
  local build_dir=${1:-}
  local cache_dir=${2:-}
  local buildpack_dir=${3:-}

  if [ "$NODE_ENV" == "test" ]; then
    echo "Skipping because NODE_ENV is 'test'"
    meta_set "skipped-prune" "true"
    return 0
  elif [ "$NODE_ENV" != "production" ]; then
    echo "Skipping because NODE_ENV is not 'production'"
    meta_set "skipped-prune" "true"
    return 0
  elif [ -n "$YARN_PRODUCTION" ]; then
    echo "Skipping because YARN_PRODUCTION is '$YARN_PRODUCTION'"
    meta_set "skipped-prune" "true"
    return 0
  elif $YARN_2; then
    if [ "$YARN2_SKIP_PRUNING" == "true" ]; then
      echo "Skipping because YARN2_SKIP_PRUNING is '$YARN2_SKIP_PRUNING'"
      meta_set "skipped-prune" "true"
      return 0
    fi
    cd "$build_dir" || return
    echo "Running 'yarn heroku prune'"
    export YARN_PLUGINS="${buildpack_dir}/yarn2-plugins/prune-dev-dependencies/bundles/@yarnpkg/plugin-prune-dev-dependencies.js"
    monitor "yarn-prune" yarn heroku prune
    meta_set "skipped-prune" "false"
  else
    cd "$build_dir" || return
    monitor "yarn-prune" yarn install --frozen-lockfile --ignore-engines --ignore-scripts --prefer-offline 2>&1
    meta_set "skipped-prune" "false"
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

  npm_version=$(npm --version)
  # major_string will be ex: "4." "5." "10"
  local major_string=${npm_version:0:2}
  # strip any "."s from major_string
  local major=${major_string//.}

  # We should only run `npm ci` if all of the manifest files are there, and we are running at least npm 6.x
  # `npm ci` was introduced in the 5.x line in 5.7.0, but this sees very little usage, < 5% of builds
  if [[ -f "$build_dir/package.json" ]] && [[ "$(has_npm_lock "$build_dir")" == "true" ]] && (( major >= 6 )); then
    echo "true"
  else
    echo "false"
  fi
}

npm_node_modules() {
  local build_dir=${1:-}
  local production=${NPM_CONFIG_PRODUCTION:-false}

  if [ -e "$build_dir/package.json" ]; then
    cd "$build_dir" || return

    if [[ "$USE_NPM_INSTALL" == "false" ]]; then
      meta_set "use-npm-ci" "true"
      echo "Installing node modules"
      monitor "npm-install" npm ci --production="$production" --unsafe-perm --userconfig "$build_dir/.npmrc" 2>&1
    else
      meta_set "use-npm-ci" "false"
      if [ -e "$build_dir/package-lock.json" ]; then
        echo "Installing node modules (package.json + package-lock)"
      elif [ -e "$build_dir/npm-shrinkwrap.json" ]; then
        echo "Installing node modules (package.json + shrinkwrap)"
      else
        echo "Installing node modules (package.json)"
      fi
      monitor "npm-install" npm install --production="$production" --unsafe-perm --userconfig "$build_dir/.npmrc" 2>&1
    fi
  else
    echo "Skipping (no package.json)"
  fi
}

npm_rebuild() {
  local build_dir=${1:-}
  local production=${NPM_CONFIG_PRODUCTION:-false}

  if [ -e "$build_dir/package.json" ]; then
    cd "$build_dir" || return
    echo "Rebuilding any native modules"
    npm rebuild 2>&1
    if [ -e "$build_dir/npm-shrinkwrap.json" ]; then
      echo "Installing any new modules (package.json + shrinkwrap)"
    else
      echo "Installing any new modules (package.json)"
    fi
    monitor "npm-rebuild" npm install --production="$production" --unsafe-perm --userconfig "$build_dir/.npmrc" 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}

npm_prune_devdependencies() {
  local npm_version
  local build_dir=${1:-}

  npm_version=$(npm --version)

  if [ "$NODE_ENV" == "test" ]; then
    echo "Skipping because NODE_ENV is 'test'"
    meta_set "skipped-prune" "true"
    return 0
  elif [ "$NODE_ENV" != "production" ]; then
    echo "Skipping because NODE_ENV is not 'production'"
    meta_set "skipped-prune" "true"
    return 0
  elif [ -n "$NPM_CONFIG_PRODUCTION" ]; then
    echo "Skipping because NPM_CONFIG_PRODUCTION is '$NPM_CONFIG_PRODUCTION'"
    meta_set "skipped-prune" "true"
    return 0
  elif [ "$npm_version" == "5.3.0" ]; then
    mcount "skip-prune-issue-npm-5.3.0"
    echo "Skipping because npm 5.3.0 fails when running 'npm prune' due to a known issue"
    echo "https://github.com/npm/npm/issues/17781"
    echo ""
    echo "You can silence this warning by updating to at least npm 5.7.1 in your package.json"
    echo "https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version"
    meta_set "skipped-prune" "true"
    return 0
  elif [ "$npm_version" == "5.6.0" ] ||
       [ "$npm_version" == "5.5.1" ] ||
       [ "$npm_version" == "5.5.0" ] ||
       [ "$npm_version" == "5.4.2" ] ||
       [ "$npm_version" == "5.4.1" ] ||
       [ "$npm_version" == "5.2.0" ] ||
       [ "$npm_version" == "5.1.0" ]; then
    mcount "skip-prune-issue-npm-5.6.0"
    echo "Skipping because npm $npm_version sometimes fails when running 'npm prune' due to a known issue"
    echo "https://github.com/npm/npm/issues/19356"
    echo ""
    echo "You can silence this warning by updating to at least npm 5.7.1 in your package.json"
    echo "https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version"
    meta_set "skipped-prune" "true"
    return 0
  else
    cd "$build_dir" || return
    monitor "npm-prune" npm prune --userconfig "$build_dir/.npmrc" 2>&1
    meta_set "skipped-prune" "false"
  fi
}
