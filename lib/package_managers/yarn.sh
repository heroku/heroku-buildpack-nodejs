#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. The
# caller's flags are read from `$-` (the current shell); a `$(set +o)` capture runs in a
# command-substitution subshell where bash always forces errexit off, so it would later
# restore errexit as disabled even when the caller had it on. pipefail has no `$-` letter, so
# it is captured separately (it is reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__yarn_saved_flags="$-"
__yarn_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

function package_managers::yarn::install_binary() {
	local dir="${1}"
	local version=${2:-1.22.x}
	local package_name url installed_version

	# npm 12 removed the --unsafe-perm flag and rejects it with EUNKNOWNCONFIG, so only pass it
	# to the currently-active npm when that npm still accepts it.
	local unsafe_perm=()
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside; a non-match just omits the flag
	if package_managers::npm::supports_unsafe_perm; then
		unsafe_perm=(--unsafe-perm)
	fi

	if [[ -n "${YARN_BINARY_URL}" ]]; then
		url="${YARN_BINARY_URL}"
		echo "Downloading and installing yarn from ${url}"
	else
		echo "Downloading and installing yarn (${version})"
		# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
		if ! package_name=$(package_managers::yarn::_determine_package_name "${version}"); then
			build_data::set_string "failure" "yarn-resolve-failed"
			output::error <<-EOF
				Unable to resolve yarn version '${version}' via npm info
			EOF
			false
		fi
		if ! utils::command::suppress_output npm install "${unsafe_perm[@]}" --quiet --no-audit --no-progress -g "${package_name}@${version}"; then
			build_data::set_string "failure" "yarn-install-failed"
			output::error <<-EOF
				Unable to install yarn ${version}.
				Does yarn ${version} exist? (https://help.heroku.com/8MEL050H)
				Is ${version} valid semver? (https://help.heroku.com/0ZIOF3ST)
				Is yarn ${version} compatible with this Node.js version?
			EOF
			false
		fi
	fi
	# Verify yarn works before capturing and ensure its stderr is inspectable later
	utils::command::suppress_output yarn --version
	installed_version="$(yarn --version)"
	# shellcheck disable=SC2154 # YARN_2 is a global set by the caller (bin/compile)
	if ${YARN_2}; then
		echo "Using yarn ${installed_version}"
	else
		echo "Installed yarn ${installed_version}"
	fi
}

# Yarn 2+ (aka: "berry") is hosted under a different npm package so we need to do some
# extra checking to determine the correct package name.
function package_managers::yarn::_determine_package_name() {
	local version="${1}"
	local NPM_INFO_OUTPUT exit_code
	NPM_INFO_OUTPUT=$(mktemp)

	# shellcheck disable=SC2064 # expand NPM_INFO_OUTPUT now so the RETURN trap removes this exact temp file
	trap "rm -rf '${NPM_INFO_OUTPUT}' >/dev/null" RETURN

	npm info "yarn@${version}" version >"${NPM_INFO_OUTPUT}" 2>&1
	exit_code=$?

	if [[ ${exit_code} -eq 0 ]]; then
		# There are a couple of 2.x versions in the yarn package list, but that should be okay
		# since we're using npm to install the binaries. The previous inventory resolver never
		# handled this case well.
		echo "yarn"
		return 0
	fi

	# If nothing is returned for the yarn package list for the given version, it must be @yarnpkg/cli-dist
	if grep -q "E404" "${NPM_INFO_OUTPUT}"; then
		echo "@yarnpkg/cli-dist"
		return 0
	fi

	# Handle unexpected output on stderr so it's not captured by command substitution
	cat "${NPM_INFO_OUTPUT}" >&2
	return "${exit_code}"
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__yarn_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__yarn_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__yarn_saved_pipefail}"
unset __yarn_saved_flags __yarn_saved_pipefail
