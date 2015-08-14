install_node_modules() {
  local build_dir=${1:-}

  if [ -e $build_dir/package.json ]; then
    cd $build_dir
    echo "Pruning any extraneous modules"
    npm prune --unsafe-perm --userconfig $build_dir/.npmrc 2>&1
    if [ -e $build_dir/npm-shrinkwrap.json ]; then
      echo "Installing node modules (package.json + shrinkwrap)"
    else
      echo "Installing node modules (package.json)"
    fi
    npm install --unsafe-perm --userconfig $build_dir/.npmrc 2>&1
    if [ "$NPM_CONFIG_PRODUCTION" = "false" ] && [ "$NODE_ENV" = "production" ]; then
      echo "Pruning devDependencies"
      npm prune --unsafe-perm --userconfig $build_dir/.npmrc --production 2>&1
    fi
  else
    echo "Skipping (no package.json)"
  fi
}

rebuild_node_modules() {
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
    if [ "$NPM_CONFIG_PRODUCTION" = "false" ] && [ "$NODE_ENV" = "production" ]; then
      echo "Pruning devDependencies"
      npm prune --unsafe-perm --userconfig $build_dir/.npmrc --production 2>&1
    fi
  else
    echo "Skipping (no package.json)"
  fi
}
