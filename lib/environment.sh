#!/usr/bin/env bash

get_os() {
  uname | tr '[:upper:]' '[:lower:]'
}

get_cpu() {
  if [[ "$(uname -p)" = "i686" ]]; then
    echo "x86"
  else
    echo "x64"
  fi
}

get_platform() {
  os=$(get_os)
  cpu=$(get_cpu)
  echo "$os-$cpu"
}

create_default_env() {
  local YARN=$1

  export NPM_CONFIG_LOGLEVEL=${NPM_CONFIG_LOGLEVEL:-error}
  export NODE_MODULES_CACHE=${NODE_MODULES_CACHE:-true}
  export NODE_ENV=${NODE_ENV:-production}
  export NODE_VERBOSE=${NODE_VERBOSE:-false}

  if $YARN; then
    export USE_YARN_CACHE=${USE_YARN_CACHE:-true}
  fi

  if [[ -n "$USE_NPM_INSTALL" ]]; then
    export USE_NPM_INSTALL=${USE_NPM_INSTALL}
  fi
}

create_build_env() {
  # if the user hasn't set NODE_OPTIONS, increase the default amount of space
  # that a node process can address to match that of the build dynos (2.5GB)
  if [[ -z $NODE_OPTIONS ]]; then
    export NODE_OPTIONS="--max_old_space_size=2560"
  fi
}

list_node_config() {
  echo ""
  printenv | grep ^NPM_CONFIG_ || true
  printenv | grep ^YARN_ || true
  printenv | grep ^USE_NPM_ || true
  printenv | grep ^USE_YARN_ || true
  printenv | grep ^NODE_ || true

  if [ "$NPM_CONFIG_PRODUCTION" = "true" ] && [ "$NODE_ENV" != "production" ]; then
    echo ""
    echo "npm scripts will see NODE_ENV=production (not '${NODE_ENV}')"
    echo "https://docs.npmjs.com/misc/config#production"
  fi

  if [ "$NPM_CONFIG_PRODUCTION" == "true" ]; then
    mcount "npm-config-production-true"
  elif [ "$NPM_CONFIG_PRODUCTION" == "false" ]; then
    mcount "npm-config-production-false"
  fi
}

export_env_dir() {
  local env_dir=$1
  if [ -d "$env_dir" ]; then
    local whitelist_regex=${2:-''}
    local blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH|LANG|BUILD_DIR)$'}
    # shellcheck disable=SC2164
    pushd "$env_dir" >/dev/null
    for e in *; do
      [ -e "$e" ] || continue
      echo "$e" | grep -E "$whitelist_regex" | grep -qvE "$blacklist_regex" &&
      export "$e=$(cat "$e")"
      :
    done
    # shellcheck disable=SC2164
    popd >/dev/null
  fi
}

write_profile() {
  local bp_dir="$1"
  local build_dir="$2"
  mkdir -p "$build_dir/.profile.d"
  cp "$bp_dir"/profile/* "$build_dir/.profile.d/"
}

write_ci_profile() {
  local bp_dir="$1"
  local build_dir="$2"
  write_profile "$1" "$2"
  cp "$bp_dir"/ci-profile/* "$build_dir/.profile.d/"
}

write_export() {
  local bp_dir="$1"
  local build_dir="$2"

  # only write the export script if the buildpack directory is writable.
  # this may occur in situations outside of Heroku, such as running the
  # buildpacks locally.
  if [ -w "$bp_dir" ]; then
    echo "export PATH=\"$build_dir/.heroku/node/bin:$build_dir/.heroku/yarn/bin:\$PATH:$build_dir/node_modules/.bin\"" > "$bp_dir/export"
    echo "export NODE_HOME=\"$build_dir/.heroku/node\"" >> "$bp_dir/export"
  fi
}
