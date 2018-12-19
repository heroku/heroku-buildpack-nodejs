measure_size() {
  (du -s node_modules 2>/dev/null || echo 0) | awk '{print $1}'
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
      monitor "$script_name" yarn run "$script_name"
    else
      echo "Running $script_name"
      monitor "$script_name" npm run "$script_name" --if-present
    fi
  fi
}

run_build_script() {
  local has_build_script=$(read_json "$BUILD_DIR/package.json" ".scripts.build")
  local has_heroku_build_script=$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-postbuild\"]")

  if [[ -n "$has_heroku_build_script" ]] && [[ -n "$has_build_script" ]]; then
    echo "Detected both 'build' and 'heroku-postbuild' scripts"
    mcount "scripts.heroku-postbuild-and-build"
    run_if_present 'heroku-postbuild'
  elif [[ -n "$has_heroku_build_script" ]]; then
    mcount "scripts.heroku-postbuild"
    run_if_present 'heroku-postbuild'
  elif [[ -n "$has_build_script" ]]; then
    mcount "scripts.build"
    run_if_present 'build'
  fi
}

warn_build_script_behavior_opt_in() {
  local opted_in="$1"
  if [[ "$opted_in" = true ]]; then
    header "Opting in to new default build script behavior"
    echo "You have set \"heroku-run-build-script\" = true in your package.json"
    echo ""
    echo "- If a \"build\" script is defined in package.json it will be executed by default"
    echo "- The \"heroku-postbuild\" script will be executed instead if present"
  fi
}

log_build_scripts() {
  local build=$(read_json "$BUILD_DIR/package.json" ".scripts[\"build\"]")
  local heroku_prebuild=$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-prebuild\"]")
  local heroku_postbuild=$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-postbuild\"]")
  local postinstall=$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-postbuild\"]")

  bd_set "build-script" "$build"
  bd_set "postinstall-script" "$postinstall"
  bd_set "heroku-prebuild-script" "$heroku_prebuild"
  bd_set "heroku-postbuild-script" "$heroku_prebuild"

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

yarn_node_modules() {
  local build_dir=${1:-}
  local production=${YARN_PRODUCTION:-false}

  echo "Installing node modules (yarn.lock)"
  cd "$build_dir"
  monitor "yarn-install" yarn install --production=$production --frozen-lockfile --ignore-engines 2>&1
}

yarn_prune_devdependencies() {
  local build_dir=${1:-} 

  if [ "$NODE_ENV" == "test" ]; then
    echo "Skipping because NODE_ENV is 'test'"
    bd_set "skipped-prune" "true"
    return 0
  elif [ "$NODE_ENV" != "production" ]; then
    echo "Skipping because NODE_ENV is not 'production'"
    bd_set "skipped-prune" "true"
    return 0
  elif [ -n "$YARN_PRODUCTION" ]; then
    echo "Skipping because YARN_PRODUCTION is '$YARN_PRODUCTION'"
    bd_set "skipped-prune" "true"
    return 0
  else 
    cd "$build_dir" 
    monitor "yarn-prune" yarn install --frozen-lockfile --ignore-engines --ignore-scripts --prefer-offline 2>&1
    bd_set "skipped-prune" "false"
  fi
}

npm_node_modules() {
  local build_dir=${1:-}
  local production=${NPM_CONFIG_PRODUCTION:-false}

  if [ -e $build_dir/package.json ]; then
    cd $build_dir

    if [ -e $build_dir/package-lock.json ]; then
      echo "Installing node modules (package.json + package-lock)"
    elif [ -e $build_dir/npm-shrinkwrap.json ]; then
      echo "Installing node modules (package.json + shrinkwrap)"
    else
      echo "Installing node modules (package.json)"
    fi
    monitor "npm-install" npm install --production=$production --unsafe-perm --userconfig $build_dir/.npmrc 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}

npm_rebuild() {
  local build_dir=${1:-}
  local production=${NPM_CONFIG_PRODUCTION:-false}

  if [ -e $build_dir/package.json ]; then
    cd $build_dir
    echo "Rebuilding any native modules"
    npm rebuild 2>&1
    if [ -e $build_dir/npm-shrinkwrap.json ]; then
      echo "Installing any new modules (package.json + shrinkwrap)"
    else
      echo "Installing any new modules (package.json)"
    fi
    monitor "npm-rebuild" npm install --production=$production --unsafe-perm --userconfig $build_dir/.npmrc 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}

npm_prune_devdependencies() {
  local build_dir=${1:-} 
  local npm_version=$(npm --version)

  if [ "$NODE_ENV" == "test" ]; then
    echo "Skipping because NODE_ENV is 'test'"
    bd_set "skipped-prune" "true"
    return 0
  elif [ "$NODE_ENV" != "production" ]; then
    echo "Skipping because NODE_ENV is not 'production'"
    bd_set "skipped-prune" "true"
    return 0
  elif [ -n "$NPM_CONFIG_PRODUCTION" ]; then
    echo "Skipping because NPM_CONFIG_PRODUCTION is '$NPM_CONFIG_PRODUCTION'"
    bd_set "skipped-prune" "true"
    return 0
  elif [ "$npm_version" == "5.3.0" ]; then
    mcount "skip-prune-issue-npm-5.3.0"
    echo "Skipping because npm 5.3.0 fails when running 'npm prune' due to a known issue"
    echo "https://github.com/npm/npm/issues/17781"
    echo ""
    echo "You can silence this warning by updating to at least npm 5.7.1 in your package.json"
    echo "https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version"
    bd_set "skipped-prune" "true"
    return 0
  elif [ "$npm_version" == "5.6.0" ] ||
       [ "$npm_version" == "5.5.1" ] ||
       [ "$npm_version" == "5.5.0" ] ||
       [ "$npm_version" == "5.4.2" ] ||
       [ "$npm_version" == "5.4.1" ] ||
       [ "$npm_version" == "5.2.0" ] ||
       [ "$npm_version" == "5.1.0" ]; then
    mcount "skip-prune-issue-npm-5.6.0"
    echo "Skipping because npm $npm_version sometimes fails when running 'npm prune' due to a known issue"
    echo "https://github.com/npm/npm/issues/19356"
    echo ""
    echo "You can silence this warning by updating to at least npm 5.7.1 in your package.json"
    echo "https://devcenter.heroku.com/articles/nodejs-support#specifying-an-npm-version"
    bd_set "skipped-prune" "true"
    return 0
  else
    cd "$build_dir" 
    monitor "npm-prune" npm prune --userconfig $build_dir/.npmrc 2>&1
    bd_set "skipped-prune" "false"
  fi
}
