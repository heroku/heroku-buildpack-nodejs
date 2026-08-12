#!/usr/bin/env bash

detect_package_manager() {
  case $YARN in
    true) echo "yarn";;
    *) echo "npm";;
  esac
}

fail() {
  build_data::set_duration "build_time" "$build_start_time"
  exit 1
}

warn() {
  local tip=${1:-}
  local url=${2:-https://devcenter.heroku.com/articles/nodejs-support}
  echo " !     $tip" || true
  echo "       $url" || true
  echo ""
}

warn_old_npm() {
  local npm_version latest_npm

  npm_version="$(npm --version)"

  if [ "$(package_managers::npm::version_major)" -lt "2" ]; then
    # Emit immediately via output::warning so this surfaces during the build.
    output::warning <<-EOF
			This version of npm ($npm_version) has several known issues. Please update your npm version in package.json.

			https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version
		EOF
  fi
}

warn_old_npm_lockfile() {
  local npm_version
  local npm_lock=$1

  npm_version="$(npm --version)"

  if $npm_lock && [ "$(package_managers::npm::version_major)" -lt "5" ]; then
    warn "This version of npm ($npm_version) does not support package-lock.json. Please
       update your npm version in package.json." "https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version"
  fi
}

warn_no_start() {
  local start_script
  local build_dir="$1"

  if ! [ -e "$build_dir/Procfile" ]; then
    start_script=$(utils::json::read "$build_dir/package.json" ".scripts.start")
    if [ "$start_script" == "" ]; then
      if ! [ -e "$build_dir/server.js" ]; then
        warn "This app may not specify any way to start a node process" "https://devcenter.heroku.com/articles/nodejs-support#default-web-process-type"
      fi
    fi
  fi
}


warn_unmet_dep() {
  local package_manager
  local log_file="$1"

  package_manager=$(detect_package_manager)

  if grep -qi 'unmet dependency' "$log_file" || grep -qi 'unmet peer dependency' "$log_file"; then
    warn "Unmet dependencies don't fail $package_manager install but may cause runtime issues" "https://github.com/npm/npm/issues/7494"
  fi
}

warn_skipping_unsafe_pnpm_prune() {
  local pnpm_version="$1"
  warn "Pruning skipped due to presence of lifecycle scripts

       The version of pnpm used ($pnpm_version) will execute the following lifecycle scripts
       declared in package.json during pruning which can cause build failures:
       - pnpm:devPreinstall
       - preinstall
       - install
       - postinstall
       - prepare

       Since pruning can't be done safely for your build, it will be skipped. To fix this you
       must upgrade your version of pnpm to 8.15.6 or higher."
}

warn_skipping_unsafe_pnpm_workspace_prune() {
  local project_path="$1"
  echo "
! Pruning skipped due to presence of lifecycle scripts

Lifecycle scripts were detected in the \`package.json\` file at \`$project_path\`. Due to how
workspace pruning in pnpm operates, it will execute the following lifecycle scripts declared
in package.json during reinstallation of prod dependencies which can cause build failures:
- pnpm:devPreinstall
- preinstall
- install
- postinstall
- prepare

Since pruning can't be done safely for your build, it will be skipped."
}
