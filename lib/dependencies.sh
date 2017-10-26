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
  local postinstall=$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-postbuild\"]")

  if [ -n "$build" ]; then
    mcount "scripts.build"

    if [ -z "$heroku_postbuild" ]; then
      mcount "scripts.build-without-heroku-postbuild"
    fi

    if [ -z "$postinstall" ]; then
      mcount "scripts.build-without-postinstall"
    fi

    if [ -z "$postinstall" ] && [ -z "$heroku_postbuild" ]; then
      mcount "scripts.build-without-other-hooks"
    fi
  fi

  if [ -n "$postinstall" ]; then
    mcount "scripts.postinstall"

    if [ "$postinstall" == "npm run build" ] ||
       [ "$postinstall" == "yarn run build" ] ||
       [ "$postinstall" == "yarn build" ]; then
      mcount "scripts.postinstall-is-npm-build"
    fi

  fi

  if [ -n "$heroku_prebuild" ]; then
    mcount "scripts.heroku-prebuild"
  fi

  if [ -n "$heroku_postbuild" ]; then
    mcount "scripts.heroku-postbuild"

    if [ "$heroku_postbuild" == "npm run build" ] ||
       [ "$heroku_postbuild" == "yarn run build" ] ||
       [ "$heroku_postbuild" == "yarn build" ]; then
      mcount "scripts.heroku-postbuild-is-npm-build"
    fi
  fi

  if [ -n "$heroku_postbuild" ] && [ -n "$build" ]; then
    mcount "scripts.build-and-heroku-postbuild"

    if [ "$heroku_postbuild" != "$build" ]; then
      mcount "scripts.different-build-and-heroku-postbuild"
    fi
  fi
}

yarn_supports_frozen_lockfile() {
  local yarn_version="$(yarn --version)"
  # Yarn versions lower than 0.19 will crash if passed --frozen-lockfile
  if [[ "$yarn_version" =~ ^0\.(16|17|18).*$ ]]; then
    mcount "yarn.doesnt-support-frozen-lockfile"
    false
  else
    true
  fi
}

yarn_node_modules() {
  local build_dir=${1:-}

  echo "Installing node modules (yarn.lock)"
  cd "$build_dir"
  if yarn_supports_frozen_lockfile; then
    yarn install --frozen-lockfile --ignore-engines 2>&1
  else
    yarn install --pure-lockfile --ignore-engines 2>&1
  fi
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
