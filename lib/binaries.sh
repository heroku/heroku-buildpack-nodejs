#!/usr/bin/env bash

# Compiled from: https://github.com/heroku/buildpacks-nodejs/blob/main/common/nodejs-utils/src/bin/resolve_version.rs
RESOLVE="$BP_DIR/lib/vendor/resolve-version-$(get_os)"

resolve_nodejs() {
  local node_version="$1"
  local lts_major_version="$2"
  local output

  if output=$($RESOLVE "$BP_DIR/inventory/node.toml" "$node_version" "$lts_major_version"); then
    if [[ $output = "No result" ]]; then
      return 1
    else
      echo "$output"
      return 0
    fi
  fi
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
    echo "Downloading and installing yarn ($version)"
    package_name=$(determine_yarn_package_name "$version")
    if ! suppress_output npm install --unsafe-perm --quiet --no-audit --no-progress -g "$package_name@$version"; then
      echo "Unable to install yarn $version. " \
        "Does yarn $version exist? (https://help.heroku.com/8MEL050H) " \
        "Is $version valid semver? (https://help.heroku.com/0ZIOF3ST) " \
        "Is yarn $version compatible with this Node.js version?" \ && false
    fi
  fi
  # Verify yarn works before capturing and ensure its stderr is inspectable later
  suppress_output yarn --version
  if $YARN_2; then
    echo "Using yarn $(yarn --version)"
  else
    echo "Installed yarn $(yarn --version)"
  fi
}

install_nodejs() {
  local requested_version="${1:-}"
  local dir="${2:?}"
  local code resolve_result
  local lts_major_version="24"

  if [[ -z "$requested_version" ]]; then
      requested_version="$lts_major_version.x"
  fi

  if [[ -n "$NODE_BINARY_URL" ]]; then
    download_url="$NODE_BINARY_URL"
    echo "Downloading and installing node from $download_url"
  else
    echo "Resolving node version $requested_version..."
    resolve_result=$(resolve_nodejs "$requested_version" "$lts_major_version" || echo "failed")

    if [[ "$resolve_result" == "failed" ]]; then
      fail_bin_install "$requested_version" "$lts_major_version"
    fi

    version=$(echo "$resolve_result" | jq -r .version)
    download_url=$(echo "$resolve_result" | jq -r .url)
    checksum_type=$(echo "$resolve_result" | jq -r .checksum_type)
    checksum_value=$(echo "$resolve_result" | jq -r .checksum_value)
    uses_wide_range=$(echo "$resolve_result" | jq .uses_wide_range)
    lts_upper_bound_enforced=$(echo "$resolve_result" | jq .lts_upper_bound_enforced)

    if [[ "$uses_wide_range" == "true" ]]; then
      echo
      echo "! The requested Node.js version is using a wide range ($requested_version) that can resolve to a Node.js major version"
      echo "  higher than you intended. Limiting the requested range to a major LTS range like \`$lts_major_version.x\` is recommended."
      echo "  https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
    fi

    if [[ "$lts_upper_bound_enforced" == "true" ]]; then
      echo
      echo "! The resolved Node.js version has been limited to the Active LTS ($version) for the requested range of \`$requested_version\`."
      echo "  To opt-out of this behavior, set the following config var: \`NODEJS_ALLOW_WIDE_RANGE=true\`"
      echo "  https://devcenter.heroku.com/articles/nodejs-support#supported-node-js-versions"
    fi

    # if either warning message was displayed, ensure we add a newline before continuing with regular output
    if [[ "$uses_wide_range" == "true" ]] || [[ "$lts_upper_bound_enforced" == "true" ]]; then
      echo
    fi

    echo "Downloading and installing node $version..."

    if [[ "$version" == "22.5.0" ]]; then
      warn_about_node_version_22_5_0
    fi
  fi

  output_file="/tmp/node.tar.gz"
  code=$(curl "$download_url" -L --silent --fail --retry 5 --retry-max-time 15 --retry-connrefused --connect-timeout 5 -o "$output_file" --write-out "%{http_code}")

  if [ "$code" != "200" ]; then
    echo "Unable to download node: $code" && false
  fi

  if [[ -z "$NODE_BINARY_URL" ]]; then
    case "$checksum_type" in
      "sha256")
        echo "Validating checksum"
        if ! echo "$checksum_value $output_file" | sha256sum --check --status; then
          echo "Checksum validation failed for Node.js $version - $checksum_type:$checksum_value" && false
        fi
        ;;
      *)
        echo "Unsupported checksum for Node.js $version - $checksum_type:$checksum_value" && false
        ;;
    esac
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
  # Verify npm works before capturing and ensure its stderr is inspectable later
  suppress_output npm --version
  npm_version="$(npm --version)"

  # If the user has not specified a version of npm, but has an npm lockfile
  # upgrade them to npm 5.x if a suitable version was not installed with Node
  if $npm_lock && [ "$version" == "" ] && [ "$(npm_version_major)" -lt "5" ]; then
    echo "Detected package-lock.json: defaulting npm to version 5.x.x"
    version="5.x.x"
  fi

  if [ "$version" == "" ]; then
    echo "Using default npm version: $npm_version"
  elif [[ "$npm_version" == "$version" ]]; then
    echo "npm $npm_version already installed with node"
  else
    echo "Bootstrapping npm $version (replacing $npm_version)..."
    monitor "install_npm_binary" install_npm_binary "${version}"
    # Verify npm works before capturing and ensure its stderr is inspectable later
    suppress_output npm --version
    echo "npm $(npm --version) installed"
  fi
}

install_npm_binary() {
  local version="$1"
  if ! npm install --unsafe-perm --quiet --no-audit --no-progress -g "npm@$version" >/dev/null; then
    echo "Unable to install npm $version. " \
      "Does npm $version exist? " \
      "Is npm $version compatible with this Node.js version?" && false
  fi
}

install_pnpm() {
  local version="$1"
  echo "Downloading and installing pnpm ($version)"
  if ! suppress_output npm install --unsafe-perm --quiet --no-audit --no-progress -g "pnpm@$version"; then
    echo "Unable to install pnpm $version. " \
      "Does pnpm $version exist? (https://help.heroku.com/8MEL050H) " \
      "Is $version valid semver? (https://help.heroku.com/0ZIOF3ST) " \
      "Is yarn $version compatible with this Node.js version?" \ && false
  fi
  # Verify pnpm works before capturing and ensure its stderr is inspectable later
  suppress_output pnpm --version
  echo "Using pnpm $(pnpm --version)"
}

suppress_output() {
  local TMP_COMMAND_OUTPUT
  TMP_COMMAND_OUTPUT=$(mktemp)
  trap "rm -rf '$TMP_COMMAND_OUTPUT' >/dev/null" RETURN

  "$@" >"$TMP_COMMAND_OUTPUT" 2>&1 || {
    local exit_code="$?"
    cat "$TMP_COMMAND_OUTPUT"
    return "$exit_code"
  }
  return 0
}

# Yarn 2+ (aka: "berry") is hosted under a different npm package so we need to do some
# extra checking to determine the correct package name.
determine_yarn_package_name() {
  local NPM_INFO_OUTPUT
  NPM_INFO_OUTPUT=$(mktemp)

  trap "rm -rf '$NPM_INFO_OUTPUT' >/dev/null" RETURN

  npm info "yarn@$version" version >"$NPM_INFO_OUTPUT" 2>&1
  exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    # There are a couple of 2.x versions in the yarn package list, but that should be okay
    # since we're using npm to install the binaries. The previous inventory resolver never
    # handled this case well.
    echo "yarn"
    return 0
  fi

  # If nothing is returned for the yarn package list for the given version, it must be @yarnpkg/cli-dist
  if cat "$NPM_INFO_OUTPUT" | grep -q "E404"; then
    echo "@yarnpkg/cli-dist"
    return 0
  fi

  # Handle unexpected output
  echo "Unable to resolve yarn version '$version' via npm info"
  cat "$NPM_INFO_OUTPUT"
  return "$exit_code"
}
