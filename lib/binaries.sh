#!/usr/bin/env bash

# Compiled from: https://github.com/heroku/buildpacks-nodejs/tree/main/crates/nodejs-data

install_yarn() {
  local dir="$1"
  local version=${2:-1.22.x}
  local number url code resolve_result

  if [[ -n "$YARN_BINARY_URL" ]]; then
    url="$YARN_BINARY_URL"
    echo "Downloading and installing yarn from $url"
  else
    echo "Downloading and installing yarn ($version)"
    if ! package_name=$(determine_yarn_package_name "$version"); then
      build_data::set_string "failure" "yarn-resolve-failed"
      output::error <<-EOF
				Unable to resolve yarn version '$version' via npm info
			EOF
      false
    fi
    if ! suppress_output npm install --unsafe-perm --quiet --no-audit --no-progress -g "$package_name@$version"; then
      build_data::set_string "failure" "yarn-install-failed"
      output::error <<-EOF
				Unable to install yarn $version.
				Does yarn $version exist? (https://help.heroku.com/8MEL050H)
				Is $version valid semver? (https://help.heroku.com/0ZIOF3ST)
				Is yarn $version compatible with this Node.js version?
			EOF
      false
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
  if $npm_lock && [ "$version" == "" ] && [ "$(package_managers::npm::version_major)" -lt "5" ]; then
    echo "Detected package-lock.json: defaulting npm to version 5.x.x"
    version="5.x.x"
  fi

  if [ "$version" == "" ]; then
    echo "Using default npm version: $npm_version"
  elif [[ "$npm_version" == "$version" ]]; then
    echo "npm $npm_version already installed with node"
  else
    echo "Bootstrapping npm $version (replacing $npm_version)..."
    local install_npm_start
    install_npm_start=$(build_data::current_unix_realtime)
    install_npm_binary "${version}"
    build_data::set_duration "install_npm_binary_time" "$install_npm_start"
    # Verify npm works before capturing and ensure its stderr is inspectable later
    suppress_output npm --version
    echo "npm $(npm --version) installed"
  fi
}

install_npm_binary() {
  local version="$1"

  # XXX: Workaround for https://github.com/heroku/heroku-buildpack-nodejs/issues/1590
  # Node 22.22.2 fails to install npm >= 11.11.0 with a MODULE_NOT_FOUND error for `promise-retry`.
  # Installing an intermediate npm version (~11.10.0) first avoids the issue.
  if [[ "$(node --version)" == "v22.22.2" ]]; then
    local resolved_version
    resolved_version=$(npm info "npm@${version}" version --json 2>/dev/null | jq -r 'if type == "array" then .[-1] else . end' 2>/dev/null) || true
    local major minor
    major=$(echo "$resolved_version" | cut -d. -f1)
    minor=$(echo "$resolved_version" | cut -d. -f2)
    if [[ -z "$resolved_version" ]] || [[ "$resolved_version" == "null" ]] || [[ -z "$major" ]] || [[ -z "$minor" ]]; then
      build_data::set_string "failure" "npm-resolve-failed"
      output::error <<-EOF
				Failed to resolve npm version from range '$version'.
				Unable to perform Node.js 22.22.2 regression workaround (https://github.com/npm/cli/issues/9151).
			EOF
      false
      return
    fi
    if [[ "$major" == "11" ]] && [[ "$minor" -ge 11 ]]; then
      echo "Installing npm@~11.10.0 to workaround Node.js 22.22.2 regression (https://github.com/npm/cli/issues/9151)"
      if ! suppress_output npm install --unsafe-perm --quiet --no-audit --no-progress -g "npm@~11.10.0"; then
        build_data::set_string "failure" "npm-node-22.22.2-workaround-failed"
        output::error <<-EOF
					Unable to install intermediate npm ~11.10.0 for Node.js 22.22.2 workaround.
					Consider pinning npm to an exact version that works with Node.js 22.22.2.
				EOF
        false
        return
      fi
    fi
  fi

  if ! suppress_output npm install --unsafe-perm --quiet --no-audit --no-progress -g "npm@$version"; then
    build_data::set_string "failure" "npm-install-failed"
    output::error <<-EOF
			Unable to install npm $version.
			Does npm $version exist?
			Is npm $version compatible with this Node.js version?
		EOF
    false
  fi
}

install_pnpm() {
  local version="$1"
  echo "Downloading and installing pnpm ($version)"
  if ! suppress_output npm install --unsafe-perm --quiet --no-audit --no-progress -g "pnpm@$version"; then
    build_data::set_string "failure" "pnpm-install-failed"
    output::error <<-EOF
			Unable to install pnpm $version.
			Does pnpm $version exist? (https://help.heroku.com/8MEL050H)
			Is $version valid semver? (https://help.heroku.com/0ZIOF3ST)
			Is pnpm $version compatible with this Node.js version?
		EOF
    false
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
  local version="$1"
  local NPM_INFO_OUTPUT exit_code
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
  if grep -q "E404" "$NPM_INFO_OUTPUT"; then
    echo "@yarnpkg/cli-dist"
    return 0
  fi

  # Handle unexpected output on stderr so it's not captured by command substitution
  cat "$NPM_INFO_OUTPUT" >&2
  return "$exit_code"
}
