#!/usr/bin/env bash

RESOLVE="$BP_DIR/lib/vendor/resolve-version-$(get_os)"
RESOLVE_V2="$BP_DIR/lib/vendor/resolve"

resolve() {
  local binary="$1"
  local versionRequirement="$2"
  local n=0
  local output v2_output resolve_is_equal

  # retry this up to 5 times in case of spurious failed API requests
  until [ $n -ge 5 ]
  do
    # if a user sets the HTTP_PROXY ENV var, it could prevent this from making the S3 requests
    # it needs here. We can ignore this proxy for aws urls with NO_PROXY. Some environments
    # require a proxy for all HTTP requests, so the NO_PROXY ENV var should be set outside the
    # script by the user
    # see testAvoidHttpProxyVersionResolutionIssue test and README
    if output=$($RESOLVE "$binary" "$versionRequirement"); then
      v2_output=$($RESOLVE_V2 "$BP_DIR/inventory/$binary.toml" "$versionRequirement")
      resolve_is_equal=$(if [[ "$output" == "$v2_output" ]]; then echo true; else echo false; fi)

      meta_set "resolve-v1-$binary" "$output"
      meta_set "resolve-v2-$binary" "$v2_output"
      meta_set "resolve-is-equal-$binary" "$resolve_is_equal"
      meta_set "resolve-v2-error" "$STD_ERR"

      echo "$output"
      return 0
    # don't retry if we get a negative result
    elif [[ $output = "No result" ]]; then
      return 1
    elif [[ $output == "Could not parse"* ]] || [[ $output == "Could not get"* ]]; then
      return 1
    else
      n=$((n+1))
      # break for a second with a linear backoff
      sleep $((n+1))
    fi
  done

  return 1
}

install_yarn() {
  local dir="$1"
  local version=${2:-1.22.x}
  local number url code resolve_result

  if [[ -n "$YARN_BINARY_URL" ]]; then
    url="$YARN_BINARY_URL"
    echo "Downloading and installing yarn from $url"
  else
    echo "Resolving yarn version $version..."
    resolve_result=$(resolve yarn "$version" || echo "failed")

    if [[ "$resolve_result" == "failed" ]]; then
      fail_bin_install yarn "$version"
    fi

    read -r number url < <(echo "$resolve_result")

    echo "Downloading and installing yarn ($number)"
  fi

  code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 -o /tmp/yarn.tar.gz --write-out "%{http_code}")

  if [ "$code" != "200" ]; then
    echo "Unable to download yarn: $code" && false
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  # https://github.com/yarnpkg/yarn/issues/770
  if tar --version | grep -q 'gnu'; then
    tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1 --warning=no-unknown-keyword
  else
    tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1
  fi
  chmod +x "$dir"/bin/*

  if $YARN_2; then
    echo "Using yarn $(yarn --version)"
  else
    echo "Installed yarn $(yarn --version)"
  fi
}

install_nodejs() {
  local version=${1:-16.x}
  local dir="${2:?}"
  local code resolve_result

  if [[ -n "$NODE_BINARY_URL" ]]; then
    url="$NODE_BINARY_URL"
    echo "Downloading and installing node from $url"
  else
    echo "Resolving node version $version..."
    resolve_result=$(resolve node "$version" || echo "failed")

    read -r number url < <(echo "$resolve_result")

    if [[ "$resolve_result" == "failed" ]]; then
      fail_bin_install node "$version"
    fi

    echo "Downloading and installing node $number..."
  fi

  code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 -o /tmp/node.tar.gz --write-out "%{http_code}")

  if [ "$code" != "200" ]; then
    echo "Unable to download node: $code" && false
  fi
  rm -rf "${dir:?}"/*
  tar xzf /tmp/node.tar.gz --strip-components 1 -C "$dir"
  chmod +x "$dir"/bin/*
}

install_npm() {
  local npm_version
  local version="$1"
  local dir="$2"
  local npm_lock="$3"
  npm_version="$(npm --version)"

  # If the user has not specified a version of npm, but has an npm lockfile
  # upgrade them to npm 5.x if a suitable version was not installed with Node
  if $npm_lock && [ "$version" == "" ] && [ "${npm_version:0:1}" -lt "5" ]; then
    echo "Detected package-lock.json: defaulting npm to version 5.x.x"
    version="5.x.x"
  fi

  if [ "$version" == "" ]; then
    echo "Using default npm version: $npm_version"
  elif [[ "$npm_version" == "$version" ]]; then
    echo "npm $npm_version already installed with node"
  else
    echo "Bootstrapping npm $version (replacing $npm_version)..."
    if ! npm install --unsafe-perm --quiet -g "npm@$version" 2>@1>/dev/null; then
      echo "Unable to install npm $version; does it exist?" && false
    fi
    echo "npm $version installed"
  fi
}
