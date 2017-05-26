warnings=$(mktemp -t heroku-buildpack-nodejs-XXXX)

detect_package_manager() {
  case $YARN in
    true) echo "yarn";;
    *) echo "npm";;
  esac
}

failure_message() {
  local warn="$(cat $warnings)"
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

fail_invalid_package_json() {
  if ! cat ${1:-}/package.json | $JQ "." 1>/dev/null; then
    error "Unable to parse package.json"
    mcount 'failures.parse.package-json'
    return 1
  fi
}

fail_dot_heroku() {
  if [ -f "${1:-}/.heroku" ]; then
    header "Build failed"
    warn "The directory .heroku could not be created

       It looks like a .heroku file is checked into this project.
       The Node.js buildpack uses the hidden directory .heroku to store
       binaries like the node runtime and npm. You should remove the
       .heroku file or ignore it by adding it to .slugignore
       "
    exit 1
  fi
}

fail_dot_heroku_node() {
  if [ -f "${1:-}/.heroku/node" ]; then
    header "Build failed"
    warn "The directory .heroku/node could not be created

       It looks like a .heroku file is checked into this project.
       The Node.js buildpack uses the hidden directory .heroku to store
       binaries like the node runtime and npm. You should remove the
       .heroku file or ignore it by adding it to .slugignore
       "
    exit 1
  fi
}

fail_yarn_and_npm_lockfiles() {
  if [ -f "${1:-}/yarn.lock" ] && [ -f "${1:-}/package-lock.json" ]; then
    mcount "failures.two-lock-files"
    header "Build failed"
    warn "Two different lock files found: package-lock.json and yarn.lock

       Both npm and yarn have created lock files for this application,
       but only one can be used to install dependencies. Installing
       dependencies using the wrong package manager can result in missing
       packages or subtle bugs in production.

       - To use npm to install your application's dependencies please delete
         the yarn.lock file.

         $ git rm yarn.lock

       - To use yarn to install your application's dependences please delete
         the package-lock.json file.

         $ git rm package-lock.json
    " https://kb.heroku.com/why-is-my-node-js-build-failing-because-of-conflicting-lock-files
    exit 1
  fi
}

warning() {
  local tip=${1:-}
  local url=${2:-https://devcenter.heroku.com/articles/nodejs-support}
  echo "- $tip" >> $warnings
  echo "  $url" >> $warnings
  echo "" >> $warnings
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
    mcount 'warnings.node.unspecified'
  elif [ "$node_engine" == "*" ]; then
    warning "Dangerous semver range (*) in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
    mcount 'warnings.node.star'
  elif [ ${node_engine:0:1} == ">" ]; then
    warning "Dangerous semver range (>) in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
    mcount 'warnings.node.greater'
  fi
}

warn_prebuilt_modules() {
  local build_dir=${1:-}
  if [ -e "$build_dir/node_modules" ]; then
    warning "node_modules checked into source control" "https://blog.heroku.com/node-habits-2016#9-only-git-the-important-bits"
    mcount 'warnings.modules.prebuilt'
  fi
}

warn_missing_package_json() {
  local build_dir=${1:-}
  if ! [ -e "$build_dir/package.json" ]; then
    warning "No package.json found"
    mcount 'warnings.no-package'
  fi
}

warn_old_npm() {
  local npm_version="$(npm --version)"
  if [ "${npm_version:0:1}" -lt "2" ]; then
    local latest_npm="$(curl --silent --get --retry 5 --retry-max-time 15 https://semver.herokuapp.com/npm/stable)"
    warning "This version of npm ($npm_version) has several known issues - consider upgrading to the latest release ($latest_npm)" "https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version"
    mcount 'warnings.npm.old'
  fi
}

warn_young_yarn() {
  if $YARN; then
    warning "This project was built with yarn, which is new and under development. Some projects can still be built more reliably with npm" "https://devcenter.heroku.com/articles/nodejs-support#build-behavior"
    mcount 'warnings.yarn.young'
  fi
}

warn_untracked_dependencies() {
  local log_file="$1"
  if grep -qi 'gulp: not found' "$log_file" || grep -qi 'gulp: command not found' "$log_file"; then
    warning "Gulp may not be tracked in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
    mcount 'warnings.modules.untracked.gulp'
  fi
  if grep -qi 'grunt: not found' "$log_file" || grep -qi 'grunt: command not found' "$log_file"; then
    warning "Grunt may not be tracked in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
    mcount 'warnings.modules.untracked.grunt'
  fi
  if grep -qi 'bower: not found' "$log_file" || grep -qi 'bower: command not found' "$log_file"; then
    warning "Bower may not be tracked in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
    mcount 'warnings.modules.untracked.bower'
  fi
}

warn_angular_resolution() {
  local log_file="$1"
  if grep -qi 'Unable to find suitable version for angular' "$log_file"; then
    warning "Bower may need a resolution hint for angular" "https://github.com/bower/bower/issues/1746"
    mcount 'warnings.angular.resolution'
  fi
}

warn_missing_devdeps() {
  local log_file="$1"
  if grep -qi 'cannot find module' "$log_file"; then
    warning "A module may be missing from 'dependencies' in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
    mcount 'warnings.modules.missing'
    if [ "$NPM_CONFIG_PRODUCTION" == "true" ]; then
      local devDeps=$(read_json "$BUILD_DIR/package.json" ".devDependencies")
      if [ "$devDeps" != "" ]; then
        warning "This module may be specified in 'devDependencies' instead of 'dependencies'" "https://devcenter.heroku.com/articles/nodejs-support#devdependencies"
        mcount 'warnings.modules.devdeps'
      fi
    fi
  fi
}

warn_no_start() {
  local log_file="$1"
  if ! [ -e "$BUILD_DIR/Procfile" ]; then
    local startScript=$(read_json "$BUILD_DIR/package.json" ".scripts.start")
    if [ "$startScript" == "" ]; then
      if ! [ -e "$BUILD_DIR/server.js" ]; then
        warn "This app may not specify any way to start a node process" "https://devcenter.heroku.com/articles/nodejs-support#default-web-process-type"
        mcount 'warnings.unstartable'
      fi
    fi
  fi
}

warn_econnreset() {
  local log_file="$1"
  if grep -qi 'econnreset' "$log_file"; then
    warning "ECONNRESET issues may be related to npm versions" "https://github.com/npm/registry/issues/10#issuecomment-217141066"
    mcount 'warnings.econnreset'
  fi
}

warn_unmet_dep() {
  local log_file="$1"
  local package_manager=$(detect_package_manager)
  if grep -qi 'unmet dependency' "$log_file" || grep -qi 'unmet peer dependency' "$log_file"; then
    warn "Unmet dependencies don't fail $package_manager install but may cause runtime issues" "https://github.com/npm/npm/issues/7494"
    mcount 'warnings.modules.unmet'
  fi
}
