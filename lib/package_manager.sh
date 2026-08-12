#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. The
# caller's flags are read from `$-` (the current shell); a `$(set +o)` capture runs in a
# command-substitution subshell where bash always forces errexit off, so it would later
# restore errexit as disabled even when the caller had it on. pipefail has no `$-` letter, so
# it is captured separately (it is reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__package_manager_saved_flags="$-"
__package_manager_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

# Dispatches a named lifecycle script to the active package manager's module, which spells and
# runs the tool-specific command (`npm/yarn/pnpm run <script>`). This is the coordination seam:
# the coordinator decides *which* script runs and *whether* build flags apply; the module decides
# how to spell the command. Mirrors the Node.js CNB's `package_manager` → per-PM-module dispatch.
function package_manager::_dispatch_run_script() {
	local build_dir=${1:-}
	local script_name=${2:-}
	local build_flags=${3:-}

	# YARN, YARN_2, and PNPM are globals exported by the caller (bin/compile).
	# shellcheck disable=SC2154 # set by the caller (bin/compile)
	if ${YARN} || ${YARN_2}; then
		package_managers::yarn::run_script "${build_dir}" "${script_name}" "${build_flags}"
	elif ${PNPM}; then
		package_managers::pnpm::run_script "${script_name}" "${build_flags}"
	else
		package_managers::npm::run_script "${script_name}" "${build_flags}"
	fi
}

# Lists installed top-level dependencies for the verbose build summary. Coordinator: picks the
# active package manager and delegates to its module (mirrors package_manager::_dispatch_run_script).
# Frames the listing in blank lines to set it off from the surrounding build log; the per-PM
# modules stay presentation-free and only spell their native listing command.
function package_manager::list_dependencies() {
	local build_dir=${1:-}

	echo ""
	# YARN, YARN_2, and PNPM are globals exported by the caller (bin/compile).
	# shellcheck disable=SC2154 # set by the caller (bin/compile)
	if ${YARN} || ${YARN_2}; then
		package_managers::yarn::list_dependencies "${build_dir}"
	elif ${PNPM}; then
		package_managers::pnpm::list_dependencies "${build_dir}"
	else
		package_managers::npm::list_dependencies "${build_dir}"
	fi
	echo ""
}

# Runs a lifecycle-script command built by a package-manager module, capturing its merged
# output for classification. This is the shared execution + failure-routing layer for all
# package managers (the per-PM modules only spell the command). Cross-cutting failures
# (git-auth, econnreset, libc6 incompatibility) and build-script-specific failures (e.g. the
# OpenSSL unsupported-algorithm error) are classified here; any other failure bubbles up to the
# generic failure::handle_uncaught ERR trap, which records failure=internal-error.
function package_manager::run_script_command() {
	local command=("$@")

	local log_file
	log_file=$(mktemp)

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves. The
	# script's stdout+stderr are merged with `2>&1` and passed through `tee` (for later
	# classification) to stdout; indentation is applied by the enclosing `… | output "$LOG_FILE"`
	# pipe in bin/compile, so do not re-indent here.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { "${command[@]}" 2>&1 | tee "${log_file}"; }; then
		# Capture the full pipe status first (before any other command clobbers PIPESTATUS).
		# The pipeline is `<tool> 2>&1 | tee`, so [0] is the tool's exit code and [1] is tee's.
		local pipe_status=("${PIPESTATUS[@]}")
		local tool_exit="${pipe_status[0]}"

		local -A failure
		# shellcheck disable=SC2310 # the elif calls a function in a condition, so set -e is disabled inside
		if [[ "${tool_exit}" -eq 0 ]]; then
			# The script succeeded but the pipeline failed (tee couldn't write the log — e.g. out
			# of disk). Buildpack-side, so report it directly rather than blaming the app.
			package_manager::_handle_script_pipefail "${pipe_status[*]}"
		elif failure::handle_git_auth_failure "${log_file}" failure; then
			# A heroku-prebuild/build/heroku-postbuild/heroku-cleanup script can shell out to git
			# for a git+ssh:// dependency and hit the same SSH host-key failure as the main
			# install. This is a cross-cutting git-layer failure (every package manager shells out
			# to git), so it is classified before bubbling to the generic ERR-trap fallback.
			failure::emit failure
		elif package_manager::_handle_build_script_failure "${log_file}" failure; then
			# Build-script-specific failures (not tied to a particular package manager, since the
			# command run here is the app's own script). Checked before the cross-cutting network
			# and runtime fallbacks below so a specific build-script cause wins.
			failure::emit failure
		elif failure::handle_econnreset "${log_file}" failure; then
			# A build-script lifecycle hook can hit a network reset the same way the main
			# install can (e.g. installing something itself, or shelling out to a registry).
			# This is a cross-cutting network-layer failure; checked last, as a fallback after
			# the build-script-specific matcher above.
			failure::emit failure
		elif failure::handle_libc6_incompatibility "${log_file}" failure; then
			# The Node.js binary itself is incompatible with the current stack's glibc. This is a
			# cross-cutting runtime-layer failure; checked last, as a fallback after the
			# build-script-specific matcher above.
			failure::emit failure
		fi

		# No known failure mode recognised. Bubble up the tool's exit code so the pipeline that
		# runs this script fails under errexit/pipefail and the generic failure::handle_uncaught
		# ERR trap records it as failure=internal-error — covering the failure modes not yet
		# migrated here.
		return "${tool_exit}"
	fi
}

# Emits the build-script pipefail failure for the case where the script inside a
# `<tool> run … | tee log` pipeline exited 0 but a downstream stage (typically `tee` writing to
# the log) failed — for example the build ran out of disk space. Wraps `failure::handle_pipefail`
# with a build-script id and message so callers pass only the joined PIPESTATUS string.
function package_manager::_handle_script_pipefail() {
	local pipe_status_str="${1}"
	local message
	message=$(
		cat <<-EOF
			Error: Unable to capture the build script log output.

			The build script ran, but writing its log to disk failed (for example,
			the build ran out of disk space). This is not a problem with your
			application. Please try again.
		EOF
	)
	failure::handle_pipefail "build-script-pipefail" "${pipe_status_str}" "${message}"
}

# Pure classifier for build-script failures that aren't tied to a particular package manager —
# the command run at this call site is the app's own heroku-prebuild/build/heroku-postbuild/
# heroku-cleanup script, so these matchers key on Node.js/tool-level signals rather than a
# package-manager error code.
#
# Input:
#   $1  path to a log file containing the captured output of the failed script
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when a known failure mode is recognised; returns 1 and leaves
# the array untouched otherwise. Has no side effects: it does not write build data, print to
# the build log, or exit.
function package_manager::_handle_build_script_failure() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	# ERR_OSSL_EVP_UNSUPPORTED — thrown by OpenSSL 3 (Node.js >=17, statically linked) when app
	# or dependency code uses a cryptographic algorithm/digest OpenSSL 3 no longer supports by
	# default.
	if grep -q "ERR_OSSL_EVP_UNSUPPORTED" "${log_file}"; then
		local solution help_url=""

		# Webpack's default chunk/module id hash function is one such unsupported algorithm, so
		# this more specific case gets its own id and fix.
		if grep -q "\[webpack-cli\] Error" "${log_file}"; then
			__failure["id"]="openssl-unsupported-algorithm-webpack"
			solution="If this app uses Webpack 5.54.0+, you can change the Webpack configuration to use a different
\`output.hashFunction\` like \`xxhash64\`. Older versions of Webpack should configure a custom
\`output.hashFunction\` that uses supported cryptographic algorithms."
			help_url="https://webpack.js.org/configuration/output/#outputhashfunction"
		else
			__failure["id"]="openssl-unsupported-algorithm"
			solution="To fix this, update any dependencies that may be causing the issue and identify and update application code
that uses deprecated or unsupported cryptographic algorithms to use modern, secure alternatives."
		fi

		__failure["classification"]="user"
		__failure["message"]=$(
			cat <<-EOF
				Unsupported cryptographic algorithm used

				This error frequently occurs in apps upgrading from older versions of Node.js (<17.x) which is statically
				compiled against OpenSSL v1 to newer versions of Node.js (>=17.x) which is statically compiled against
				OpenSSL v3.

				${solution}

				If this is not possible, a temporary workaround can be done by setting a config var that re-enables support
				for legacy algorithms using \`heroku config set NODE_OPTIONS=--openssl-legacy-provider\`. Please note, this
				is not recommended for production environments.
			EOF
		)
		if [[ -n "${help_url}" ]]; then
			__failure["message"]="${__failure["message"]}
${help_url}"
		fi
		return 0
	fi

	# Node.js heap exhaustion — most commonly hit during asset-bundler steps (Webpack, Vite,
	# Rollup) running with excessive concurrency for the dyno's available memory.
	if grep -q "JavaScript heap out of memory" "${log_file}"; then
		__failure["id"]="node-out-of-memory"
		__failure["classification"]="user"
		__failure["message"]=$(
			cat <<-EOF
				Node.js Out-Of-Memory (OOM)

				This error can occur due to several reasons (large data handling, memory leaks, etc.) but the most
				common reason during a build is excessive concurrent operations from asset bundlers like
				Webpack, Vite, or Rollup. Your asset bundler configuration may include plugins to perform tasks such
				as minification or compilation using multiple parallel processes. In containerized environments,
				default settings for these tools may not be appropriate.

				If you are getting this error during asset compilation, check which plugins you have enabled and
				consult their documentation for configuration related to concurrent or parallel operations and
				either disable or set lower limits.

				As a temporary workaround, it's also possible to increase the memory limits of your Node.js process
				by prepending \`NODE_OPTIONS="--max-old-space-size=VALUE_IN_MB"\` to the failing script.
				For example, \`NODE_OPTIONS="--max-old-space-size=4096"\` would set a limit of 4GB. This should
				be done with caution as it doesn't solve the underlying issue of why this build requires higher
				memory limits.
			EOF
		)
		return 0
	fi

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

function package_manager::_run_if_present() {
	local build_dir=${1:-}
	local script_name=${2:-}
	local has_script_name

	has_script_name=$(utils::package_json::has_script "${build_dir}/package.json" "${script_name}")

	if [[ "${has_script_name}" == "true" ]]; then
		package_manager::_dispatch_run_script "${build_dir}" "${script_name}"
	fi
}

function package_manager::_run_build_if_present() {
	local build_dir=${1:-}
	local script_name=${2:-}
	local has_script_name
	local script

	has_script_name=$(utils::package_json::has_script "${build_dir}/package.json" "${script_name}")
	script=$(utils::json::read "${build_dir}/package.json" ".scripts[\"${script_name}\"]")

	if [[ "${script}" == "ng build" ]]; then
		output::warning <<-EOF
			"ng build" detected as build script. We recommend you use \`ng build --prod\` or add \`--prod\` to your build flags. See https://devcenter.heroku.com/articles/nodejs-support#build-flags

			https://devcenter.heroku.com/articles/nodejs-support
		EOF
	fi

	if [[ "${has_script_name}" == "true" ]]; then
		# NODE_BUILD_FLAGS is a global exported by the caller (bin/compile); only the build script
		# receives it.
		# shellcheck disable=SC2154 # set by the caller (bin/compile)
		package_manager::_dispatch_run_script "${build_dir}" "${script_name}" "${NODE_BUILD_FLAGS:-}"
	fi
}

function package_manager::run_prebuild_script() {
	local build_dir=${1:-}
	local has_heroku_prebuild_script

	has_heroku_prebuild_script=$(utils::package_json::has_script "${build_dir}/package.json" "heroku-prebuild")

	if [[ "${has_heroku_prebuild_script}" == "true" ]]; then
		header "Prebuild"
		package_manager::_run_if_present "${build_dir}" 'heroku-prebuild'
	fi
}

function package_manager::run_build_script() {
	local build_dir=${1:-}
	local has_build_script has_heroku_build_script

	has_build_script=$(utils::package_json::has_script "${build_dir}/package.json" "build")
	has_heroku_build_script=$(utils::package_json::has_script "${build_dir}/package.json" "heroku-postbuild")
	if [[ "${has_heroku_build_script}" == "true" ]] && [[ "${has_build_script}" == "true" ]]; then
		echo "Detected both \"build\" and \"heroku-postbuild\" scripts"
		package_manager::_run_if_present "${build_dir}" 'heroku-postbuild'
	elif [[ "${has_heroku_build_script}" == "true" ]]; then
		package_manager::_run_if_present "${build_dir}" 'heroku-postbuild'
	elif [[ "${has_build_script}" == "true" ]]; then
		package_manager::_run_build_if_present "${build_dir}" 'build'
	fi
}

function package_manager::run_cleanup_script() {
	local build_dir=${1:-}
	local has_heroku_cleanup_script

	has_heroku_cleanup_script=$(utils::package_json::has_script "${build_dir}/package.json" "heroku-cleanup")

	if [[ "${has_heroku_cleanup_script}" == "true" ]]; then
		header "Cleanup"
		package_manager::_run_if_present "${build_dir}" 'heroku-cleanup'
	fi
}

# Pre-flight guard run before any package manager is selected: fails the build when the
# application has committed lockfiles for more than one package manager, or a modern lockfile
# alongside npm-shrinkwrap.json. Reads the filesystem directly and, when it detects a problem,
# delegates to the emit-at-site helper for that case (mirrors runtimes::nodejs::_fail_*). Both
# cases are the app's fault (classification=user).
function package_manager::fail_multiple_lockfiles() {
	local build_dir="${1:-}"
	local has_modern_lockfile=false

	local -A lockfiles=(
		["npm"]="package-lock.json"
		["pnpm"]="pnpm-lock.yaml"
		["Yarn"]="yarn.lock"
	)

	local package_manager lockfile
	local detected_package_managers=()
	for package_manager in "${!lockfiles[@]}"; do
		lockfile="${lockfiles["${package_manager}"]}"
		if [[ -f "${build_dir}/${lockfile}" ]]; then
			has_modern_lockfile=true
			detected_package_managers+=("${package_manager}")
		fi
	done

	# Sort the detected managers case-insensitively so the reported list, per-manager fix steps,
	# and the recorded failure_detail all have a stable order (npm, pnpm, Yarn) regardless of
	# associative-array iteration order.
	local -a package_managers_sorted=()
	if ((${#detected_package_managers[*]} > 0)); then
		# shellcheck disable=SC2312 # sort orders the NUL-delimited names; masking its exit is intentional (matches pre-migration behavior)
		readarray -td '' package_managers_sorted < <(printf '%s\0' "${detected_package_managers[@]}" | sort -z --ignore-case)
	fi

	if ((${#package_managers_sorted[*]} > 1)); then
		package_manager::_fail_multiple_lockfiles "${package_managers_sorted[@]}"
	fi

	if ${has_modern_lockfile} && [[ -f "${build_dir}/npm-shrinkwrap.json" ]]; then
		package_manager::_fail_shrinkwrap_conflict "${package_managers_sorted[@]}"
	fi
}

# Emits the classified failure for multiple modern lockfiles present at once and exits. Called
# directly at the failure site (see runtimes::nodejs::_fail_node_download for the direct-emit
# rationale). Receives the detected package-manager names, already sorted, and interpolates them
# into both the reported list and the per-manager `git rm` fix steps. Keeps the historical
# `multiple-lock-files` failure id for metric continuity.
function package_manager::_fail_multiple_lockfiles() {
	local -a package_managers_sorted=("$@")

	local -A lockfiles=(
		["npm"]="package-lock.json"
		["pnpm"]="pnpm-lock.yaml"
		["Yarn"]="yarn.lock"
	)

	local pm_list
	pm_list=$(
		IFS=','
		printf '%s' "${package_managers_sorted[*]}"
	)

	# Build the per-manager fix steps once here (rather than inline in the heredoc) so the
	# subshell's exit code isn't masked by the surrounding command substitution.
	local fix_steps
	fix_steps=$(package_manager::_multiple_lockfiles_fix_steps "${package_managers_sorted[@]}")

	local -A failure
	failure["id"]="multiple-lock-files"
	failure["classification"]="user"
	failure["detail"]="${pm_list}"
	failure["message"]=$(
		cat <<-EOF
			Error: Multiple lockfiles found.

			Multiple package managers (${pm_list}) have created lockfiles for this application,
			but only one can be used to install dependencies. This usually happens when a project standardizes on one
			package manager, but a dependency is later added with a different one and the extra lockfile is committed.
			Installing dependencies with the wrong package manager can result in missing packages or subtle, hard to
			debug bugs in production.

			Only one of the following package manager lockfiles is supported at a time:
			- ${lockfiles["npm"]} (npm)
			- ${lockfiles["Yarn"]} (Yarn)
			- ${lockfiles["pnpm"]} (pnpm)

			Keep the lockfile for the package manager you use and delete the rest, then commit and redeploy:

			${fix_steps}

			To stop the extra lockfiles from being committed again, add them to your .gitignore file.
		EOF
	)
	failure::emit failure
}

# Pre-flight guard: fails the build when the app declares more than one package manager in
# package.json, via the engines.npm/engines.yarn/engines.pnpm fields and/or the packageManager
# field. Installing dependencies with the wrong package manager can cause missing packages or
# subtle production bugs, so exactly one may be declared. Collects the distinct package managers
# named (associative-array keys dedupe them) alongside a human-readable descriptor of each
# declaration; if more than one distinct manager is named, hands off to the emit-at-site helper
# (which prints the message, records build data, and exits).
function package_manager::fail_conflicting_metadata() {
	local build_dir="${1}"

	local npm_engine yarn_engine pnpm_engine package_manager
	npm_engine=$(utils::json::read "${build_dir}/package.json" ".engines.npm")
	yarn_engine=$(utils::json::read "${build_dir}/package.json" ".engines.yarn")
	pnpm_engine=$(utils::json::read "${build_dir}/package.json" ".engines.pnpm")
	package_manager=$(utils::json::read "${build_dir}/package.json" ".packageManager")

	local -A package_managers
	local -a fields_detected=()

	if [[ -n "${npm_engine}" ]]; then
		package_managers["npm"]=1
		fields_detected+=("npm version detected in engines.npm (${npm_engine})")
	fi

	if [[ -n "${yarn_engine}" ]]; then
		package_managers["yarn"]=1
		fields_detected+=("yarn version declared in engines.yarn (${yarn_engine})")
	fi

	if [[ -n "${pnpm_engine}" ]]; then
		package_managers["pnpm"]=1
		fields_detected+=("pnpm version declared in engines.pnpm (${pnpm_engine})")
	fi

	if [[ "${package_manager}" == yarn* ]]; then
		package_managers["yarn"]=1
		fields_detected+=("yarn version declared in packageManager (${package_manager})")
	elif [[ "${package_manager}" == pnpm* ]]; then
		package_managers["pnpm"]=1
		fields_detected+=("pnpm version declared in packageManager (${package_manager})")
	fi

	if ((${#package_managers[@]} > 1)); then
		package_manager::_fail_conflicting_metadata "${fields_detected[@]}"
	fi
}

# Emits the classified failure for an app that declares more than one package manager in
# package.json. Keeps the historical `multiple-package-managers` failure id for metric
# continuity. Classified `user` — the app controls package.json. Receives one descriptor per
# detected declaration (from the guard above) and renders them into both the message and the
# build-data detail. See runtimes::nodejs::_fail_node_download for why this emits directly at
# the call site.
function package_manager::_fail_conflicting_metadata() {
	local fields_detected=("$@")

	local fields_block
	fields_block=$(printf -- '- %s\n' "${fields_detected[@]}")

	local -A failure
	failure["id"]="multiple-package-managers"
	failure["classification"]="user"
	failure["detail"]=$(
		IFS=,
		echo "${fields_detected[*]}"
	)
	failure["message"]=$(
		cat <<-EOF
			Multiple package managers declared in package.json

			Installing dependencies using the wrong package manager can result in missing packages or subtle bugs
			in production. Only one of the following fields should be used, all others should be removed:

			${fields_block}
		EOF
	)
	failure::emit failure
}

# Emits the classified failure for a modern lockfile present alongside npm-shrinkwrap.json and
# exits. See runtimes::nodejs::_fail_node_download for the direct-emit rationale. Receives the
# detected package-manager names (already sorted) so the recorded detail names which modern
# lockfile(s) conflicted with the shrinkwrap file. Keeps the historical
# `shrinkwrap-lock-file-conflict` failure id for metric continuity.
function package_manager::_fail_shrinkwrap_conflict() {
	local -a package_managers_sorted=("$@")

	local pm_list
	pm_list=$(
		IFS=','
		printf '%s' "${package_managers_sorted[*]}"
	)

	local -A failure
	failure["id"]="shrinkwrap-lock-file-conflict"
	failure["classification"]="user"
	failure["detail"]="${pm_list}"
	failure["message"]=$(
		cat <<-EOF
			Error: Multiple lockfiles conflicting with npm-shrinkwrap.json.

			Your application has multiple lockfiles defined which conflicts with the
			shrinkwrap file you've been using. Only one lockfile can be used
			to install dependencies. Installing dependencies using the wrong lockfile
			can result in missing packages or subtle bugs in production.

			Please make sure there is only one of the following files in your
			application directory, then commit and redeploy:

			- yarn.lock
			- pnpm-lock.yaml
			- package-lock.json
			- npm-shrinkwrap.json

			To stop the extra lockfiles from being committed again, add them to your .gitignore file.
		EOF
	)
	failure::emit failure
}

# Builds the "keep one, remove the rest" fix instructions for a multiple-lockfiles error.
# Given the detected package manager names as arguments (e.g. "npm" "pnpm" "Yarn"), it prints
# one block per package manager listing the exact `git rm` command needed to remove the other
# lockfiles, so the advice is specific to the lockfiles actually present in the application.
# Pure helper (no side effects); the output order follows the caller-passed argument order.
function package_manager::_multiple_lockfiles_fix_steps() {
	local managers=("$@")

	local -A lockfiles=(
		["npm"]="package-lock.json"
		["pnpm"]="pnpm-lock.yaml"
		["Yarn"]="yarn.lock"
	)

	local keep other remove
	for keep in "${managers[@]}"; do
		remove=()
		for other in "${managers[@]}"; do
			if [[ "${other}" != "${keep}" ]]; then
				remove+=("${lockfiles["${other}"]}")
			fi
		done

		echo "       If you use ${keep}:"
		echo "       \$ git rm ${remove[*]}"
		echo "       \$ git commit -m \"Remove unused lockfiles\""
		echo "       \$ git push heroku main"
		echo ""
	done
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__package_manager_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__package_manager_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__package_manager_saved_pipefail}"
unset __package_manager_saved_flags __package_manager_saved_pipefail
