#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. The
# caller's flags are read from `$-` (the current shell); a `$(set +o)` capture runs in a
# command-substitution subshell where bash always forces errexit off, so it would later
# restore errexit as disabled even when the caller had it on. pipefail has no `$-` letter, so
# it is captured separately (it is reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__npm_saved_flags="$-"
__npm_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

function npm_version_major() {
	npm --version | cut -d "." -f 1
}

# Pure classifier for npm dependency-install failures.
#
# Input: path to a log file containing the captured output of the failed npm command.
# Output: a classification JSON object (see failure::message) on stdout if a known failure
# mode is recognised, or nothing at all if unrecognised. Has no side effects: it does not
# write build data, print to the build log, or exit.
function npm::handle_npm_install_failure() {
	local log_file="${1}"

	# npm EBADPLATFORM code — stable npm v3–v11 (lib/utils/error-message.js).
	if grep -qiE 'npm (ERR!|error) code EBADPLATFORM' "${log_file}"; then
		failure::message --reason "npm-ebadplatform" --classification "user" <<-EOF
			Error: Unable to install dependencies using npm.

			One of your dependencies (or its native binary) does not support
			this stack's CPU architecture or operating system. Check the log
			output above for the offending package.
		EOF
		return 0
	fi

	# npm EINVALIDPACKAGENAME code — stable npm v3–v11. The code is set in the npm-package-arg
	# dependency and printed via npm's generic `npm (ERR!|error) code <CODE>` summary line.
	if grep -qiE 'npm (ERR!|error) code EINVALIDPACKAGENAME' "${log_file}"; then
		failure::message --reason "npm-package-name-typo" --classification "user" <<-EOF
			Error: Unable to install dependencies using npm.

			A package name in your package.json is invalid. Check the log output
			above for the offending entry and correct the spelling.
		EOF
		return 0
	fi

	# npm E404 code — stable npm v3–v11 (lib/utils/error-message.js). The second pattern matches
	# Yarn's 404 wording, carried over from the legacy log_other_failures matcher.
	if grep -qiE -e 'npm (ERR!|error) code E404' \
		-e "error An unexpected error occurred: .* Request failed \"404 Not Found\"" "${log_file}"; then

		# The flatmap-stream malware case is a more specific instance of a 404.
		if grep -qi "flatmap-stream" "${log_file}"; then
			failure::message --reason "flatmap-stream-404" --classification "user" <<-EOF
				Error: The flatmap-stream module has been removed from the npm registry.

				On November 26th (2018), npm was notified of a malicious package that had made
				its way into event-stream, a popular npm package. npm responded by removing
				flatmap-stream and event-stream@3.3.6 from the registry.

				Docs: https://help.heroku.com/4OM7X18J
			EOF
			return 0
		fi

		failure::message --reason "module-404" --classification "user" <<-EOF
			Error: Unable to install dependencies using npm.

			A package could not be found in the npm registry (404). Check the log
			output above for the package name and verify it exists and is spelled
			correctly.
		EOF
		return 0
	fi

	# TODO: classify additional npm codes present in error-message.js but not yet handled here,
	# e.g. ETARGET (no matching version), ERESOLVE (dependency conflict), ENOSPC (disk full).
	# Add each as its own matcher above, verified against npm source per the version-spread loop.

	# No known failure mode recognised — emit nothing so the caller can fall through.
	return 0
}

# Installs app dependencies with npm (fresh install path; the prebuild/rebuild path is
# still handled by lib/dependencies.sh until it is migrated).
#
# On failure, the captured output is run through npm::handle_npm_install_failure and, if a
# known failure mode is recognised, failure::emit renders the message, records the
# classification, and exits. Otherwise a generic npm-install failure is emitted so the build
# never falls through silently.
function npm::install_dependencies() {
	local build_dir="${1}"
	local production="${NPM_CONFIG_PRODUCTION:-false}"

	if [[ ! -e "${build_dir}/package.json" ]]; then
		echo "Skipping (no package.json)"
		return 0
	fi

	cd "${build_dir}"

	local npm_command=(npm)
	if [[ "${USE_NPM_INSTALL:-true}" == "false" ]]; then
		build_data::set_raw "use_npm_ci" "true"
		echo "Installing node modules"
		npm_command+=(ci)
	else
		build_data::set_raw "use_npm_ci" "false"
		if [[ -e "${build_dir}/package-lock.json" ]]; then
			echo "Installing node modules (package.json + package-lock)"
		elif [[ -e "${build_dir}/npm-shrinkwrap.json" ]]; then
			echo "Installing node modules (package.json + shrinkwrap)"
		else
			echo "Installing node modules (package.json)"
		fi
		npm_command+=(install)
	fi
	npm_command+=(--production="${production}" --unsafe-perm --userconfig "${build_dir}/.npmrc")

	local log_file
	log_file=$(mktemp)

	local start
	start=$(build_data::current_unix_realtime)

	# Run inside `if !` so errexit is suppressed: the legacy ERR trap won't fire and we
	# classify the failure ourselves at the call site.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { "${npm_command[@]}" 2>&1 | tee "${log_file}"; }; then
		build_data::set_duration "install_dependencies_time" "${start}"

		local classification
		classification=$(npm::handle_npm_install_failure "${log_file}")
		if [[ -n "${classification}" ]]; then
			failure::emit "${classification}"
		fi

		# No known failure mode recognised — emit a generic npm-install failure.
		local generic
		generic=$(
			failure::message --reason "install-dependencies::npm" <<-EOF
				Error: Unable to install dependencies using npm.

				See the log output above for more information.
			EOF
		)
		failure::emit "${generic}"
	fi

	build_data::set_duration "install_dependencies_time" "${start}"
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__npm_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__npm_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__npm_saved_pipefail}"
unset __npm_saved_flags __npm_saved_pipefail
