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

# Installs app dependencies with npm (fresh install path; the prebuild/rebuild path is
# still handled by lib/dependencies.sh until it is migrated).
#
# On failure, the captured output is run through npm::_handle_npm_install_failure and, if a
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

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { "${npm_command[@]}" 2>&1 | tee "${log_file}"; }; then
		# Capture the full pipe status first (before any other command clobbers PIPESTATUS).
		# The pipeline is `npm 2>&1 | tee`, so [0] is npm's exit code and [1] is tee's.
		local pipe_status=("${PIPESTATUS[@]}")
		local npm_exit="${pipe_status[0]}"
		build_data::set_duration "install_dependencies_time" "${start}"

		local -A failure
		# shellcheck disable=SC2310 # the elif calls a function in a condition, so set -e is disabled inside
		if [[ "${npm_exit}" -eq 0 ]]; then
			# npm itself succeeded; the pipeline failed because `tee` (which captures the install
			# log) failed — e.g. the build ran out of disk space. That is a failure on the
			# buildpack's side, not a problem with the app's dependencies, so don't run it through
			# the npm classifier (it would match nothing and blame the user). `tee` returns a bare
			# non-zero on any write error without encoding the cause, so we record the raw pipe
			# status as detail for observability rather than guessing why it failed.
			failure["id"]="npm-install-pipefail"
			failure["classification"]="buildpack"
			failure["detail"]="PIPESTATUS=[${pipe_status[*]}]"
			failure["message"]=$(
				cat <<-EOF
					Error: Unable to capture the npm install log output.

					The dependency install ran, but writing its log to disk failed (for example,
					the build ran out of disk space). This is not a problem with your
					dependencies. Please try again.
				EOF
			)
			failure::emit failure
		elif npm::_handle_npm_install_failure "${log_file}" failure; then
			# The classifier fills `failure` by nameref and returns 0 on a match. It is invoked
			# directly in the `elif` condition (not wrapped in `$(...)`) so its writes survive — a
			# command substitution runs in a subshell where the nameref updates would be lost.
			failure::emit failure
		fi

		# No known failure mode recognised. Bubble up by returning npm's exit code: the pipeline
		# that runs this install (`build_dependencies | output "$LOG_FILE"`) then fails under
		# errexit/pipefail, the legacy ERR trap fires, and `log_other_failures` classifies the
		# failure from $LOG_FILE — covering the codes (ERESOLVE, ETARGET, ENOSPC, …) not yet
		# migrated here, instead of masking them with a generic message.
		return "${npm_exit}"
	fi

	build_data::set_duration "install_dependencies_time" "${start}"
}

function npm_version_major() {
	npm --version | cut -d "." -f 1
}

# Pure classifier for npm dependency-install failures.
#
# Input:
#   $1  path to a log file containing the captured output of the failed npm command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when a known failure mode is recognised; returns 1 and leaves
# the array untouched otherwise. Has no side effects: it does not write build data, print to
# the build log, or exit. Detail is set to the npm error code plus the first descriptive
# error line, giving observability a precise discriminator within each failure bucket.
function npm::_handle_npm_install_failure() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	# npm EBADPLATFORM code — stable npm v3–v11 (lib/utils/error-message.js).
	if grep -qiE 'npm (ERR!|error) code EBADPLATFORM($| )' "${log_file}"; then
		__failure["id"]="npm-ebadplatform"
		__failure["classification"]="user"
		__failure["detail"]="EBADPLATFORM: $(npm::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: Unable to install dependencies using npm.

				One of your dependencies (or its native binary) does not support
				this stack's CPU architecture or operating system. Check the log
				output above for the offending package.
			EOF
		)
		return 0
	fi

	# npm EINVALIDPACKAGENAME code — stable npm v3–v11. The code is set in the npm-package-arg
	# dependency and printed via npm's generic `npm (ERR!|error) code <CODE>` summary line.
	if grep -qiE 'npm (ERR!|error) code EINVALIDPACKAGENAME($| )' "${log_file}"; then
		__failure["id"]="npm-package-name-typo"
		__failure["classification"]="user"
		__failure["detail"]="EINVALIDPACKAGENAME: $(npm::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: Unable to install dependencies using npm.

				A package name in your package.json is invalid. Check the log output
				above for the offending entry and correct the spelling.
			EOF
		)
		return 0
	fi

	# npm E404 code — stable npm v3–v11 (lib/utils/error-message.js). The second pattern matches
	# Yarn's 404 wording, carried over from the legacy log_other_failures matcher.
	if grep -qiE -e 'npm (ERR!|error) code E404($| )' \
		-e "error An unexpected error occurred: .* Request failed \"404 Not Found\"" "${log_file}"; then

		# The flatmap-stream malware case is a more specific instance of a 404.
		if grep -qi "flatmap-stream" "${log_file}"; then
			__failure["id"]="flatmap-stream-404"
			__failure["classification"]="user"
			__failure["detail"]="E404: $(npm::_extract_error_detail "${log_file}")"
			__failure["message"]=$(
				cat <<-EOF
					Error: The flatmap-stream module has been removed from the npm registry.

					On November 26th (2018), npm was notified of a malicious package that had made
					its way into event-stream, a popular npm package. npm responded by removing
					flatmap-stream and event-stream@3.3.6 from the registry.

					Docs: https://help.heroku.com/4OM7X18J
				EOF
			)
			return 0
		fi

		__failure["id"]="module-404"
		__failure["classification"]="user"
		__failure["detail"]="E404: $(npm::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: Unable to install dependencies using npm.

				A package could not be found in the npm registry (404). Check the log
				output above for the package name and verify it exists and is spelled
				correctly.
			EOF
		)
		return 0
	fi

	# npm ESTRICTALLOWSCRIPTS — new in npm 12. Install scripts are blocked unless covered by the
	# "allowScripts" policy in package.json. Code surfaces on the `npm error code <CODE>` line.
	if grep -qiE 'npm (ERR!|error) code ESTRICTALLOWSCRIPTS' "${log_file}"; then
		__failure["id"]="npm-strict-allow-scripts"
		__failure["classification"]="user"
		__failure["detail"]="ESTRICTALLOWSCRIPTS: $(npm::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: Unable to install dependencies using npm.

				npm blocked one or more dependency install scripts because they are not
				covered by the "allowScripts" policy in your package.json. Native modules
				that compile on install (e.g. via node-gyp) will not be built until you
				approve them.

				Run \`npm approve-scripts <package>\` locally to review and allow the trusted
				packages listed above, then commit the updated package.json and redeploy.

				Docs: https://docs.npmjs.com/cli/v11/commands/npm-approve-scripts
			EOF
		)
		return 0
	fi

	# npm EALLOWGIT — new in npm 12. Git dependencies (direct or transitive) are refused unless
	# allow-git is set. Error code is `EALLOW${TYPE}` from arborist build-ideal-tree.js.
	if grep -qiE 'npm (ERR!|error) code EALLOWGIT' "${log_file}"; then
		__failure["id"]="npm-allow-git-blocked"
		__failure["classification"]="user"
		__failure["detail"]="EALLOWGIT: $(npm::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: Unable to install dependencies using npm.

				npm refused to fetch a dependency that points to a git repository, because
				git dependencies are disabled by default in npm 12+. Check the log output
				above for the offending package.

				Either replace it with a published registry version, or set "allow-git" in
				your .npmrc to permit it.

				Docs: https://docs.npmjs.com/cli/v11/using-npm/config#allow-git
			EOF
		)
		return 0
	fi

	# npm EALLOWREMOTE — new in npm 12. Remote-URL/tarball dependencies (direct or transitive) are
	# refused unless allow-remote is set. Error code is `EALLOW${TYPE}` from arborist.
	if grep -qiE 'npm (ERR!|error) code EALLOWREMOTE' "${log_file}"; then
		__failure["id"]="npm-allow-remote-blocked"
		__failure["classification"]="user"
		__failure["detail"]="EALLOWREMOTE: $(npm::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: Unable to install dependencies using npm.

				npm refused to fetch a dependency that points to a remote URL (e.g. an
				https tarball), because remote dependencies are disabled by default in
				npm 12+. Check the log output above for the offending package.

				Either replace it with a published registry version, or set "allow-remote"
				in your .npmrc to permit it.

				Docs: https://docs.npmjs.com/cli/v11/using-npm/config#allow-remote
			EOF
		)
		return 0
	fi

	# TODO: classify additional npm codes present in error-message.js but not yet handled here,
	# e.g. ETARGET (no matching version), ERESOLVE (dependency conflict), ENOSPC (disk full).
	# Add each as its own matcher above, verified against npm source per the version-spread loop.

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

# Returns the first descriptive npm error line for use as failure detail: the first
# `npm error`/`npm ERR!` line that carries a human message, skipping the bare `code <CODE>`
# line and the trailing "complete log" noise, with the prefix and indentation stripped.
# Internal helper to npm::_handle_npm_install_failure; not meant to be called directly.
function npm::_extract_error_detail() {
	local log_file="${1}"
	grep -iE 'npm (ERR!|error) ' "${log_file}" \
		| grep -ivE 'npm (ERR!|error) code ' \
		| grep -ivE 'A complete log of this run|npm-debug.log' \
		| head -n 1 \
		| sed -E 's/^npm (ERR!|error) //I' \
		| sed -E 's/^[[:space:]]+//' \
		|| true
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__npm_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__npm_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__npm_saved_pipefail}"
unset __npm_saved_flags __npm_saved_pipefail
