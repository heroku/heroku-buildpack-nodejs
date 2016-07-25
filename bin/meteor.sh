get_meteor_version() {
  if [ -e "${1:-}/.meteor/release" ]; then
    cat ${1:-}/.meteor/release
  fi
}

meteor_version=$(get_meteor_version ${1:-})

# Format of .meteor/release file is METEOR@1.4.x-patchsomething
meteor_node_version() {
  local meteor_release_version="$1"
  local meteor_version="$(echo $meteor_release_version | cut -d'@' -f2)"
  local minor="$(echo $meteor_version | cut -d'.' -f2)"
  if [ "$minor" -gt 3 ] ; then
    echo "4.4.x"
  else
    echo "0.10.x"
  fi
}

meteor_npm_version() {
  echo "3.x"
}

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
cd .app-build/bundle/programs/server
exec node \$NODE_BOOT_FLAGS boot.js program.json
EOF

  chmod +x "${build_dir}/.start-meteor-app"
}

install_phantomjs_linux() {
  local build_dir=$1
  local npm_dir="${build_dir}/.app-build/bundle/programs/server/npm"
  local dfischer_phantomjs_dir="/dfischer_phantomjs/node_modules/phantomjs"
  local phantom_dir_pre13="${npm_dir}${dfischer_phantomjs_dir}"
  local phantom_dir_post13="${npm_dir}/node_modules/meteor${dfischer_phantomjs_dir}"
  local phantom_dir=""

  [ -d "$phantom_dir_pre13" ] && phantom_dir=$phantom_dir_pre13
  [ -d "$phantom_dir_post13" ] && phantom_dir=$phantom_dir_post13

  if [ -n "$phantom_dir" ] ; then
    pushd $phantom_dir > /dev/null
    header "Phantomjs installation"
    node install.js 2>&1 | grep -v "${build_dir}" | grep -v '%' | output "$LOG_FILE"
    info "Phantomjs installed and ready"
    popd > /dev/null
  fi
}

clean_meteor_installation() {
  local build_dir=$1
  rm -rf "$METEOR_HOME"
  [ -d "${build_dir}/.meteor/local" ] && rm -rf "${build_dir}/.meteor/local"
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
    info "Removing your existing Meteor installation."
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
  local meteor_build_cache_dir="${build_dir}/.meteor/local"

  if [ -d "$cache_dir/meteor" ] ; then
    [ -d "$METEOR_HOME" ] && rm -fr "${METEOR_HOME}"
    cp -r "${cache_dir}/meteor" "${METEOR_HOME}"

    [ -d "${meteor_build_cache_dir}" ] && rm -rf "${meteor_build_cache_dir}"
    [ -d "${cache_dir}/meteor-local" ] && cp -r "${cache_dir}/meteor-local" "${meteor_build_cache_dir}" 
    cached_meteor_version=$(cat "$cache_dir/meteor-version")
  fi

  [ -e "$build_dir/.meteor/release" ] && local meteor_version=$(cat "$build_dir/.meteor/release")

  if [ -z "$cached_meteor_version" -o "$cached_meteor_version" != "$meteor_version" ] ; then
    mkdir -p ${METEOR_HOME}

    if [ "x${cached_meteor_version}" != "x" ] ; then
      header "Upgrading Meteor from ${cached_meteor_version} to ${meteor_version}"
    fi

    if [ -d "${meteor_build_cache_dir}" ] ; then
      info "Meteor build cache purged"
      rm -rf "${meteor_build_cache_dir}"
    fi

    install_meteor_dist $meteor_version
    header "Meteor installed → $meteor_version"
  else
    info "Meteor installed from cache → $meteor_version"
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

remove_mobile_platforms() {
  build_dir=$1
  platforms_file="${build_dir}/.meteor/platforms"
  [ ! -e "${platforms_file}" ] && return
  sed -i 's/^ios$//g' "${platforms_file}"
  sed -i 's/^android$//g' "${platforms_file}"
}

install_meteor_npm_package_json() {
  build_dir=$1
  cache_dir=$2

  pushd "$build_dir/.app-build/bundle/programs/server" >/dev/null
  npm install --unsafe-perm --userconfig $build_dir/.npmrc 2>&1 | output "$LOG_FILE"
  (npm ls --depth=0 | tail -n +2 || true) 2>/dev/null | output "$LOG_FILE"
  popd >/dev/null
}

cache_meteor_install() {
  build_dir=$1
  cache_dir=$2
  meteor_install=$3
  info "Caching meteor runtime for future builds"

  # If first build or new version of meteor, caching meteor install
  if [[ ! -e "$cache_dir/meteor-version" ]] || [[ "$meteor_version" != "$(cat $cache_dir/meteor-version)" ]] ; then
    [ -d "$cache_dir/meteor" ] && rm -rf "$cache_dir/meteor"
    cp -r "$meteor_install" "$cache_dir/meteor"
  fi

  [ -d "$cache_dir/meteor-local" ] && rm -rf "$cache_dir/meteor-local"
  cp -r "$build_dir/.meteor/local" "$cache_dir/meteor-local"
  echo $meteor_version > "$cache_dir/meteor-version"
}

build_meteor_app() {
  build_dir=$1
  cache_dir=$2

  METEOR_HOME="$build_dir/.meteor-install"
  [ -e "$build_dir/.meteor/release" ] && meteor_version=$(cat "$build_dir/.meteor/release")

  install_meteor "$build_dir" "$cache_dir"
  export PATH=$PATH:${METEOR_HOME}/.meteor

  check_meteorhacks_npm

  build_flags="--architecture os.linux.x86_64 --directory .app-build"
  BUILD_MOBILE_PLATFORMS_SERVER=${BUILD_MOBILE_PLATFORMS_SERVER:-false}
  METEOR_DEBUG_BUILD=${METEOR_DEBUG_BUILD:-false}

  if [ "x${BUILD_MOBILE_PLATFORMS_SERVER}" = "xtrue" ] ; then
    build_flags="--server-only ${build_flags}"
  else
    remove_mobile_platforms "$build_dir"
  fi

  if [ "x${METEOR_DEBUG_BUILD}" = "xtrue"  ] ; then
    build_flags="--debug ${build_flags}"
  fi

  info "Building Meteor Application - may take some time, be patient..."

  HOME=$METEOR_HOME meteor build $build_flags 2>&1 | \
    grep -v "under your source tree" | \
    grep -v "interpreted as source code" | \
    grep -v "a different directory instead" | \
    grep -v "meteor build ../output" | \
    output "$LOG_FILE"

  install_meteor_npm_package_json "$build_dir" "$cache_dir"
  cache_meteor_install "$build_dir" "$cache_dir" "$METEOR_HOME"
  info "Application built"
  install_phantomjs_linux $build_dir
  create_meteor_settings_profile $build_dir
  create_meteor_startup_file $build_dir
  clean_meteor_installation $build_dir
}
