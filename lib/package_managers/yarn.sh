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

# Fails fast when a Yarn 2+ (Berry) build has the legacy yarn 1.x `YARN_PRODUCTION` variable set.
# Berry maps it to the unregistered `production` setting and aborts config load — with a strict
# clipanion UsageError — on EVERY yarn invocation (install, prune, and `yarn run <script>` for the
# prebuild/build/cleanup hooks). Detecting the condition here, before any yarn command runs, fails
# once with actionable guidance instead of letting whichever yarn command happens to run first
# blow up partway through the build. Emits directly (the cause is known locally, so there is no log
# to classify); a no-op when the variable is unset, so the caller can invoke it unconditionally.
function package_managers::yarn::fail_if_yarn_production_env_set_on_berry() {
	local yarn_production="${1:-}"

	if [[ -z "${yarn_production}" ]]; then
		return 0
	fi

	# Preserve the legacy matcher's value-sensitive guidance: YARN_PRODUCTION=true meant the app
	# wanted production-only installs (prune devDependencies), so the equivalent Berry setting keeps
	# pruning (YARN2_SKIP_PRUNING=false); any other value meant keep devDependencies, so it skips
	# pruning (YARN2_SKIP_PRUNING=true). Hardcoding one value would invert intent for the common
	# YARN_PRODUCTION=true case, leaving devDependencies in the slug.
	local skip_pruning
	if [[ "${yarn_production}" == "true" ]]; then
		skip_pruning="false"
	else
		skip_pruning="true"
	fi

	local -A failure
	failure["id"]="yarn2-with-yarn-production-env-set"
	failure["classification"]="user"
	failure["message"]=$(
		cat <<-EOF
			Unsupported Yarn configuration: YARN_PRODUCTION

			Yarn 2+ (Berry) does not support the YARN_PRODUCTION environment
			variable and stops the build while loading its configuration.

			To fix, remove YARN_PRODUCTION and use YARN2_SKIP_PRUNING to control
			whether devDependencies are pruned after the build:

			\$ heroku config:unset YARN_PRODUCTION
			\$ heroku config:set YARN2_SKIP_PRUNING=${skip_pruning}
		EOF
	)
	failure::emit failure
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

function package_managers::yarn::install_dependencies() {
	local build_dir="${1:-}"
	local production="${YARN_PRODUCTION:-false}"

	echo "Installing node modules (yarn.lock)"
	cd "${build_dir}" || return

	local log_file
	log_file=$(mktemp)

	local start
	start=$(build_data::current_unix_realtime)

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves.
	# Yarn 1 writes progress and errors across stdout+stderr; merge them with `2>&1` and pass the
	# merged stream through `tee` for classification. Indentation is applied by the enclosing
	# `build_dependencies | output "$LOG_FILE"` pipe in bin/compile — do not re-indent here or
	# every yarn line would be indented twice.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { yarn install --production="${production}" --frozen-lockfile --ignore-engines --prefer-offline 2>&1 | tee "${log_file}"; }; then
		# Capture the full pipe status first (before any other command clobbers PIPESTATUS).
		# The pipeline is `yarn 2>&1 | tee`, so [0] is yarn's exit code and [1] is tee's.
		local pipe_status=("${PIPESTATUS[@]}")
		local yarn_exit="${pipe_status[0]}"
		build_data::set_duration "install_dependencies_time" "${start}"

		local -A failure
		# The installed yarn is old but functional; capture its version here (where yarn is on
		# PATH) so the pure classifier can name it in the outdated-yarn message without running a
		# subprocess itself. `|| true` keeps a --version hiccup from tripping errexit on the
		# already-failing path.
		local yarn_version
		yarn_version="$(yarn --version 2>/dev/null || true)"
		# shellcheck disable=SC2310 # the elif calls a function in a condition, so set -e is disabled inside
		if [[ "${yarn_exit}" -eq 0 ]]; then
			# yarn succeeded but the pipeline failed (tee couldn't write the log — e.g. out of
			# disk). Buildpack-side, so don't run it through the yarn classifier.
			package_managers::yarn::_handle_install_pipefail "${pipe_status[*]}"
		elif failure::handle_git_auth_failure "${log_file}" failure; then
			# A private git+ssh dependency failed SSH host-key verification. This is a
			# cross-cutting git-layer failure (every package manager shells out to git), so it
			# is classified before the yarn-specific matcher below.
			failure::emit failure
		elif package_managers::yarn::_handle_yarn_classic_install_failure "${log_file}" failure "${yarn_version}"; then
			# The classifier fills `failure` by nameref and returns 0 on a match. It is invoked
			# directly in the `elif` condition (not wrapped in `$(...)`) so its writes survive — a
			# command substitution runs in a subshell where the nameref updates would be lost.
			failure::emit failure
		elif failure::handle_econnreset "${log_file}" failure; then
			# A network connection was reset. This is a cross-cutting network-layer failure
			# (every package manager can hit it). Checked last, as a fallback after the
			# yarn-specific matcher above.
			failure::emit failure
		fi

		# No known failure mode recognised. Bubble up by returning yarn's exit code: the pipeline
		# that runs this install (`build_dependencies | output "$LOG_FILE"`) then fails under
		# errexit/pipefail, the legacy ERR trap fires, and `log_other_failures` classifies the
		# failure from $LOG_FILE — covering the yarn 1.x cases still matched there, instead of
		# masking them with a generic message.
		return "${yarn_exit}"
	fi

	build_data::set_duration "install_dependencies_time" "${start}"
}

# Emits the yarn-install pipefail failure for the yarn install paths (yarn 1.x classic and
# yarn 2+ Berry share this wrapper — the user-facing wording is flag-agnostic). Wraps
# `failure::handle_pipefail` with the yarn-specific id and message so callers pass only the
# joined PIPESTATUS string.
function package_managers::yarn::_handle_install_pipefail() {
	local pipe_status_str="${1}"
	local message
	message=$(
		cat <<-EOF
			Error: Unable to capture the yarn install log output.

			The dependency install ran, but writing its log to disk failed (for example,
			the build ran out of disk space). This is not a problem with your
			dependencies. Please try again.
		EOF
	)
	failure::handle_pipefail "yarn-install-pipefail" "${pipe_status_str}" "${message}"
}

# Pure classifier for yarn 1.x (classic) dependency-install failures. Yarn 2+ (Berry) has a
# separate install path (`yarn2_install_dependencies`) with its own error surface and is not
# handled here.
#
# Input:
#   $1  path to a log file containing the captured output of the failed yarn command
#   $2  name of an associative array to fill (see failure::emit for its fields)
#   $3  installed yarn version (captured by the caller where yarn is on PATH), named in the
#       outdated-yarn message
# Returns 0 and fills the array when a known failure mode is recognised; returns 1 and leaves
# the array untouched otherwise. Has no side effects: it does not write build data, print to
# the build log, or exit. Yarn 1 has no numeric error codes, so detail carries the first
# descriptive `error <line>` from the log (prefix stripped) as a discriminator.
function package_managers::yarn::_handle_yarn_classic_install_failure() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"
	# Only the outdated-yarn branch names the version; other failure modes may omit it.
	local yarn_version="${3:-}"

	# Yarn 1.x emits this literal line from src/cli/commands/install.js when --frozen-lockfile
	# detects a mismatch between package.json and yarn.lock.
	if grep -qi 'Your lockfile needs to be updated' "${log_file}"; then
		__failure["id"]="outdated-yarn-lockfile"
		__failure["classification"]="user"
		__failure["detail"]="$(package_managers::yarn::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Outdated Yarn lockfile

				Your application's yarn.lock does not match the dependencies in
				package.json. The yarn.lock records the exact modules Yarn installed,
				and the build fails when the two drift apart to prevent subtle bugs
				and security issues.

				This commonly happens when another tool modifies package.json without
				running yarn install — for example, using npm to add a dependency, or
				editing a version requirement by hand.

				To fix, run yarn install in your project directory and commit the
				updated yarn.lock:

				\$ yarn install
				\$ git add yarn.lock
				\$ git commit -m "Updated Yarn lockfile"
				\$ git push heroku main
			EOF
		)
		return 0
	fi

	# Yarn <0.19 emits this error when --frozen-lockfile is used (the flag wasn't added until
	# 0.19). The app's engines.yarn controls which version is installed. The caller passes the
	# installed version (captured where yarn is on PATH) so this message can name it, matching
	# the legacy handler's wording, while the classifier itself stays subprocess-free.
	if grep -qi 'error .install. has been replaced with .add. to add new dependencies' "${log_file}"; then
		__failure["id"]="outdated-yarn"
		__failure["classification"]="user"
		__failure["detail"]="$(package_managers::yarn::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Outdated Yarn version: ${yarn_version}

				Your application is specifying a requirement on an old version of Yarn (${yarn_version})
				which does not support the --frozen-lockfile option. Please upgrade to a
				newer version, at least 0.19, by updating your requirement in the 'engines'
				field in your package.json.

				"engines": {
				  "yarn": "1.3.2"
				}

				https://devcenter.heroku.com/articles/nodejs-support#specifying-a-yarn-version
			EOF
		)
		return 0
	fi

	# Yarn 1.x emits this literal line from its package resolver (src/package-request.js) when no
	# published version satisfies the requested range. Keyed on the message text because yarn 1 has
	# no numeric error codes. The legacy failure id (`bad-version-for-dependency`) is preserved
	# verbatim so the `failure` build-data key stays continuous for downstream metrics.
	if grep -qi "error Couldn't find any versions for" "${log_file}"; then
		__failure["id"]="bad-version-for-dependency"
		__failure["classification"]="user"
		__failure["detail"]="$(package_managers::yarn::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: Unable to install dependencies using Yarn.

				One of your dependencies requests a package version that does not exist
				in the npm registry. Check the log output above for the offending package
				and version range, and update it to a version that has been published.
			EOF
		)
		return 0
	fi

	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if package_managers::yarn::_match_classic_registry_404 "${log_file}" __failure; then
		return 0
	fi

	# TODO: classify additional yarn 1.x failures still matched by the legacy trap's
	# `log_other_failures` in a follow-up migration.

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

# Returns the first descriptive yarn error line for use as failure detail: the first
# `error <message>` line, with the `error ` prefix stripped. Yarn 1 has no numeric codes, so
# the message text itself is the discriminator inside a bucket. Internal helper to
# package_managers::yarn::_handle_yarn_classic_install_failure; not meant to be called directly.
function package_managers::yarn::_extract_error_detail() {
	local log_file="${1}"
	grep -iE '^error ' "${log_file}" \
		| head -n 1 \
		| sed -E 's/^error //I' \
		|| true
}

# Pure classifier for the yarn 1.x (classic) registry-404 failure. Yarn's reporter prints this
# distinct wording (no numeric error code) rather than npm's `code E404` summary line, so it needs
# its own matcher — but it fills the SAME failure id/classification as npm's E404 branch
# (package_managers::npm::_handle_npm_install_failure in npm.sh) so the `module-404` /
# `flatmap-stream-404` metric stays unified across package managers regardless of which one hit
# the 404. Shared by both the classic install and classic prune (reinstall) classifiers, since
# either can re-fetch a package and hit the same registry response.
#
# Input:
#   $1  path to a log file containing the captured output of the failed yarn command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when the yarn-classic 404 wording is recognised; returns 1 and
# leaves the array untouched otherwise. Has no side effects.
function package_managers::yarn::_match_classic_registry_404() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure404="${2}"

	# Yarn 1.x reporter (src/reporters/console/console-reporter.js) wraps any thrown request
	# error as `error An unexpected error occurred: "<message>".`, where <message> is the
	# request wrapper's `Request failed "404 Not Found"` for a registry 404.
	if grep -qiE 'error An unexpected error occurred: .* Request failed "404 Not Found"' "${log_file}"; then
		# The flatmap-stream malware case is a more specific instance of a 404.
		if grep -qi "flatmap-stream" "${log_file}"; then
			__failure404["id"]="flatmap-stream-404"
			__failure404["classification"]="user"
			__failure404["detail"]="$(package_managers::yarn::_extract_error_detail "${log_file}")"
			__failure404["message"]=$(
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

		__failure404["id"]="module-404"
		__failure404["classification"]="user"
		__failure404["detail"]="$(package_managers::yarn::_extract_error_detail "${log_file}")"
		__failure404["message"]=$(
			cat <<-EOF
				Error: Unable to install dependencies using Yarn.

				A package could not be found in the npm registry (404). Check the log
				output above for the package name and verify it exists and is spelled
				correctly.
			EOF
		)
		return 0
	fi

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

function package_managers::yarn::yarn2_install_dependencies() {
	local build_dir="${1:-}"

	echo "Running 'yarn install' with yarn.lock"
	cd "${build_dir}" || return

	local log_file
	log_file=$(mktemp)

	local start
	start=$(build_data::current_unix_realtime)

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves.
	# Berry writes progress and errors across stdout+stderr; merge them with `2>&1` and pass the
	# merged stream through `tee` for classification. Indentation is applied by the enclosing
	# `build_dependencies | output "$LOG_FILE"` pipe in bin/compile — do not re-indent here or
	# every yarn line would be indented twice.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { yarn install --immutable 2>&1 | tee "${log_file}"; }; then
		# Capture the full pipe status first (before any other command clobbers PIPESTATUS).
		# The pipeline is `yarn 2>&1 | tee`, so [0] is yarn's exit code and [1] is tee's.
		local pipe_status=("${PIPESTATUS[@]}")
		local yarn_exit="${pipe_status[0]}"
		build_data::set_duration "install_dependencies_time" "${start}"

		local -A failure
		# shellcheck disable=SC2310 # the elif calls a function in a condition, so set -e is disabled inside
		if [[ "${yarn_exit}" -eq 0 ]]; then
			# yarn succeeded but the pipeline failed (tee couldn't write the log — e.g. out of
			# disk). Buildpack-side, so don't run it through the Berry classifier. Reuses the
			# shared yarn pipefail wrapper — the user-facing wording covers both yarn 1 and Berry.
			package_managers::yarn::_handle_install_pipefail "${pipe_status[*]}"
		elif failure::handle_git_auth_failure "${log_file}" failure; then
			# A private git+ssh dependency failed SSH host-key verification. This is a
			# cross-cutting git-layer failure (every package manager shells out to git), so it
			# is classified before the Berry-specific matcher below.
			failure::emit failure
		elif package_managers::yarn::_handle_yarn_berry_install_failure "${log_file}" failure; then
			# The classifier fills `failure` by nameref and returns 0 on a match. It is invoked
			# directly in the `elif` condition (not wrapped in `$(...)`) so its writes survive — a
			# command substitution runs in a subshell where the nameref updates would be lost.
			failure::emit failure
		elif failure::handle_econnreset "${log_file}" failure; then
			# A network connection was reset. This is a cross-cutting network-layer failure
			# (every package manager can hit it). Checked last, as a fallback after the
			# Berry-specific matcher above.
			failure::emit failure
		fi

		# No known failure mode recognised. Bubble up by returning yarn's exit code: the pipeline
		# that runs this install (`build_dependencies | output "$LOG_FILE"`) then fails under
		# errexit/pipefail, the legacy ERR trap fires, and `log_other_failures` classifies the
		# failure from $LOG_FILE — covering the Berry YN codes (e.g. YN0001, YN0018) not yet
		# migrated here, instead of masking them with a generic message.
		return "${yarn_exit}"
	fi

	build_data::set_duration "install_dependencies_time" "${start}"
}

# Pure classifier for yarn 2+ (Berry) dependency-install failures. Yarn 1.x (classic) has a
# separate install path (`install_dependencies`) with its own error surface and is not handled
# here.
#
# Input:
#   $1  path to a log file containing the captured output of the failed yarn command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when a known failure mode is recognised; returns 1 and leaves
# the array untouched otherwise. Has no side effects: it does not write build data, print to
# the build log, or exit. Detail is set to the Berry YN-code plus the first descriptive
# framed error line, giving observability a precise discriminator within each failure bucket.
function package_managers::yarn::_handle_yarn_berry_install_failure() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	# YN0028 — Berry refuses to modify yarn.lock under `--immutable`. Emitted from
	# @yarnpkg/core's install report when the resolution step would have written a new
	# lockfile (see yarnpkg/berry sources/Report.ts + install command).
	if grep -qi 'YN0028' "${log_file}"; then
		__failure["id"]="yarn-lockfile-out-of-sync"
		__failure["classification"]="user"
		__failure["detail"]="YN0028: $(package_managers::yarn::_extract_berry_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Yarn lockfile is not in sync

				Your application's yarn.lock does not match the dependencies in
				package.json, and yarn install was run with --immutable so it refused
				to modify the lockfile. The build fails when the two drift apart to
				prevent subtle bugs and security issues.

				This commonly happens when another tool modifies package.json without
				running yarn install — for example, using npm to add a dependency, or
				editing a version requirement by hand.

				To fix, run yarn install in your project directory and commit the
				updated yarn.lock:

				\$ yarn install
				\$ git add yarn.lock
				\$ git commit -m "Updated Yarn lockfile"
				\$ git push heroku main
			EOF
		)
		return 0
	fi

	# TODO: classify additional Berry YN codes currently handled by the legacy trap in
	# follow-up migrations (e.g. YN0001 internal error, YN0018 checksum mismatch).

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

# Returns the first descriptive Berry error line for use as failure detail: Berry emits
# progress and errors as `➤ YN####: <message>` (often with box-drawing framing when inside a
# report group). Skip YN0000 (informational bookkeeping — "Yarn X.Y.Z", "Resolution step",
# etc.), grab the first real code line, and strip the arrow/code prefix and box-drawing so the
# detail carries just the descriptive text alongside the code prefix set by callers. Internal
# helper to package_managers::yarn::_handle_yarn_berry_install_failure; not meant to be called
# directly.
function package_managers::yarn::_extract_berry_error_detail() {
	local log_file="${1}"
	grep -aE 'YN[0-9]{4}:' "${log_file}" \
		| grep -av 'YN0000:' \
		| head -n 1 \
		| sed -E 's/.*YN[0-9]{4}:[[:space:]]*//' \
		| sed -E 's/^[│├└┌─┐┘[:space:]]+//' \
		|| true
}

function package_managers::yarn::prune_devdependencies() {
	local build_dir=${1:-}
	local buildpack_dir=${2:-}

	# NODE_ENV, YARN_PRODUCTION, and YARN_2 are globals exported by the caller (bin/compile via
	# lib/environment.sh / the app's config vars). The NODE_ENV and YARN_PRODUCTION skip gates
	# apply to both yarn flavors; each per-flavor worker owns its prune command, failure handling,
	# and any flavor-specific skip (e.g. YARN2_SKIP_PRUNING).
	# shellcheck disable=SC2154 # set by the caller (bin/compile)
	if [[ "${NODE_ENV}" == "test" ]]; then
		echo "Skipping because NODE_ENV is 'test'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	elif [[ "${NODE_ENV}" != "production" ]]; then
		echo "Skipping because NODE_ENV is not 'production'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	elif [[ -n "${YARN_PRODUCTION}" ]]; then
		echo "Skipping because YARN_PRODUCTION is '${YARN_PRODUCTION}'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	elif ${YARN_2}; then
		package_managers::yarn::_prune_berry_devdependencies "${build_dir}" "${buildpack_dir}"
	else
		package_managers::yarn::_prune_classic_devdependencies "${build_dir}"
	fi
}

# Runs the yarn 1.x (classic) devDependency prune (`yarn install --frozen-lockfile` against the
# production dependency set). Yarn 2+ (Berry) has a separate prune path
# (`_prune_berry_devdependencies`) with its own error surface. The shared NODE_ENV/YARN_PRODUCTION
# skip gates are handled by the `prune_devdependencies` entry point before dispatch.
function package_managers::yarn::_prune_classic_devdependencies() {
	local build_dir="${1}"

	cd "${build_dir}" || return

	local log_file
	log_file=$(mktemp)

	local start
	start=$(build_data::current_unix_realtime)

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves.
	# Yarn 1 writes progress and errors across stdout+stderr; merge them with `2>&1` and pass
	# the merged stream through `tee` for classification. Indentation is applied by the
	# enclosing `prune_devdependencies | output "$LOG_FILE"` pipe in bin/compile — do not
	# re-indent here or every yarn line would be indented twice.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { yarn install --frozen-lockfile --ignore-engines --ignore-scripts --prefer-offline 2>&1 | tee "${log_file}"; }; then
		# Capture the full pipe status first (before any other command clobbers PIPESTATUS).
		# The pipeline is `yarn 2>&1 | tee`, so [0] is yarn's exit code and [1] is tee's.
		local pipe_status=("${PIPESTATUS[@]}")
		local yarn_exit="${pipe_status[0]}"
		build_data::set_duration "prune_dev_dependencies_time" "${start}"

		local -A failure
		# shellcheck disable=SC2310 # the elif calls a function in a condition, so set -e is disabled inside
		if [[ "${yarn_exit}" -eq 0 ]]; then
			# yarn succeeded but the pipeline failed (tee couldn't write the log — e.g. out of
			# disk). Buildpack-side, so don't run it through the prune classifier.
			package_managers::yarn::_handle_prune_pipefail "${pipe_status[*]}"
		elif failure::handle_git_auth_failure "${log_file}" failure; then
			# The classic prune path reinstalls with `yarn install --frozen-lockfile`, which can
			# re-fetch a git+ssh dependency and hit the same host-key failure as a fresh install.
			failure::emit failure
		elif package_managers::yarn::_handle_yarn_classic_prune_failure "${log_file}" failure; then
			# The classifier fills `failure` by nameref and returns 0 on a match. It is invoked
			# directly in the `elif` condition (not wrapped in `$(...)`) so its writes survive — a
			# command substitution runs in a subshell where the nameref updates would be lost.
			failure::emit failure
		elif failure::handle_econnreset "${log_file}" failure; then
			# The classic prune path reinstalls with `yarn install --frozen-lockfile`, which can
			# re-fetch a dependency and hit the same network-reset failure as a fresh install.
			# Checked last, as a fallback after the yarn-specific matcher above.
			failure::emit failure
		fi

		# No known prune failure mode recognised. Bubble up by returning yarn's exit code: the
		# pipeline that runs this prune (`prune_devdependencies | output "$LOG_FILE"`) then fails
		# under errexit/pipefail, the legacy ERR trap fires, and `log_other_failures` classifies
		# the failure from $LOG_FILE — today unrecognised prune failures fall through to its
		# `unknown-prune-dependencies-error` catch-all, instead of being masked with a generic
		# message.
		return "${yarn_exit}"
	fi

	build_data::set_duration "prune_dev_dependencies_time" "${start}"
	build_data::set_raw "skipped_prune" "false"
}

# Emits the yarn-prune pipefail failure for the devDependency-prune paths (yarn 1.x classic and
# yarn 2+ Berry share this wrapper — the user-facing wording is flag-agnostic). Wraps
# `failure::handle_pipefail` with the prune-specific id and message so callers pass only the
# joined PIPESTATUS string.
function package_managers::yarn::_handle_prune_pipefail() {
	local pipe_status_str="${1}"
	local message
	message=$(
		cat <<-EOF
			Error: Unable to capture the yarn prune log output.

			The devDependency prune ran, but writing its log to disk failed (for example,
			the build ran out of disk space). This is not a problem with your
			dependencies. Please try again.
		EOF
	)
	failure::handle_pipefail "yarn-prune-pipefail" "${pipe_status_str}" "${message}"
}

# Pure classifier for yarn 1.x (classic) devDependency-prune failures. Yarn 2+ (Berry) has a
# separate prune path (`_prune_berry_devdependencies`) with its own classifier. No prune-specific
# failure mode is recognised today beyond the shared registry-404 matcher — the prune reinstall
# (`yarn install --frozen-lockfile`) can re-fetch a package and hit the same 404 as a fresh
# install — so this is kept as the home for any future yarn 1.x prune-specific matcher.
#
# Input:
#   $1  path to a log file containing the captured output of the failed yarn prune command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when a known failure mode is recognised; returns 1 and leaves
# the array untouched otherwise. Has no side effects.
function package_managers::yarn::_handle_yarn_classic_prune_failure() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if package_managers::yarn::_match_classic_registry_404 "${log_file}" __failure; then
		return 0
	fi

	# TODO: classify yarn 1.x prune-specific failures here if any surface (none known today).

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

# Runs the yarn 2+ (Berry) devDependency prune (`yarn heroku prune` via the bundled plugin). Yarn
# 1.x (classic) has a separate prune path (`_prune_classic_devdependencies`) with its own error
# surface. Honors the Berry-only YARN2_SKIP_PRUNING escape hatch, then removes the local Yarn
# cache when the node-modules linker is in use to keep the slug small. The shared
# NODE_ENV/YARN_PRODUCTION skip gates are handled by the `prune_devdependencies` entry point
# before dispatch.
function package_managers::yarn::_prune_berry_devdependencies() {
	local build_dir="${1}"
	local buildpack_dir="${2}"

	# shellcheck disable=SC2154 # YARN2_SKIP_PRUNING is a global set by the caller (bin/compile)
	if [[ "${YARN2_SKIP_PRUNING}" == "true" ]]; then
		echo "Skipping because YARN2_SKIP_PRUNING is '${YARN2_SKIP_PRUNING}'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	fi

	cd "${build_dir}" || return
	echo "Running 'yarn heroku prune'"
	export YARN_PLUGINS="${buildpack_dir}/yarn2-plugins/prune-dev-dependencies/bundles/@yarnpkg/plugin-prune-dev-dependencies.js"

	local log_file
	log_file=$(mktemp)

	local start
	start=$(build_data::current_unix_realtime)

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves.
	# Berry writes progress and errors across stdout+stderr; merge them with `2>&1` and pass
	# the merged stream through `tee` for classification. Indentation is applied by the
	# enclosing `prune_devdependencies | output "$LOG_FILE"` pipe in bin/compile — do not
	# re-indent here or every yarn line would be indented twice.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { yarn heroku prune 2>&1 | tee "${log_file}"; }; then
		# Capture the full pipe status first (before any other command clobbers PIPESTATUS).
		# The pipeline is `yarn 2>&1 | tee`, so [0] is yarn's exit code and [1] is tee's.
		local pipe_status=("${PIPESTATUS[@]}")
		local yarn_exit="${pipe_status[0]}"
		build_data::set_duration "prune_dev_dependencies_time" "${start}"

		local -A failure
		# shellcheck disable=SC2310 # the elif calls a function in a condition, so set -e is disabled inside
		if [[ "${yarn_exit}" -eq 0 ]]; then
			# yarn succeeded but the pipeline failed (tee couldn't write the log — e.g. out of
			# disk). Buildpack-side, so don't run it through the Berry prune classifier. Reuses the
			# shared yarn-prune pipefail wrapper — the user-facing wording covers both flavors.
			package_managers::yarn::_handle_prune_pipefail "${pipe_status[*]}"
		elif package_managers::yarn::_handle_yarn_berry_prune_failure "${log_file}" failure; then
			# The classifier fills `failure` by nameref and returns 0 on a match. It is invoked
			# directly in the `elif` condition (not wrapped in `$(...)`) so its writes survive — a
			# command substitution runs in a subshell where the nameref updates would be lost.
			failure::emit failure
		fi

		# No known prune failure mode recognised. Bubble up by returning yarn's exit code: the
		# pipeline that runs this prune (`prune_devdependencies | output "$LOG_FILE"`) then fails
		# under errexit/pipefail, the legacy ERR trap fires, and `log_other_failures` classifies
		# the failure from $LOG_FILE — today unrecognised prune failures fall through to its
		# `unknown-prune-dependencies-error` catch-all, instead of being masked with a generic
		# message.
		return "${yarn_exit}"
	fi

	build_data::set_duration "prune_dev_dependencies_time" "${start}"

	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside; a false result just skips the cache cleanup
	if package_managers::yarn::_berry_node_modules_enabled "${build_dir}"; then
		echo "Removing local yarn cache to reduce slug size"
		rm -rf "${build_dir}/.yarn/cache"
	fi
	build_data::set_raw "skipped_prune" "false"
}

# Pure classifier for yarn 2+ (Berry) devDependency-prune failures. Yarn 1.x (classic) has a
# separate prune path (`_prune_classic_devdependencies`) with its own classifier. No prune-specific
# failure mode is recognised today. This stub always returns 1 so the caller bubbles the raw exit
# code to the legacy trap; it is kept for symmetry with the Berry install classifier and as the
# home for any future Berry prune matcher.
#
# Input:
#   $1  path to a log file containing the captured output of the failed yarn prune command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when a known failure mode is recognised; returns 1 and leaves
# the array untouched otherwise. Has no side effects.
function package_managers::yarn::_handle_yarn_berry_prune_failure() {
	# shellcheck disable=SC2034 # $1 (log_file) is unused today; kept to match the classifier signature for future matchers
	local log_file="${1}"
	# shellcheck disable=SC2178,SC2034 # nameref to the caller's array; unused until a matcher fills it
	local -n __failure="${2}"

	# TODO: classify Berry prune-specific failures here if any surface (none known today).

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

function package_managers::yarn::detect_berry() {
	local uses_yarn="${1}"
	local build_dir="${2}"
	local yml_metadata
	local version

	yml_metadata=$(utils::yaml::read "${build_dir}/yarn.lock" '.__metadata' 2>/dev/null)

	# grep for version in case the output is a parsing error
	version=$(echo "${yml_metadata}" | grep version)

	if [[ "${uses_yarn}" == "true" && "${version}" != "" ]]; then
		echo "true"
	else
		echo "false"
	fi
}

function package_managers::yarn::berry_has_release_script() {
	local build_dir="${1}"
	local yarn_path
	yarn_path=$(utils::yaml::read "${build_dir}/.yarnrc.yml" '.yarnPath' 2>/dev/null)
	[[ -n "${yarn_path}" && "${yarn_path}" != "null" ]] && [[ -f "${build_dir}/${yarn_path}" ]]
}

function package_managers::yarn::berry_has_cache() {
	local build_dir="${1}"
	local yarn_cache="${build_dir}/.yarn/cache"
	# shellcheck disable=SC2312 # the boolean test only cares whether the directory is non-empty; masking ls's exit is intentional (matches pre-migration behavior)
	[[ -d "${yarn_cache}" ]] && [[ -n "$(ls -A "${yarn_cache}")" ]]
}

function package_managers::yarn::berry_get_path() {
	local build_dir="${1}"
	local yarn_path
	yarn_path=$(utils::yaml::read "${build_dir}/.yarnrc.yml" '.yarnPath' 2>/dev/null)
	if [[ -n "${yarn_path}" && "${yarn_path}" != "null" ]]; then
		echo "${yarn_path}"
	fi
}

# Emits the classified failure for a missing Yarn 2+ (Berry) `.yarnrc.yml` during the vendoring
# pre-flight and exits. Keeps the existing validate-then-emit guard so bin/compile's control flow
# is unchanged: on a missing file it fills a local failure array and calls failure::emit (which
# prints, records build data, sets the marker, and exits); otherwise it returns cleanly. Preserves
# the historical `missing-yarnrc-yml` failure id for metric continuity. See
# runtimes::nodejs::_fail_node_download for the direct-emit-at-site rationale.
function package_managers::yarn::fail_missing_yarnrc_yml() {
	local build_dir="${1}"

	if [[ ! -f "${build_dir}/.yarnrc.yml" ]]; then
		local -A failure
		failure["id"]="missing-yarnrc-yml"
		failure["classification"]="user"
		failure["detail"]="${build_dir}/.yarnrc.yml"
		failure["message"]=$(
			cat <<-EOF
				The 'yarnrc.yml' file is not found

				It looks like the 'yarnrc.yml' file is missing from this project. Please
				make sure this file is checked into version control and made available to
				Heroku.

				To generate 'yarnrc.yml', make sure Yarn 2 is installed on your local
				machine and set the version in your project directory with:

				 \$ yarn set version berry

				Read more at the Yarn docs: https://yarnpkg.com/getting-started/install#per-project-install
				https://devcenter.heroku.com/articles/nodejs-support
			EOF
		)
		failure::emit failure
	fi
}

# Emits the classified failure when the `yarnPath` value could not be read from `.yarnrc.yml`
# during the Yarn 2+ (Berry) vendoring pre-flight and exits. Keeps the existing validate-then-emit
# guard (an empty yarn_path) so bin/compile's control flow is unchanged. Preserves the historical
# `missing-yarn-path` failure id for metric continuity. See
# runtimes::nodejs::_fail_node_download for the direct-emit-at-site rationale.
function package_managers::yarn::fail_missing_yarn_path() {
	local build_dir="${1}"
	local yarn_path="${2}"

	if [[ "${yarn_path}" == "" ]]; then
		local -A failure
		failure["id"]="missing-yarn-path"
		failure["classification"]="user"
		failure["detail"]="${build_dir}/.yarnrc.yml"
		failure["message"]=$(
			cat <<-EOF
				The 'yarnPath' could not be read from the 'yarnrc.yml' file

				It looks like 'yarnrc.yml' is missing the 'yarnPath' value, which is needed
				to identify the location of yarn for this build.

				To regenerate 'yarnrc.yml' with the 'yarnPath' value set, make sure Yarn 2
				is installed on your local machine and set the version in your project
				directory with:

				 \$ yarn set version berry

				Read more at the Yarn docs: https://yarnpkg.com/getting-started/install#per-project-install
				https://devcenter.heroku.com/articles/nodejs-support
			EOF
		)
		failure::emit failure
	fi
}

# Emits the classified failure when the vendored Yarn release referenced by `yarnPath` is missing
# from the app during the Yarn 2+ (Berry) vendoring pre-flight and exits. Keeps the existing
# validate-then-emit guard so bin/compile's control flow is unchanged. Preserves the historical
# `missing-yarn-vendor` failure id for metric continuity, and records the offending path in detail.
# See runtimes::nodejs::_fail_node_download for the direct-emit-at-site rationale.
function package_managers::yarn::fail_missing_yarn_vendor() {
	local build_dir="${1}"
	local yarn_path="${2}"

	if [[ ! -f "${build_dir}/${yarn_path}" ]]; then
		local -A failure
		failure["id"]="missing-yarn-vendor"
		failure["classification"]="user"
		failure["detail"]="${yarn_path}"
		failure["message"]=$(
			cat <<-EOF
				Yarn was not found

				It looks like yarn is missing from ${yarn_path}, which is needed to continue
				this build on Heroku. Yarn 2 recommends vendoring Yarn under the '.yarn/releases'
				directory, so remember to check the '.yarn' directory into version control
				to use during builds.

				To generate the '.yarn' directory correctly, make sure Yarn 2 is installed
				on your local machine and run the following in your project directory:

				 \$ yarn install
				 \$ yarn set version berry

				Read more at the Yarn docs: https://yarnpkg.com/getting-started/install#per-project-install
				https://devcenter.heroku.com/articles/nodejs-support
			EOF
		)
		failure::emit failure
	fi
}

function package_managers::yarn::berry_use_app_cache() {
	local build_dir="${1}"
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside (matches pre-migration behavior)
	if package_managers::yarn::berry_has_cache "${build_dir}" || ! package_managers::yarn::_berry_node_modules_enabled "${build_dir}"; then
		return
	fi
	false
}

function package_managers::yarn::_berry_node_modules_enabled() {
	local build_dir="${1}"
	local node_linker

	node_linker=$(utils::yaml::read "${build_dir}/.yarnrc.yml" '.nodeLinker' 2>/dev/null)

	[[ "${node_linker}" == "node-modules" ]]
}

function package_managers::yarn::get_major_version() {
	local build_dir="${1}"
	local package_manager yarn_engine version_string

	# Check packageManager field first (e.g., "yarn@4.0.0")
	package_manager=$(utils::json::read "${build_dir}/package.json" ".packageManager")
	if [[ "${package_manager}" == yarn@* ]]; then
		version_string="${package_manager#yarn@}"
		# Extract major version (e.g., "4.0.0" -> "4", "4.0.0+sha256.abc" -> "4")
		echo "${version_string}" | cut -d "." -f 1
		return
	fi

	# Check engines.yarn field (e.g., "4.x", "^4.0.0", ">=4.0.0")
	yarn_engine=$(utils::json::read "${build_dir}/package.json" ".engines.yarn")
	if [[ -n "${yarn_engine}" ]]; then
		# Extract major version, ignoring any non-numeric prefix
		version_string=$(echo "${yarn_engine}" | sed -E 's/^[^0-9]*([0-9]+)\.?.*/\1/')
		if [[ -n "${version_string}" ]]; then
			echo "${version_string}"
			return
		fi
	fi

	# If we can't determine version, return empty string
	echo ""
}

# Runs a named lifecycle script with yarn. Spells the yarn-specific command (`yarn run <script>`,
# forwarding NODE_BUILD_FLAGS as a trailing argument — yarn takes no `--` separator) and hands
# execution to the shared coordinator runner, which captures output and routes failures.
# `build_flags` is the optional NODE_BUILD_FLAGS string (empty for prebuild/postbuild/cleanup
# scripts). Unlike npm/pnpm, yarn errors on an empty script string, so a script whose body is
# empty is announced but not run (yarn has no `--if-present` equivalent).
function package_managers::yarn::run_script() {
	local build_dir=${1}
	local script_name=${2}
	local build_flags=${3:-}
	local script

	echo "Running ${script_name} (yarn)"

	script=$(utils::json::read "${build_dir}/package.json" ".scripts[\"${script_name}\"]")
	if [[ -z "${script}" ]]; then
		return 0
	fi

	local command=(yarn run "${script_name}")
	if [[ -n "${build_flags}" ]]; then
		echo "Running with ${build_flags} flags"
		command+=("${build_flags}")
	fi

	package_manager::run_script_command "${command[@]}"
}

# Lists installed top-level dependencies for the verbose build summary. Wrapped in `|| true` and
# `2>/dev/null` so a listing failure never aborts the summary.
function package_managers::yarn::list_dependencies() {
	local build_dir=${1:-}

	cd "${build_dir}" || return
	(yarn list --depth=0 || true) 2>/dev/null
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__yarn_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__yarn_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__yarn_saved_pipefail}"
unset __yarn_saved_flags __yarn_saved_pipefail
