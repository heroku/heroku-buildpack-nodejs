get_meteor_version() {
  if [ -e "${1:-}/.meteor/release" ]; then
    cat ${1:-}/.meteor/release
  fi
}

meteor_version=$(get_meteor_version ${1:-})

create_meteor_settings_profile() {
  local build_dir=$1
  local settings=""

  if [ -e "${build_dir}/settings.json" ] ; then
    settings="/settings.json"
  elif [ -d "${build_dir}/config" -a -e "${build_dir}/config/settings.json" ] ; then
    settings="/config/settings.json"
  fi

  if [ -n "${settings}" ] ; then
    header "${settings} detected, METEOR_SETTINGS will be set at runtime."
    cat > "$build_dir"/.profile.d/meteor-settings.sh <<EOF
    #!/bin/sh

    export METEOR_SETTINGS=\$(cat \$HOME$settings)
EOF
  fi
}

create_meteor_startup_file() {
  local build_dir=$1

  cat << EOF > "${build_dir}/.start-meteor-app"
cd demeteorized/bundle/programs/server
exec node boot.js program.json
EOF

  chmod +x "${build_dir}/.start-meteor-app"
}

# Hacky function to work over this bug https://github.com/onmodulus/demeteorizer/issues/152
install_phantomjs_linux() {
  local build_dir=$1
  local npm_dir="${build_dir}/demeteorized/bundle/programs/server/npm"
  local phantom_dir="${npm_dir}/dfischer_phantomjs/node_modules/phantomjs"

  if [ -d "$phantom_dir" ] ; then
    pushd $phantom_dir > /dev/null
    header "Installation of phantomjs"
    node install.js
    popd > /dev/null
  fi
}

clean_meteor_installation() {
  rm -rf "$METEOR_HOME"
}

## Install meteor distribution
# Params: install_meteor $release
# Install directory is .vendor/meteor
install_meteor_dist() {
  release=$1

  if echo $release | grep -q "@" ; then
    release=$(echo $release | cut -d '@' -f2)
  fi

  linux_arch=$(uname -m)
  if [ "${linux_arch}" = "i686" ] ; then
    platform="os.linux.x86_32"
  elif [ "${linux_arch}" = "x86_64" ] ; then
    platform="os.linux.x86_64"
  else
    echo "Unusable architecture: ${linux_arch}"
    echo "Meteor only supports i686 and x86_64 for now."
    exit 1
  fi

  # If you already have a tropohouse/warehouse, we do a clean install here:
  if [ -e "$METEOR_HOME/.meteor" ]; then
    echo "Removing your existing Meteor installation."
    rm -rf "$METEOR_HOME/.meteor"
  fi

  tarball_url="https://d3sqy0vbqsdhku.cloudfront.net/packages-bootstrap/${release}/meteor-bootstrap-${platform}.tar.gz"

  header "Downloading Meteor distribution"
  curl --silent --fail "${tarball_url}" | tar -xzf - -C "${METEOR_HOME}" -o

  header "Meteor ${release} has been installed."
}

install_meteor() {
  build_dir=$1
  cache_dir=$2
  local cached_meteor_version=""

  if [ -d "$cache_dir/meteor" ] ; then
    [ -d "$METEOR_HOME" ] && rm -fr "${METEOR_HOME}"
    cp -r "${cache_dir}/meteor" "${METEOR_HOME}"
    cached_meteor_version=$(cat "$cache_dir/meteor-version")
  fi

  [ -e "$build_dir/.meteor/release" ] && local meteor_version=$(cat "$build_dir/.meteor/release")

  if [ -z "$cached_meteor_version" -o "$cached_meteor_version" != "$meteor_version" ] ; then
    mkdir -p ${METEOR_HOME}
    install_meteor_dist $meteor_version
    header "Meteor installed → $meteor_version"
  else
    header "Meteor installed from cache → $meteor_version"
  fi
}

install_meteorite_deps() {
  build_dir=$1
  cache_dir=$2

  [ -d "$cache_dir/meteorite" ] && cp -r "$cache_dir/meteorite" "$build_dir/.meteorite"
  [ -d "$cache_dir/meteorite-packages" ] && cp -r "$cache_dir/meteorite-packages" "$build_dir/packages"

  if [ -e "$build_dir/smart.json" ] ; then
    if [ ! -e "$build_dir/smart.lock" ] ; then
      error "smart.lock is not present, run 'mrt install' to freeze dependencies"
      return 1
    fi
    npm install -g meteorite | output "$LOG_FILE"
    header "Meteorite installed"
    mrt install | output "$LOG_FILE"
    header "Meteorite packaged installed"
  fi
}

check_meteorhacks_npm() {
  meteorhacks_npm_version=$(grep meteorhacks:npm ".meteor/versions" || true)
  if [ -n "${meteorhacks_npm_version}" ] ; then
    warn_meteor_npm_dir
    warn_meteor_npm_packages_json
    warn_meteor_npm_package
  fi
}

install_demeteorizer() {
  npm install -g 'onmodulus/demeteorizer#v3.0.1' | output "$LOG_FILE"
  header "Demeteorizer installed"
}

remove_uninstallable_modules() {
  # Separe the modules names with '\n'
  uninstallable_modules="1to2"
  for module in $uninstallable_modules ; do
    out=$($JQ ".dependencies[\"${module}\"]" < "demeteorized/bundle/programs/server/package.json")
    if [ "$out" != "null" ] ; then
      cat "demeteorized/bundle/programs/server/package.json" | grep -v "${module}" > .tmp_package.json
      mv .tmp_package.json package.json
    fi
  done
}

remove_mobile_platforms() {
  build_dir=$1
  platforms_file="${build_dir}/.meteor/platforms"
  [ ! -e "${platforms_file}" ] && return
  sed -i 's/^ios$//g' "${platforms_file}"
  sed -i 's/^android$//g' "${platforms_file}"
}

demeteorize_app() {
  build_dir=$1
  cache_dir=$2

  METEOR_HOME="$build_dir/.meteor-install"
  [ -e "$build_dir/.meteor/release" ] && meteor_version=$(cat "$build_dir/.meteor/release")

  install_meteor "$build_dir" "$cache_dir"
  export PATH=$PATH:${METEOR_HOME}/.meteor

  install_meteorite_deps "$build_dir" "$cache_dir"
  install_demeteorizer
  check_meteorhacks_npm

  remove_mobile_platforms "$build_dir"
  # Build outside source dir to avoid warning:
  # Warning: The output directory is under your source tree.
  #          This causes issues when building with mobile platforms.
  #          Consider building into a different directory instead (meteor build ../output)
  tmp_build_dir=$(mktemp -d /tmp/demeteorized_XXXX)
  HOME=$METEOR_HOME demeteorizer -a os.linux.x86_64 -o "${tmp_build_dir}" | output "$LOG_FILE"
  rm -rf ${build_dir}/demeteorized && mv "${tmp_build_dir}" "${build_dir}/demeteorized"

  ln -s "demeteorized/bundle/programs/server/package.json" "package.json"

  header "Caching meteor runtime for future builds"
  rm -rf "$cache_dir/meteor"
  cp -r "$METEOR_HOME" "$cache_dir/meteor"
  echo $meteor_version > "$cache_dir/meteor-version"

  if [ -d "$build_dir/.meteorite" ] ; then
    header "Caching meteorite packages for future builds"
    rm -rf "$cache_dir/meteorite"
    rm -rf "$cache_dir/meteorite-packages"
    cp -r "$build_dir/packages" "$cache_dir/meteorite-packages"
    cp -r "$build_dir/.meteorite" "$cache_dir/meteorite"
  fi

  header "Application demeteorized"
  remove_uninstallable_modules
  install_phantomjs_linux $build_dir
  create_meteor_settings_profile $build_dir
  create_meteor_startup_file $build_dir
  clean_meteor_installation
}
