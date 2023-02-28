#!/usr/bin/env bash

warnings=$(mktemp -t heroku-buildpack-nodejs-XXXX)

detect_package_manager() {
  case $YARN in
    true) echo "yarn";;
    *) echo "npm";;
  esac
}

fail() {
  meta_time "build-time" "$build_start_time"
  log_meta_data >> "$BUILDPACK_LOG_FILE"
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

fail_invalid_package_json() {
  local is_invalid

  is_invalid=$(is_invalid_json_file "${1:-}/package.json")

  if "$is_invalid"; then
    error "Unable to parse package.json"
    mcount 'failures.parse.package-json'
    meta_set "failure" "invalid-package-json"
    header "Build failed"
    failure_message
    fail
  fi
}

fail_dot_heroku() {
  if [ -f "${1:-}/.heroku" ]; then
    mcount "failures.dot-heroku"
    meta_set "failure" "dot-heroku"
    header "Build failed"
    warn "The directory .heroku could not be created

       It looks like a .heroku file is checked into this project.
       The Node.js buildpack uses the hidden directory .heroku to store
       binaries like the node runtime and npm. You should remove the
       .heroku file or ignore it by adding it to .slugignore
       "
    fail
  fi
}

fail_dot_heroku_node() {
  if [ -f "${1:-}/.heroku/node" ]; then
    mcount "failures.dot-heroku-node"
    meta_set "failure" "dot-heroku-node"
    header "Build failed"
    warn "The directory .heroku/node could not be created

       It looks like a .heroku file is checked into this project.
       The Node.js buildpack uses the hidden directory .heroku to store
       binaries like the node runtime and npm. You should remove the
       .heroku file or ignore it by adding it to .slugignore
       "
    fail
  fi
}

fail_iojs_unsupported() {
  local build_dir="$1"
  local iojs_engine
  iojs_engine=$(read_json "$build_dir/package.json" ".engines.iojs")

  if [ -n "$iojs_engine" ]; then
    mcount "failures.iojs-unsupported"
    meta_set "failure" "iojs-unsupported"
    warn "io.js no longer supported

       You are specifying an io.js version in your package.json:

       \"engines\": {
         ...
         \"iojs\": \"${iojs_engine}\"
       }

       io.js merged back into Nodejs.org in 2015 and has been unsupported
       for many years. It is likely to contain several large security
       vulnerabilities that have been patched in Node.

       You can update your app to use the official Node.js release by
       removing the version specfication under \"engines\" in your
       package.json.
       "
    fail
  fi
}

fail_multiple_lockfiles() {
  local has_modern_lockfile=false
  if [ -f "${1:-}/yarn.lock" ] || [ -f "${1:-}/package-lock.json" ]; then
    has_modern_lockfile=true
  fi

  if [ -f "${1:-}/yarn.lock" ] && [ -f "${1:-}/package-lock.json" ]; then
    mcount "failures.two-lock-files"
    meta_set "failure" "two-lock-files"
    header "Build failed"
    warn "Two different lockfiles found: package-lock.json and yarn.lock

       Both npm and yarn have created lockfiles for this application,
       but only one can be used to install dependencies. Installing
       dependencies using the wrong package manager can result in missing
       packages or subtle bugs in production.

       - To use npm to install your application's dependencies please delete
         the yarn.lock file.

         $ git rm yarn.lock

       - To use yarn to install your application's dependencies please delete
         the package-lock.json file.

         $ git rm package-lock.json
    " https://help.heroku.com/0KU2EM53
    fail
  fi

  if $has_modern_lockfile && [ -f "${1:-}/npm-shrinkwrap.json" ]; then
    mcount "failures.shrinkwrap-lock-file-conflict"
    meta_set "failure" "shrinkwrap-lock-file-conflict"
    header "Build failed"
    warn "Two different lockfiles found

       Your application has two lockfiles defined, but only one can be used
       to install dependencies. Installing dependencies using the wrong lockfile
       can result in missing packages or subtle bugs in production.

       It's most likely that you recently installed yarn which has its own
       lockfile by default, which conflicts with the shrinkwrap file you've been
       using.

       Please make sure there is only one of the following files in your
       application directory:

       - yarn.lock
       - package-lock.json
       - npm-shrinkwrap.json
    " https://help.heroku.com/0KU2EM53
    fail
  fi
}

fail_yarn_outdated() {
  local yarn_engine
  local log_file="$1"

  if grep -qi 'error .install. has been replaced with .add. to add new dependencies' "$log_file"; then
    yarn_engine=$(yarn --version)
    mcount "failures.outdated-yarn"
    meta_set "failure" "outdated-yarn"
    echo ""
    warn "Outdated Yarn version: $yarn_engine

       Your application is specifying a requirement on an old version of Yarn ($yarn_engine)
       which does not support the --frozen-lockfile option. Please upgrade to a
       newer version, at least 0.19, by updating your requirement in the 'engines'
       field in your package.json.

       \"engines\": {
         \"yarn\": \"1.3.2\"
       }
    " https://devcenter.heroku.com/articles/nodejs-support#specifying-a-yarn-version
    fail
  fi
}

fail_yarn_lockfile_outdated() {
  local log_file="$1"
  if grep -qi 'Your lockfile needs to be updated' "$log_file"; then
    mcount "failures.outdated-yarn-lockfile"
    meta_set "failure" "outdated-yarn-lockfile"
    echo ""
    warn "Outdated Yarn lockfile

       Your application contains a Yarn lockfile (yarn.lock) which does not
       match the dependencies in package.json. This can happen if you use npm
       to install or update a dependency instead of Yarn.

       Please run the following command in your application directory and check
       in the new yarn.lock file:

       $ yarn install
       $ git add yarn.lock
       $ git commit -m \"Updated Yarn lockfile\"
       $ git push heroku main
    " https://help.heroku.com/TXYS53YJ
    fail
  fi
}

fail_bin_install() {
  local error
  local bin="$1"
  local version="$2"

  # Allow the subcommand to fail without trapping the error so we can
  # get the failing message output
  set +e

  # re-request the result, saving off the reason for the failure this time
  error=$($RESOLVE "$BP_DIR/inventory/$bin.toml" "$version" 2>&1)

  # re-enable trapping
  set -e

  if [[ $error = "No result" ]]; then
    case $bin in
      node)
        echo "Could not find Node version corresponding to version requirement: $version";;
      iojs)
        echo "Could not find Iojs version corresponding to version requirement: $version";;
      yarn)
        echo "Could not find Yarn version corresponding to version requirement: $version";;
    esac
  elif [[ $error == "Could not parse"* ]] || [[ $error == "Could not get"* ]]; then
    echo "Error: Invalid semantic version \"$version\""
  else
    echo "Error: Unknown error installing \"$version\" of $bin"
  fi

  return 1
}

fail_node_install() {
  local node_engine
  local log_file="$1"
  local build_dir="$2"

  if grep -qi 'Could not find Node version corresponding to version requirement' "$log_file"; then
    node_engine=$(read_json "$build_dir/package.json" ".engines.node")
    mcount "failures.invalid-node-version"
    meta_set "failure" "invalid-node-version"
    echo ""
    warn "No matching version found for Node: $node_engine

       Heroku supports the latest Stable version of Node.js as well as all
       active LTS (Long-Term-Support) versions, however you have specified
       a version in package.json ($node_engine) that does not correspond to
       any published version of Node.js.

       You should always specify a Node.js version that matches the runtime
       you’re developing and testing with. To find your version locally:

       $ node --version
       v6.11.1

       Use the engines section of your package.json to specify the version of
       Node.js to use on Heroku. Drop the ‘v’ to save only the version number:

       \"engines\": {
         \"node\": \"6.11.1\"
       }
    " https://help.heroku.com/6235QYN4/
    fail
  fi
}

fail_yarn_install() {
  local yarn_engine
  local log_file="$1"
  local build_dir="$2"

  if grep -qi 'Could not find Yarn version corresponding to version requirement' "$log_file"; then
    yarn_engine=$(read_json "$build_dir/package.json" ".engines.yarn")
    mcount "failures.invalid-yarn-version"
    meta_set "failure" "invalid-yarn-version"
    echo ""
    warn "No matching version found for Yarn: $yarn_engine

       Heroku supports most versions of Yarn published on npm, however you have
       specified a version in package.json ($yarn_engine) that does not correspond
       to any published version of Yarn. You can see a list of all published
       versions of Yarn with the following command:

       $ yarn info yarn versions

       You should always specify a Yarn version that matches the version
       you’re developing and testing with. To find your version locally:

       $ yarn --version
       1.12.3

       Use the engines section of your package.json to specify the version of
       Yarn to use on Heroku.

       \"engines\": {
         \"yarn\": \"1.x\"
       }
    " https://help.heroku.com/8MEL050H
    fail
  fi
}

fail_invalid_semver() {
  local log_file="$1"
  if grep -qi 'Error: Invalid semantic version' "$log_file"; then
    mcount "failures.invalid-semver-requirement"
    meta_set "failure" "invalid-semver-requirement"
    echo ""
    warn "Invalid semver requirement

       Node, Yarn, and npm adhere to semver, the semantic versioning convention
       popularized by GitHub.

       http://semver.org/

       However you have specified a version requirement that is not a valid
       semantic version.
    " https://help.heroku.com/0ZIOF3ST
    fail
  fi
}

# Yarn 2 failures

fail_using_yarn2_with_yarn_production_environment_variable_set() {
  local yarn_engine
  local skip_pruning
  local log_file="$1"

  if grep -qi 'Unrecognized or legacy configuration settings found: production' "$log_file"; then
    yarn_engine=$(yarn --version)
    if [[ "$YARN_PRODUCTION" == "true" ]]; then
      skip_pruning=false
    else
      skip_pruning=true
    fi

    mcount "failures.yarn2-with-yarn-production-env-set"
    meta_set "failure" "yarn2-with-yarn-production-env-set"
    echo ""
    warn "Legacy Yarn 1.x configuration present:

       Your application uses Yarn v$yarn_engine which does not support the YARN_PRODUCTION environment variable. Please
       update your heroku config vars to remove YARN_PRODUCTION and set YARN2_SKIP_PRUNING instead.

         $ heroku config:unset YARN_PRODUCTION && heroku config:set YARN2_SKIP_PRUNING=$skip_pruning
    " https://devcenter.heroku.com/articles/nodejs-support#skip-pruning
    fail
  fi
}

fail_missing_yarnrc_yml() {
  local build_dir="$1"

  if [[ ! -f "$build_dir/.yarnrc.yml" ]]; then
    mcount "failures.missing-yarnrc-yml"
    meta_set "failure" "missing-yarnrc-yml"
    header "Build failed"
    warn "The 'yarnrc.yml' file is not found

      It looks like the 'yarnrc.yml' file is missing from this project. Please
      make sure this file is checked into version control and made available to
      Heroku.

      To generate 'yarnrc.yml', make sure Yarn 2 is installed on your local
      machine and set the version in your project directory with:

       $ yarn set version berry

      Read more at the Yarn docs: https://yarnpkg.com/getting-started/install#per-project-install
      "
    fail
  fi
}

fail_missing_yarn_path() {
  local build_dir="$1"
  local yarn_path="$2"

  if [[ "$yarn_path" == "" ]]; then
    mcount "failures.missing-yarn-path"
    meta_set "failure" "missing-yarn-path"
    header "Build failed"
    warn "The 'yarnPath' could not be read from the 'yarnrc.yml' file

      It looks like 'yarnrc.yml' is missing the 'yarnPath' value, which is needed
      to identify the location of yarn for this build.

      To regenerate 'yarnrc.yml' with the 'yarnPath' value set, make sure Yarn 2
      is installed on your local machine and set the version in your project
      directory with:

       $ yarn set version berry

      Read more at the Yarn docs: https://yarnpkg.com/getting-started/install#per-project-install
      "
    fail
  fi
}

fail_missing_yarn_vendor() {
  local build_dir="$1"
  local yarn_path="$2"

  if [[ ! -f "$build_dir/$yarn_path" ]]; then
    mcount "failures.missing-yarn-vendor"
    meta_set "failure" "missing-yarn-vendor"
    header "Build failed"
    warn "Yarn was not found

      It looks like yarn is missing from $yarn_path, which is needed to continue
      this build on Heroku. Yarn 2 recommends vendoring Yarn under the '.yarn/releases'
      directory, so remember to check the '.yarn' directory into version control
      to use during builds.

      To generate the '.yarn' directory correctly, make sure Yarn 2 is installed
      on your local machine and run the following in your project directory:

       $ yarn install
       $ yarn set version berry

      Read more at the Yarn docs: https://yarnpkg.com/getting-started/install#per-project-install
      "
    fail
  fi
}

log_other_failures() {
  local log_file="$1"

  if grep -qP "version \`GLIBC_\d+\.\d+' not found" "$log_file"; then
    mcount "failures.libc6-incompatibility"
    meta_set "failure" "libc6-incompatibility"
    warn "This Node.js version is not compatible with the current stack.

       For Node.js versions 18 and greater, heroku-20 or newer is required.
       Consider updating to a stack that is compatible with the Node.js version
       or pinning the Node.js version to be compatible with the current
       stack." https://help.heroku.com/R7DTSTD0

    return 0
  fi

  if grep -qi "sh: 1: .*: not found" "$log_file"; then
    mcount "failures.dev-dependency-tool-not-installed"
    meta_set "failure" "dev-dependency-tool-not-installed"
    return 0
  fi

  if grep -qi "Failed at the bcrypt@\d.\d.\d install script" "$log_file"; then
    mcount "failures.bcrypt-permissions-issue"
    meta_set "failure" "bcrypt-permissions-issue"
    return 0
  fi

  if grep -qi "Versions of @angular/compiler-cli and typescript could not be determined" "$log_file"; then
    mcount "failures.ng-cli-version-issue"
    meta_set "failure" "ng-cli-version-issue"
    return 0
  fi

  if grep -qi "Cannot read property '0' of undefined" "$log_file"; then
    mcount "failures.npm-property-zero-issue"
    meta_set "failure" "npm-property-zero-issue"
    return 0
  fi

  if grep -qi "npm is known not to run on Node.js v\d.\d.\d" "$log_file"; then
    mcount "failures.npm-known-bad-version"
    meta_set "failure" "npm-known-bad-version"
    return 0
  fi

  # "notarget No matching version found for" = npm
  # "error Couldn't find any versions for" = yarn
  if grep -q -e "notarget No matching version found for" -e "error Couldn't find any versions for" "$log_file"; then
    mcount "failures.bad-version-for-dependency"
    meta_set "failure" "bad-version-for-dependency"
    return 0
  fi

  if grep -qi "You are likely using a version of node-tar or npm that is incompatible with this version of Node.js" "$log_file"; then
    mcount "failures.node-9-npm-issue"
    meta_set "failure" "node-9-npm-issue"
    return 0
  fi

  if grep -qi "console.error(\`a bug known to break npm" "$log_file"; then
    mcount "failures.old-node-new-npm"
    meta_set "failure" "old-node-new-npm"
    return 0
  fi

  if grep -qi "CALL_AND_RETRY_LAST Allocation failed" "$log_file"; then
    mcount "failures.build-out-of-memory-error"
    meta_set "failure" "build-out-of-memory-error"
    return 0
  fi

  if grep -qi "enoent ENOENT: no such file or directory" "$log_file"; then
    mcount "failures.npm-enoent"
    meta_set "failure" "npm-enoent"
    return 0
  fi

  if grep -qi "ERROR in [^ ]* from UglifyJs" "$log_file"; then
    mcount "failures.uglifyjs"
    meta_set "failure" "uglifyjs"
    return 0
  fi

  # https://github.com/angular/angular-cli/issues/4551
  if grep -qi "Module not found: Error: Can't resolve '\.\/\$\$_gendir\/app\/app\.module\.ngfactory'" "$log_file"; then
    mcount "failures.ng-cli-issue-4551"
    meta_set "failure" "ng-cli-issue-4551"
    return 0
  fi

  if grep -qi "Host key verification failed" "$log_file"; then
    mcount "failures.private-git-dependency-without-auth"
    meta_set "failure" "private-git-dependency-without-auth"
    return 0
  fi

  # same as the next test, but isolate bcyrpt specifically
  if grep -qi "Failed at the bcrypt@\d\.\d\.\d install" "$log_file"; then
    mcount "failures.bcrypt-failed-to-build"
    meta_set "failure" "bcrypt-failed-to-build"
    return 0
  fi

  if grep -qi "Failed at the [^ ]* install script" "$log_file"; then
    mcount "failures.dependency-failed-to-build"
    meta_set "failure" "dependency-failed-to-build"
    return 0
  fi

  if grep -qi "Line \d*:  '.*' is not defined" "$log_file"; then
    mcount "failures.undefined-variable-lint"
    meta_set "failure" "undefined-variable-lint"
    return 0
  fi

  if grep -qi "npm ERR! code EBADPLATFORM" "$log_file"; then
    mcount "failures.npm-ebadplatform"
    meta_set "failure" "npm-ebadplatform"
    return 0
  fi

  if grep -qi "npm ERR! code EINVALIDPACKAGENAME" "$log_file"; then
    mcount "failures.npm-package-name-typo"
    meta_set "failure" "npm-package-name-typo"
    return 0
  fi

  if grep -qi -e "npm ERR! code E404" -e "error An unexpected error occurred: .* Request failed \"404 Not Found\"" "$log_file"; then
    mcount "failures.module-404"
    meta_set "failure" "module-404"

    if grep -qi "flatmap-stream" "$log_file"; then
      mcount "flatmap-stream-404"
      meta_set "failure" "flatmap-stream-404"
      warn "The flatmap-stream module has been removed from the npm registry

       On November 26th, npm was notified of a malicious package that had made its
       way into event-stream, a popular npm package. After triaging the malware,
       npm responded by removing flatmap-stream and event-stream@3.3.6 from the Registry
       and taking ownership of the event-stream package to prevent further abuse.
      " https://help.heroku.com/4OM7X18J
      fail
    fi

    return 0
  fi

  if grep -qi "sh: 1: cd: can't cd to" "$log_file"; then
    mcount "failures.cd-command-fail"
    meta_set "failure" "cd-command-fail"
    return 0
  fi

  # Webpack Errors

  if grep -qi "Module not found: Error: Can't resolve" "$log_file"; then
    mcount "failures.webpack.module-not-found"
    meta_set "failure" "webpack-module-not-found"
    return 0
  fi

  if grep -qi "sass-loader/lib/loader.js:3:14" "$log_file"; then
    mcount "failures.webpack.sass-loader-error"
    meta_set "failure" "webpack-sass-loader-error"
    return 0
  fi

  # Typescript errors

  if grep -qi "Property '.*' does not exist on type '.*'" "$log_file"; then
    mcount "failures.typescript.missing-property"
    meta_set "failure" "typescript-missing-property"
    return 0
  fi

  if grep -qi "Property '.*' is private and only accessible within class '.*'" "$log_file"; then
    mcount "failures.typescript.private-property"
    meta_set "failure" "typescript-private-property"
    return 0
  fi

  if grep -qi "error TS2307: Cannot find module '.*'" "$log_file"; then
    mcount "failures.typescript.missing-module"
    meta_set "failure" "typescript-missing-module"
    return 0
  fi

  if grep -qi "error TS2688: Cannot find type definition file for '.*'" "$log_file"; then
    mcount "failures.typescript.missing-type-definition"
    meta_set "failure" "typescript-missing-type-definition"
    return 0
  fi

  # [^/C] means that the error is not for a file expected to be within the project
  # Ex: Error: Cannot find module 'chalk'
  if grep -q "Error: Cannot find module '[^/C\.]" "$log_file"; then
    mcount "failures.missing-module.npm"
    meta_set "failure" "missing-module-npm"
    return 0
  fi

  # / means that the error is for a file expected within the local project
  # Ex: Error: Cannot find module '/tmp/build_{hash}/...'
  if grep -q "Error: Cannot find module '/" "$log_file"; then
    mcount "failures.missing-module.local-absolute"
    meta_set "failure" "missing-module-local-absolute"
    return 0
  fi

  # /. means that the error is for a file that's a relative require
  # Ex: Error: Cannot find module './lib/utils'
  if grep -q "Error: Cannot find module '\." "$log_file"; then
    mcount "failures.missing-module.local-relative"
    meta_set "failure" "missing-module-local-relative"
    return 0
  fi

  # [^/C] means that the error is not for a file expected to be found on a C: drive
  # Ex: Error: Cannot find module 'C:\Users...'
  if grep -q "Error: Cannot find module 'C:" "$log_file"; then
    mcount "failures.missing-module.local-windows"
    meta_set "failure" "missing-module-local-windows"
    return 0
  fi

  # matches the subsequent lines of a stacktrace
  if grep -q 'at [^ ]* \([^ ]*:\d*\d*\)' "$log_file"; then
    mcount "failures.unknown-stacktrace"
    meta_set "failure" "unknown-stacktrace"
    return 0
  fi

  # If we've made it this far it's not an error we've added detection for yet
  meta_set "failure" "unknown"
  mcount "failures.unknown"
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

warn_aws_proxy() {
  if { [[ -n "$HTTP_PROXY" ]] || [[ -n "$HTTPS_PROXY" ]]; } && [[ "$NO_PROXY" != "amazonaws.com" ]]; then
    warn "Your build may fail if NO_PROXY is not set to amazonaws.com" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#aws-proxy-error"
  fi
}

warn_node_engine() {
  local node_engine=${1:-}
  if [ "$node_engine" == "" ]; then
    warning "Node version not specified in package.json" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
    mcount 'warnings.node.unspecified'
  elif [ "$node_engine" == "*" ]; then
    warning "Dangerous semver range (*) in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
    mcount 'warnings.node.star'
  elif [ "${node_engine:0:1}" == ">" ]; then
    warning "Dangerous semver range (>) in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
    mcount 'warnings.node.greater'
  fi
}

warn_prebuilt_modules() {
  local build_dir=${1:-}
  if [ -e "$build_dir/node_modules" ]; then
    warning "node_modules checked into source control" "https://devcenter.heroku.com/articles/node-best-practices#only-git-the-important-bits"
    mcount 'warnings.modules.prebuilt'
    meta_set "checked-in-node-modules" "true"
  else
    meta_set "checked-in-node-modules" "false"
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
  local npm_version latest_npm

  npm_version="$(npm --version)"

  if [ "${npm_version:0:1}" -lt "2" ]; then
    warning "This version of npm ($npm_version) has several known issues. Please update your npm version in package.json." "https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version"
    mcount 'warnings.npm.old'
  fi
}

warn_old_npm_lockfile() {
  local npm_version
  local npm_lock=$1

  npm_version="$(npm --version)"

  if $npm_lock && [ "${npm_version:0:1}" -lt "5" ]; then
    warn "This version of npm ($npm_version) does not support package-lock.json. Please
       update your npm version in package.json." "https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version"
    mcount 'warnings.npm.old-and-lockfile'
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
  local dev_deps
  local log_file="$1"
  local build_dir="$2"

  if grep -qi 'cannot find module' "$log_file"; then
    warning "A module may be missing from 'dependencies' in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
    mcount 'warnings.modules.missing'
    if [ "$NPM_CONFIG_PRODUCTION" == "true" ]; then
      dev_deps=$(read_json "$build_dir/package.json" ".devDependencies")
      if [ "$dev_deps" != "" ]; then
        warning "This module may be specified in 'devDependencies' instead of 'dependencies'" "https://devcenter.heroku.com/articles/nodejs-support#devdependencies"
        mcount 'warnings.modules.devdeps'
      fi
    fi
  fi
}

warn_no_start() {
  local start_script
  local build_dir="$1"

  if ! [ -e "$build_dir/Procfile" ]; then
    start_script=$(read_json "$build_dir/package.json" ".scripts.start")
    if [ "$start_script" == "" ]; then
      if ! [ -e "$build_dir/server.js" ]; then
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
  local package_manager
  local log_file="$1"

  package_manager=$(detect_package_manager)

  if grep -qi 'unmet dependency' "$log_file" || grep -qi 'unmet peer dependency' "$log_file"; then
    warn "Unmet dependencies don't fail $package_manager install but may cause runtime issues" "https://github.com/npm/npm/issues/7494"
    mcount 'warnings.modules.unmet'
  fi
}
