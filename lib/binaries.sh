install_yarn() {
  local dir="$1"
  local version=${2:-1.x}
  local number
  local url
  local yarn_path="/tmp/yarn.tar.gz"

  echo "Resolving yarn version $version..."
  if ! read number url < <(curl --silent --get --retry 5 --retry-max-time 15 --data-urlencode "range=$version" "https://nodebin.herokai.com/v1/yarn/$platform/latest.txt"); then
    fail_bin_install yarn $version;
  fi

  local cache="$CACHE_DIR/node/yarn-$(echo -n "$url" | sha256sum | awk '{print $1}').tar.gz"
  if [ -f $cache ]; then
    mv "$cache" "$yarn_path"
    echo "$yarn_path $cache" >> "$BINCACHE_FILE"
  else
    rm -f "$CACHE_DIR/node/yarn-*.tar.gz"
    echo "Downloading and installing yarn ($number)..."
    local code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 -o "$yarn_path" --write-out "%{http_code}")
    if [ "$code" != "200" ]; then
      echo "Unable to download yarn: $code" && false
    fi
    echo "$yarn_path $cache" >> "$BINCACHE_FILE"
  fi
  rm -rf $dir
  mkdir -p "$dir"
  # https://github.com/yarnpkg/yarn/issues/770
  if tar --version | grep -q 'gnu'; then
    tar xzf "$yarn_path" -C "$dir" --strip 1 --warning=no-unknown-keyword
  else
    tar xzf "$yarn_path" -C "$dir" --strip 1
  fi
  chmod +x $dir/bin/*
  echo "Installed yarn $(yarn --version)"
}

install_nodejs() {
  local version=${1:-8.x}
  local dir="$2"
  local number
  local url
  local nodejs_path="/tmp/node.tar.gz"

  echo "Resolving node version $version..."
  if ! read number url < <(curl --silent --get --retry 5 --retry-max-time 15 --data-urlencode "range=$version" "https://nodebin.herokai.com/v1/node/$platform/latest.txt"); then
    fail_bin_install node $version;
  fi

  local cache="$CACHE_DIR/node/node-$(echo -n "$url" | sha256sum | awk '{print $1}').tar.gz"
  if [ -f "$cache" ]; then
    mv "$cache" "$nodejs_path"
    echo "$nodejs_path $cache" >> "$BINCACHE_FILE"
  else
    rm -f "$CACHE_DIR/node/node-*.tar.gz"
    echo "Downloading and installing node $number..."
    local code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 -o "$nodejs_path" --write-out "%{http_code}")
    if [ "$code" != "200" ]; then
      echo "Unable to download node: $code" && false
    fi
    echo "$nodejs_path $cache" >> "$BINCACHE_FILE"
  fi
  tar xzf "$nodejs_path" -C /tmp
  rm -rf $dir/*
  mv /tmp/node-v$number-$os-$cpu/* $dir
  chmod +x $dir/bin/*
}

install_iojs() {
  local version="$1"
  local dir="$2"

  echo "Resolving iojs version ${version:-(latest stable)}..."
  if ! read number url < <(curl --silent --get --retry 5 --retry-max-time 15 --data-urlencode "range=$version" "https://nodebin.herokai.com/v1/iojs/$platform/latest.txt"); then
    fail_bin_install iojs $version;
  fi

  echo "Downloading and installing iojs $number..."
  local code=$(curl "$url" --silent --fail --retry 5 --retry-max-time 15 -o /tmp/iojs.tar.gz --write-out "%{http_code}")
  if [ "$code" != "200" ]; then
    echo "Unable to download iojs: $code" && false
  fi
  tar xzf /tmp/iojs.tar.gz -C /tmp
  mv /tmp/iojs-v$number-$os-$cpu/* $dir
  chmod +x $dir/bin/*
}

install_npm() {
  local version="$1"
  local dir="$2"
  local npm_lock="$3"
  local npm_version="$(npm --version)"

  # If the user has not specified a version of npm, but has an npm lockfile
  # upgrade them to npm 5.x if a suitable version was not installed with Node
  if $npm_lock && [ "$version" == "" ] && [ "${npm_version:0:1}" -lt "5" ]; then
    echo "Detected package-lock.json: defaulting npm to version 5.x.x"
    version="5.x.x"
  fi

  if [ "$version" == "" ]; then
    echo "Using default npm version: `npm --version`"
  elif [[ `npm --version` == "$version" ]]; then
    echo "npm `npm --version` already installed with node"
  else
    echo "Bootstrapping npm $version (replacing `npm --version`)..."
    if ! npm install --unsafe-perm --quiet -g "npm@$version" 2>@1>/dev/null; then
      echo "Unable to install npm $version; does it exist?" && false
    fi
    echo "npm `npm --version` installed"
  fi
}
