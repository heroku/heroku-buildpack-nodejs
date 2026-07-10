#!/usr/bin/env bash

# Compiled from: https://github.com/heroku/buildpacks-nodejs/tree/main/crates/nodejs-data

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
