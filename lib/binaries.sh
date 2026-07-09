#!/usr/bin/env bash

# Compiled from: https://github.com/heroku/buildpacks-nodejs/tree/main/crates/nodejs-data

install_yarn() {
  local dir="$1"
  local version=${2:-1.22.x}
  local number url code resolve_result

  # npm 12 removed the --unsafe-perm flag and rejects it with EUNKNOWNCONFIG, so only pass it
  # to the currently-active npm when that npm still accepts it.
  local unsafe_perm=()
  if package_managers::npm::supports_unsafe_perm; then
    unsafe_perm=(--unsafe-perm)
  fi

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
    if ! suppress_output npm install "${unsafe_perm[@]}" --quiet --no-audit --no-progress -g "$package_name@$version"; then
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

install_pnpm() {
  local version="$1"
  echo "Downloading and installing pnpm ($version)"
  # npm 12 removed the --unsafe-perm flag and rejects it with EUNKNOWNCONFIG, so only pass it
  # to the currently-active npm when that npm still accepts it.
  local unsafe_perm=()
  if package_managers::npm::supports_unsafe_perm; then
    unsafe_perm=(--unsafe-perm)
  fi
  if ! suppress_output npm install "${unsafe_perm[@]}" --quiet --no-audit --no-progress -g "pnpm@$version"; then
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
