measure_size() {
  echo "$((du -s node_modules 2>/dev/null || echo 0) | awk '{print $1}')"
}

list_dependencies() {
  local build_dir="$1"

  cd "$build_dir"
  if $YARN; then
    echo ""
    (yarn list --depth=0 || true) 2>/dev/null
    echo ""
  else
    (npm ls --depth=0 | tail -n +2 || true) 2>/dev/null
  fi
}

run_if_present() {
  local script_name=${1:-}
  local has_script=$(read_json "$BUILD_DIR/package.json" ".scripts[\"$script_name\"]")
  if [ -n "$has_script" ]; then
    if $YARN; then
      echo "Running $script_name (yarn)"
      yarn run "$script_name"
    else
      echo "Running $script_name"
      npm run "$script_name" --if-present
    fi
  fi
}

log_build_scripts() {
  local build=$(read_json "$BUILD_DIR/package.json" ".scripts[\"build\"]")
  local heroku_prebuild=$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-prebuild\"]")
  local heroku_postbuild=$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-postbuild\"]")

  if [ -n "$build" ]; then
    mcount "scripts.build"

    if [ -z "$heroku_postbuild" ]; then
      mcount "scripts.build-without-heroku-postbuild"
    fi
  fi

  if [ -n "$heroku_prebuild" ]; then
    mcount "scripts.heroku-prebuild"
  fi

  if [ -n "$heroku_postbuild" ]; then
    mcount "scripts.heroku-postbuild"
  fi

  if [ -n "$heroku_postbuild" ] && [ -n "$build" ]; then
    mcount "scripts.build-and-heroku-postbuild"

    if [ "$heroku_postbuild" != "$build" ]; then
      mcount "scripts.different-build-and-heroku-postbuild"
    fi
  fi
}

yarn_node_modules() {
  local build_dir=${1:-}

  echo "Installing node modules (yarn.lock)"
  cd "$build_dir"
  yarn install --pure-lockfile --ignore-engines 2>&1
}

npm_node_modules() {
  local build_dir=${1:-}

  if [ -e $build_dir/package.json ]; then
    cd $build_dir

    if [ -e $build_dir/package-lock.json ]; then
      echo "Installing node modules (package.json + package-lock)"
    elif [ -e $build_dir/npm-shrinkwrap.json ]; then
      echo "Installing node modules (package.json + shrinkwrap)"
    else
      echo "Installing node modules (package.json)"
    fi
    npm install --unsafe-perm --userconfig $build_dir/.npmrc 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}

npm_rebuild() {
  local build_dir=${1:-}

  if [ -e $build_dir/package.json ]; then
    cd $build_dir
    echo "Rebuilding any native modules"
    npm rebuild 2>&1
    if [ -e $build_dir/npm-shrinkwrap.json ]; then
      echo "Installing any new modules (package.json + shrinkwrap)"
    else
      echo "Installing any new modules (package.json)"
    fi
    npm install --unsafe-perm --userconfig $build_dir/.npmrc 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}
