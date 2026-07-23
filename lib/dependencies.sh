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
