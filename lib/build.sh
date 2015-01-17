build_failed() {
  head "Build failed"
  echo ""
  cat $warnings | indent
  info "We're sorry this build is failing! If you can't find the issue in application code,"
  info "please submit a ticket so we can help: https://help.heroku.com/"
  info "You can also try reverting to our legacy Node.js buildpack:"
  info "heroku config:set BUILDPACK_URL=https://github.com/heroku/heroku-buildpack-nodejs#v63"
  info ""
  info "Love,"
  info "Heroku"
}

build_succeeded() {
  head "Build succeeded!"
  echo ""
  (npm ls --depth=0 || true) 2>/dev/null | indent
  cat $warnings | indent
}

get_start_method() {
  local build_dir=$1
  if test -f $build_dir/Procfile; then
    echo "Procfile"
  elif [[ $(read_json "$build_dir/package.json" ".scripts.start") != "" ]]; then
    echo "npm start"
  elif test -f $build_dir/server.js; then
    echo "server.js"
  else
    echo ""
  fi
}

get_modules_source() {
  local build_dir=$1
  if test -d $build_dir/node_modules; then
    echo "prebuilt"
  elif test -f $build_dir/npm-shrinkwrap.json; then
    echo "npm-shrinkwrap.json"
  elif test -f $build_dir/package.json; then
    echo "package.json"
  else
    echo ""
  fi
}

get_modules_cached() {
  local cache_dir=$1
  if test -d $cache_dir/node/node_modules; then
    echo "true"
  else
    echo "false"
  fi
}

# Sets:
# iojs_engine
# node_engine
# npm_engine
# start_method
# modules_source
# npm_previous
# node_previous
# modules_cached
# environment variables (from ENV_DIR)

read_current_state() {
  info "package.json..."
  assert_json "$build_dir/package.json"
  iojs_engine=$(read_json "$build_dir/package.json" ".engines.iojs")
  node_engine=$(read_json "$build_dir/package.json" ".engines.node")
  npm_engine=$(read_json "$build_dir/package.json" ".engines.npm")

  info "build directory..."
  start_method=$(get_start_method "$build_dir")
  modules_source=$(get_modules_source "$build_dir")

  info "cache directory..."
  npm_previous=$(file_contents "$cache_dir/node/npm-version")
  node_previous=$(file_contents "$cache_dir/node/node-version")
  modules_cached=$(get_modules_cached "$cache_dir")

  info "environment variables..."
  export_env_dir $env_dir
  export NPM_CONFIG_PRODUCTION=${NPM_CONFIG_PRODUCTION:-true}
  export NODE_MODULES_CACHE=${NODE_MODULES_CACHE:-true}
}

show_current_state() {
  echo ""
  if [ "$iojs_engine" == "" ]; then
    info "Node engine:         ${node_engine:-unspecified}"
  else
    achievement "iojs"
    info "Node engine:         $iojs_engine (iojs)"
  fi
  info "Npm engine:          ${npm_engine:-unspecified}"
  info "Start mechanism:     ${start_method:-none}"
  info "node_modules source: ${modules_source:-none}"
  info "node_modules cached: $modules_cached"
  echo ""

  printenv | grep ^NPM_CONFIG_ | indent
  info "NODE_MODULES_CACHE=$NODE_MODULES_CACHE"
}

install_node() {
  local node_engine=$1

  # Resolve non-specific node versions using semver.herokuapp.com
  if ! [[ "$node_engine" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    info "Resolving node version ${node_engine:-(latest stable)} via semver.io..."
    node_engine=$(curl --silent --get --data-urlencode "range=${node_engine}" https://semver.herokuapp.com/node/resolve)
  fi

  # Download node from Heroku's S3 mirror of nodejs.org/dist
  info "Downloading and installing node $node_engine..."
  node_url="http://s3pository.heroku.com/node/v$node_engine/node-v$node_engine-linux-x64.tar.gz"
  curl $node_url -s -o - | tar xzf - -C /tmp

  # Move node (and npm) into .heroku/node and make them executable
  mv /tmp/node-v$node_engine-linux-x64/* $heroku_dir/node
  chmod +x $heroku_dir/node/bin/*
  PATH=$heroku_dir/node/bin:$PATH
}

install_iojs() {
  local iojs_engine=$1

  # Resolve non-specific iojs versions using semver.herokuapp.com
  if ! [[ "$iojs_engine" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    info "Resolving iojs version ${iojs_engine:-(latest stable)} via semver.io..."
    iojs_engine=$(curl --silent --get --data-urlencode "range=${iojs_engine}" https://semver.herokuapp.com/iojs/resolve)
  fi

  # TODO: point at /dist once that's available
  info "Downloading and installing iojs $iojs_engine..."
  download_url="https://iojs.org/dist/v$iojs_engine/iojs-v$iojs_engine-linux-x64.tar.gz"
  curl $download_url -s -o - | tar xzf - -C /tmp

  # Move iojs/node (and npm) binaries into .heroku/node and make them executable
  mv /tmp/iojs-v$iojs_engine-linux-x64/* $heroku_dir/node
  chmod +x $heroku_dir/node/bin/*
  PATH=$heroku_dir/node/bin:$PATH
}

install_npm() {
  # Optionally bootstrap a different npm version
  if [ "$npm_engine" != "" ]; then
    if ! [[ "$npm_engine" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      info "Resolving npm version ${npm_engine} via semver.io..."
      npm_engine=$(curl --silent --get --data-urlencode "range=${npm_engine}" https://semver.herokuapp.com/npm/resolve)
    fi
    if [[ `npm --version` == "$npm_engine" ]]; then
      info "npm `npm --version` already installed with node"
    else
      info "Downloading and installing npm $npm_engine (replacing version `npm --version`)..."
      npm install --quiet -g npm@$npm_engine 2>&1 >/dev/null | indent
    fi
    warn_old_npm `npm --version`
  else
    info "Using default npm version: `npm --version`"
  fi
}

function build_dependencies() {
  if [ "$modules_source" == "" ]; then
    info "Skipping dependencies (no source for node_modules)"

  elif [ "$modules_source" == "prebuilt" ]; then
    info "Rebuilding any native modules for this architecture"
    npm rebuild 2>&1 | indent
    info "Installing any new modules"
    npm install --quiet --userconfig $build_dir/.npmrc 2>&1 | indent

  else
    cache_status=$(get_cache_status)

    if [ "$cache_status" == "valid" ]; then
      info "Restoring node modules from cache"
      cp -r $cache_dir/node/node_modules $build_dir/
      info "Pruning unused dependencies"
      npm prune 2>&1 | indent
      info "Installing any new modules"
      npm install --quiet --userconfig $build_dir/.npmrc 2>&1 | indent
    else
      info "$cache_status"
      info "Installing node modules"
      touch $build_dir/.npmrc
      npm install --quiet --userconfig $build_dir/.npmrc 2>&1 | indent
    fi
  fi
}

ensure_procfile() {
  local start_method=$1
  local build_dir=$2
  if [ "$start_method" == "Procfile" ]; then
    info "Found Procfile"
  elif test -f $build_dir/Procfile; then
    info "Procfile created during build"
  elif [ "$start_method" == "npm start" ]; then
    info "No Procfile; Adding 'web: npm start' to new Procfile"
    echo "web: npm start" > $build_dir/Procfile
  elif [ "$start_method" == "server.js" ]; then
    info "No Procfile; Adding 'web: node server.js' to new Procfile"
    echo "web: node server.js" > $build_dir/Procfile
  else
    info "None found"
  fi
}

write_profile() {
  info "Creating runtime environment"
  mkdir -p $build_dir/.profile.d
  echo "export PATH=\"\$HOME/.heroku/node/bin:\$HOME/bin:\$HOME/node_modules/.bin:\$PATH\"" > $build_dir/.profile.d/nodejs.sh
  echo "export NODE_HOME=\"\$HOME/.heroku/node\"" >> $build_dir/.profile.d/nodejs.sh
}

write_export() {
  info "Exporting binary paths"
  echo "export PATH=\"$build_dir/.heroku/node/bin:$build_dir/node_modules/.bin:\$PATH\"" > $bp_dir/export
  echo "export NODE_HOME=\"$build_dir/.heroku/node\"" >> $bp_dir/export
}

clean_npm() {
  info "Cleaning npm artifacts"
  rm -rf "$build_dir/.node-gyp"
  rm -rf "$build_dir/.npm"
}

# Caching

create_cache() {
  info "Caching results for future builds"
  mkdir -p $cache_dir/node

  echo `node --version` > $cache_dir/node/node-version
  echo `npm --version` > $cache_dir/node/npm-version

  if test -d $build_dir/node_modules; then
    cp -r $build_dir/node_modules $cache_dir/node
  fi
}

clean_cache() {
  info "Cleaning previous cache"
  rm -rf "$cache_dir/node_modules" # (for apps still on the older caching strategy)
  rm -rf "$cache_dir/node"
}

get_cache_status() {
  local node_version=`node --version`
  local npm_version=`npm --version`

  # Did we bust the cache?
  if ! $modules_cached; then
    echo "No cache available"
  elif ! $NODE_MODULES_CACHE; then
    echo "Cache disabled with NODE_MODULES_CACHE"
  elif [ "$node_previous" != "" ] && [ "$node_version" != "$node_previous" ]; then
    echo "Node version changed ($node_previous => $node_version); invalidating cache"
  elif [ "$npm_previous" != "" ] && [ "$npm_version" != "$npm_previous" ]; then
    echo "Npm version changed ($npm_previous => $npm_version); invalidating cache"
  else
    echo "valid"
  fi
}
