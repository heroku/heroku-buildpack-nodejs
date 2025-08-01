#!/usr/bin/env bash

# Compiled from: https://github.com/heroku/buildpacks-nodejs/blob/main/common/nodejs-utils/src/bin/resolve_version.rs
RESOLVE="$BP_DIR/lib/vendor/resolve-version-$(get_os)"

resolve() {
  local binary="$1"
  local versionRequirement="$2"
  local output

  if output=$($RESOLVE "$BP_DIR/inventory/$binary.toml" "$versionRequirement"); then
    meta_set "resolve-v2-$binary" "$output"
    meta_set "resolve-v2-error" "$STD_ERR"
    if [[ $output = "No result" ]]; then
      return 1
    else
      echo $output
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
  local version="${1:-}"
  local dir="${2:?}"
  local code resolve_result

  if [[ -z "$version" ]]; then
      version="22.x"
  fi

  if [[ -n "$NODE_BINARY_URL" ]]; then
    url="$NODE_BINARY_URL"
    echo "Downloading and installing node from $url"
  else
    echo "Resolving node version $version..."
    resolve_result=$(resolve node "$version" || echo "failed")

    read -r number url checksum_name digest < <(echo "$resolve_result")

    if [[ "$resolve_result" == "failed" ]]; then
      fail_bin_install node "$version"
    fi

    echo "Downloading and installing node $number..."

    if [[ "$number" == "22.5.0" ]]; then
      warn_about_node_version_22_5_0
    fi
  fi

  output_file="/tmp/node.tar.gz"
  code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 --retry-connrefused --connect-timeout 5 -o "$output_file" --write-out "%{http_code}")

  if [ "$code" != "200" ]; then
    echo "Unable to download node: $code" && false
  fi

  case "$checksum_name" in
    "sha256")
      if ! echo "$digest $output_file" | sha256sum --check --status; then
        echo "Checksum validation failed for Node.js $number - $checksum_name:$digest" && false
      fi
      ;;
    *)
      echo "Unsupported checksum for Node.js $number - $checksum_name:$digest" && false
      ;;
  esac

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
    if ! npm install --unsafe-perm --quiet --no-audit --no-progress -g "npm@$version" >/dev/null; then
      echo "Unable to install npm $version. " \
        "Does npm $version exist? " \
        "Is npm $version compatible with this Node.js version?" && false
    fi
    # Verify npm works before capturing and ensure its stderr is inspectable later
    suppress_output npm --version
    echo "npm $(npm --version) installed"
  fi
}

install_yarn_using_corepack_package_manager() {
  local package_manager="$1"
  local node_version="$2"
  install_corepack_package_manager "$package_manager" "$node_version"
  suppress_output yarn --version
  echo "Using yarn $(yarn --version)"
}

install_pnpm_using_corepack_package_manager() {
  local package_manager="$1"
  local node_version="$2"
  local pnpm_cache="$3"
  install_corepack_package_manager "$package_manager" "$node_version"
  suppress_output pnpm --version
  echo "Using pnpm $(pnpm --version)"
  pnpm config set store-dir "$pnpm_cache" 2>&1
}

install_corepack_package_manager() {
  local node_major_version
  local node_minor_version

  local package_manager="$1"
  local node_version="$2"

  node_major_version=$(echo "$node_version" | cut -d "." -f 1 | sed 's/^v//')
  node_minor_version=$(echo "$node_version" | cut -d "." -f 2)

  # Corepack is available in: v16.9.0, v14.19.0
  if (( node_major_version >= 17 )) || (( node_major_version == 14 && node_minor_version >= 19 )) || (( node_major_version >= 16 && node_minor_version >= 9 )); then
    suppress_output corepack --version
    corepack_version=$(corepack --version)
    corepack enable 2>&1

    # The Corepack CLI interface was refactored in 0.20, before that the `install` command was called `prepare` and it
    # doesn't support the --global argument - https://github.com/nodejs/corepack/blob/main/CHANGELOG.md#0200-2023-08-29
    corepack_major_version=$(echo "$corepack_version" | cut -d "." -f 1)
    corepack_minor_version=$(echo "$corepack_version" | cut -d "." -f 2)
    if (( corepack_major_version == 0 )) && (( corepack_minor_version < 20 )); then
      corepack_install_command="prepare"
      corepack_install_args=()
    else
      corepack_install_command="install"
      corepack_install_args=("--global")
    fi

    # This is a workaround for Node versions that bundle a version of Corepack that is affected by
    # recent changes to npm's public signing keys:
    # * Corepack versions before 0.27.0 don't verify the integrity signatures from npm
    # * Corepack versions after 0.31.0 have the correct npm keys
    if (( corepack_major_version == 0 )); then
      if (( corepack_minor_version >= 27 )) || (( corepack_minor_version < 31 )); then
        export COREPACK_INTEGRITY_KEYS='{
  "npm": [
    {
      "expires": "2025-01-29T00:00:00.000Z",
      "keyid": "SHA256:jl3bwswu80PjjokCgh0o2w5c2U4LhQAE57gj9cz1kzA",
      "keytype": "ecdsa-sha2-nistp256",
      "scheme": "ecdsa-sha2-nistp256",
      "key": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE1Olb3zMAFFxXKHiIkQO5cJ3Yhl5i6UPp+IhuteBJbuHcA5UogKo0EWtlWwW6KSaKoTNEYL7JlCQiVnkhBktUgg=="
    },
    {
      "expires": null,
      "keyid": "SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U",
      "keytype": "ecdsa-sha2-nistp256",
      "scheme": "ecdsa-sha2-nistp256",
      "key": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEY6Ya7W++7aUPzvMTrezH6Ycx3c+HOKYCcNGybJZSCJq/fd7Qa8uuAKtdIkUQtQiEKERhAmE5lMMJhP8OkDOa2g=="
    }
  ]
}'
      fi
    fi

    echo "Installing $(echo "$package_manager" | cut -d "+" -f 1) via corepack ${corepack_version}"
    install_output=$(mktemp)
    if ! corepack "${corepack_install_args[@]}" "$corepack_install_command" "$package_manager" > "$install_output" 2>&1; then
      # always show the output on error
      cat "$install_output"
      if grep --ignore-case "mismatch hashes" "$install_output"; then
        fail_corepack_install_invalid_hash "$package_manager"
      else
        fail_corepack_install_invalid_version "$package_manager"
      fi
    fi
  else
    fail_corepack_not_available "$package_manager" "$node_version"
  fi

  # XXX: Because the corepack binary scripts are located in a sub-directory of the application directory,
  #      the `type` field from application's package.json can accidentally force an incorrect module
  #      system from being detected which influences how these binaries scripts are then loaded. Adding the
  #      following dummy package.json with no `type` set will short-circuit that from happening when Node.js
  #      runs it's rules for determining the module system.
  echo '{ "name": "halt-node-module-system-determination-rules", "version": "0.0.0" }' > "$COREPACK_HOME/package.json"
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
