install_yarn() {
  local dir="$1"
  local version="$2"
  local number
  local url

  echo "Resolving yarn version ${version:-(latest)}..."
  if ! read number url < <(curl --silent --get --retry 5 --retry-max-time 15 --data-urlencode "range=$version" "https://nodebin.herokai.com/v1/yarn/$platform/latest.txt"); then
    echo "Unable to resolve; does that version exist?" && false
  fi

  echo "Downloading and installing yarn $number..."
  local code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 -o /tmp/yarn.tar.gz --write-out "%{http_code}")
  if [ "$code" != "200" ]; then
    echo "Unable to download yarn: $code" && false
  fi
  rm -rf $dir
  mkdir -p "$dir"
  # https://github.com/yarnpkg/yarn/issues/770
  if tar --version | grep -q 'gnu'; then
    tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1 --warning=no-unknown-keyword
  else
    tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1
  fi
  chmod +x $dir/bin/*
  echo "Installed yarn $(yarn --version)"
}

install_nodejs() {
  local version=${1:-6.x}
  local dir="$2"
  local number
  local url

  echo "Resolving node version $version..."
  if ! read number url < <(curl --silent --get --retry 5 --retry-max-time 15 --data-urlencode "range=$version" "https://nodebin.herokai.com/v1/node/$platform/latest.txt"); then
    echo "Unable to resolve; does that version exist?" && false
  fi

  echo "Downloading and installing node $number..."
  local code=$(curl "$url" --silent --fail --retry 5 --retry-max-time 15 -o /tmp/node.tar.gz --write-out "%{http_code}")
  if [ "$code" != "200" ]; then
    echo "Unable to download node: $code" && false
  fi
  tar xzf /tmp/node.tar.gz -C /tmp
  rm -rf $dir/*
  mv /tmp/node-v$number-$os-$cpu/* $dir
  chmod +x $dir/bin/*
}

install_iojs() {
  local version="$1"
  local dir="$2"
  local number
  local url

  echo "Resolving iojs version ${version:-(latest)}..."
  if ! read number url < <(curl --silent --get --retry 5 --retry-max-time 15 --data-urlencode "range=$version" "https://nodebin.herokai.com/v1/iojs/$platform/latest.txt"); then
    echo "Unable to resolve; does that version exist?" && false
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

  if [ "$version" == "" ]; then
    echo "Using default npm version: `npm --version`"
  else
    if [[ `npm --version` == "$version" ]]; then
      echo "npm `npm --version` already installed with node"
    else
      echo "Bootstrapping npm $version (replacing `npm --version`)..."
      if ! npm install --unsafe-perm --quiet -g "npm@$version" 2>@1 >/dev/null; then
        echo "Unable to install npm $version; does it exist?" && false
      fi
      echo "npm `npm --version` installed"
    fi
  fi
}
