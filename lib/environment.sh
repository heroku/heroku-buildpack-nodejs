create_default_env() {
  export NPM_CONFIG_PRODUCTION=${NPM_CONFIG_PRODUCTION:-true}
  export NPM_CONFIG_LOGLEVEL=${NPM_CONFIG_LOGLEVEL:-error}
  export NODE_MODULES_CACHE=${NODE_MODULES_CACHE:-true}
  export NODE_ENV=${NODE_ENV:-production}
}

list_node_config() {
  echo ""
  printenv | grep ^NPM_CONFIG_ || true
  printenv | grep ^NODE_ || true

  if [ "$NPM_CONFIG_PRODUCTION" = "true" ] && [ "$NODE_ENV" != "production" ]; then
    echo ""
    echo "npm scripts will see NODE_ENV=production (not '${NODE_ENV}')"
    echo "https://docs.npmjs.com/misc/config#production"
  fi
}

export_env_dir() {
  local env_dir=$1
  if [ -d "$env_dir" ]; then
    local whitelist_regex=${2:-''}
    local blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH)$'}
    if [ -d "$env_dir" ]; then
      for e in $(ls $env_dir); do
        echo "$e" | grep -E "$whitelist_regex" | grep -qvE "$blacklist_regex" &&
        export "$e=$(cat $env_dir/$e)"
        :
      done
    fi
  fi
}

write_profile() {
  local bp_dir="$1"
  local build_dir="$2"
  mkdir -p $build_dir/.profile.d
  cp $bp_dir/profile/* $build_dir/.profile.d/
}

write_export() {
  local bp_dir="$1"
  local build_dir="$2"
  echo "export PATH=\"$build_dir/.heroku/node/bin:\$PATH:$build_dir/node_modules/.bin\"" > $bp_dir/export
  echo "export NODE_HOME=\"$build_dir/.heroku/node\"" >> $bp_dir/export
}
