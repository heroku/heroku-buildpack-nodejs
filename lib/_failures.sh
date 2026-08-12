#!/usr/bin/env bash

warnings=$(mktemp -t heroku-buildpack-nodejs-XXXX)

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

failure_message() {
  local warn

  warn="$(cat "$warnings")"

  echo ""
  echo "We're sorry this build is failing! You can troubleshoot common issues here:"
  echo "https://devcenter.heroku.com/articles/troubleshooting-node-deploys"
  echo ""
  if [ "$warn" != "" ]; then
    echo "Some possible problems:"
    echo ""
    echo "$warn"
  else
    echo "If you're stuck, please submit a ticket so we can help:"
    echo "https://help.heroku.com/"
  fi
  echo ""
  echo "Love,"
  echo "Heroku"
  echo ""
}

# Yarn 2 failures

log_other_failures() {
  local log_file="$1"

  if grep -qiE 'npm (ERR!|error) code EBADPLATFORM' "$log_file"; then
    build_data::set_string "failure" "npm-ebadplatform"
    return 0
  fi

  if grep -qiE 'npm (ERR!|error) code EINVALIDPACKAGENAME' "$log_file"; then
    build_data::set_string "failure" "npm-package-name-typo"
    return 0
  fi

  # Webpack Errors

  # Typescript errors

  if grep -q "JavaScript heap out of memory" "$log_file"; then
    build_data::set_string "failure" "node-out-of-memory"
    warn "Node.js Out-Of-Memory (OOM)

       This error can occur due to several reasons (large data handling, memory leaks, etc.) but the most
       common reason during a build is excessive concurrent operations from asset bundlers like
       Webpack, Vite, or Rollup. Your asset bundler configuration may include plugins to perform tasks such
       as minification or compilation using multiple parallel processes. In containerized environments,
       default settings for these tools may not be appropriate.

       If you are getting this error during asset compilation, check which plugins you have enabled and
       consult their documentation for configuration related to concurrent or parallel operations and
       either disable or set lower limits.

       As a temporary workaround, it's also possible to increase the memory limits of your Node.js process
       by prepending \`NODE_OPTIONS=\"--max-old-space-size=VALUE_IN_MB\"\` to the failing script.
       For example, \`NODE_OPTIONS=\"--max-old-space-size=4096\"\` would set a limit of 4GB. This should
       be done with caution as it doesn't solve the underlying issue of why this build requires higher
       memory limits.
    "
    fail
  fi

  # matches the subsequent lines of a stacktrace
  if grep -q 'at [^ ]* \([^ ]*:\d*\d*\)' "$log_file"; then
    build_data::set_string "failure" "unknown-stacktrace"
    return 0
  fi

  # If we've made it this far it's not an error we've added detection for yet
  # so classify by build step (if set) or default to unknown
  build_step=$(build_data::get_current "build_step")
  if [[ -n "$build_step" ]]; then
    build_data::set_string "failure" "unknown-$build_step-error"
  else
    build_data::set_string "failure" "unknown"
  fi
}

warning() {
  local tip=${1:-}
  local url=${2:-https://devcenter.heroku.com/articles/nodejs-support}
  {
  echo "- $tip"
  echo "  $url"
  echo ""
  } >> "$warnings"
}

warn() {
  local tip=${1:-}
  local url=${2:-https://devcenter.heroku.com/articles/nodejs-support}
  echo " !     $tip" || true
  echo "       $url" || true
  echo ""
}

warn_node_engine() {
  local node_engine=${1:-}
  if [ "$node_engine" == "" ]; then
    warning "Node version not specified in package.json" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
  elif [ "$node_engine" == "*" ]; then
    warning "Dangerous semver range (*) in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
  elif [ "${node_engine:0:1}" == ">" ]; then
    warning "Dangerous semver range (>) in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
  fi
}

warn_prebuilt_modules() {
  local build_dir=${1:-}
  if [ -e "$build_dir/node_modules" ]; then
    warning "node_modules checked into source control" "https://devcenter.heroku.com/articles/node-best-practices#only-git-the-important-bits"
  fi
}

warn_missing_package_json() {
  local build_dir=${1:-}
  if ! [ -e "$build_dir/package.json" ]; then
    warning "No package.json found"
  fi
}

warn_old_npm() {
  local npm_version latest_npm

  npm_version="$(npm --version)"

  if [ "$(package_managers::npm::version_major)" -lt "2" ]; then
    # Emit immediately rather than via warning(), whose $warnings buffer is only flushed by
    # failure_message on a failed build — so a migrated failure that bypasses the legacy
    # handler, or a successful build, would never surface this warning.
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

warn_untracked_dependencies() {
  local log_file="$1"
  if grep -qi 'gulp: not found' "$log_file" || grep -qi 'gulp: command not found' "$log_file"; then
    warning "Gulp may not be tracked in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
  fi
  if grep -qi 'grunt: not found' "$log_file" || grep -qi 'grunt: command not found' "$log_file"; then
    warning "Grunt may not be tracked in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
  fi
  if grep -qi 'bower: not found' "$log_file" || grep -qi 'bower: command not found' "$log_file"; then
    warning "Bower may not be tracked in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
  fi
}

warn_angular_resolution() {
  local log_file="$1"
  if grep -qi 'Unable to find suitable version for angular' "$log_file"; then
    warning "Bower may need a resolution hint for angular" "https://github.com/bower/bower/issues/1746"
  fi
}

warn_missing_devdeps() {
  local dev_deps
  local log_file="$1"
  local build_dir="$2"

  if grep -qi 'cannot find module' "$log_file"; then
    warning "A module may be missing from 'dependencies' in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
    if [ "$NPM_CONFIG_PRODUCTION" == "true" ]; then
      dev_deps=$(utils::json::read "$build_dir/package.json" ".devDependencies")
      if [ "$dev_deps" != "" ]; then
        warning "This module may be specified in 'devDependencies' instead of 'dependencies'" "https://devcenter.heroku.com/articles/nodejs-support#devdependencies"
      fi
    fi
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
