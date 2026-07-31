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
# package managers (the per-PM modules only spell the command). The captured log is where a
# future call-site classifier will inspect known build-script failures (e.g. the OpenSSL
# unsupported-algorithm error); today the only handled case is a pipe failure, and every other
# failure bubbles up so the legacy ERR trap's `log_other_failures` classifies it from $LOG_FILE.
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

		if [[ "${tool_exit}" -eq 0 ]]; then
			# The script succeeded but the pipeline failed (tee couldn't write the log — e.g. out
			# of disk). Buildpack-side, so report it directly rather than blaming the app.
			package_manager::_handle_script_pipefail "${pipe_status[*]}"
		fi

		# No known build-script failure mode is classified at this call site yet (OSSL, OOM, and
		# the other build-script matchers still live in the legacy `log_other_failures` trap,
		# which classifies from $LOG_FILE). Bubble the tool's exit code so the pipeline that runs
		# this script fails under errexit/pipefail, the legacy ERR trap fires, and it classifies
		# the failure — instead of masking it with a generic message.
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

function package_manager::_run_if_present() {
	local build_dir=${1:-}
	local script_name=${2:-}
	local has_script_name

	has_script_name=$(has_script "${build_dir}/package.json" "${script_name}")

	if [[ "${has_script_name}" == "true" ]]; then
		package_manager::_dispatch_run_script "${build_dir}" "${script_name}"
	fi
}

function package_manager::_run_build_if_present() {
	local build_dir=${1:-}
	local script_name=${2:-}
	local has_script_name
	local script

	has_script_name=$(has_script "${build_dir}/package.json" "${script_name}")
	script=$(read_json "${build_dir}/package.json" ".scripts[\"${script_name}\"]")

	if [[ "${script}" == "ng build" ]]; then
		warn "\"ng build\" detected as build script. We recommend you use \`ng build --prod\` or add \`--prod\` to your build flags. See https://devcenter.heroku.com/articles/nodejs-support#build-flags"
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

	has_heroku_prebuild_script=$(has_script "${build_dir}/package.json" "heroku-prebuild")

	if [[ "${has_heroku_prebuild_script}" == "true" ]]; then
		header "Prebuild"
		package_manager::_run_if_present "${build_dir}" 'heroku-prebuild'
	fi
}

function package_manager::run_build_script() {
	local build_dir=${1:-}
	local has_build_script has_heroku_build_script

	has_build_script=$(has_script "${build_dir}/package.json" "build")
	has_heroku_build_script=$(has_script "${build_dir}/package.json" "heroku-postbuild")
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

	has_heroku_cleanup_script=$(has_script "${build_dir}/package.json" "heroku-cleanup")

	if [[ "${has_heroku_cleanup_script}" == "true" ]]; then
		header "Cleanup"
		package_manager::_run_if_present "${build_dir}" 'heroku-cleanup'
	fi
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__package_manager_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__package_manager_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__package_manager_saved_pipefail}"
unset __package_manager_saved_flags __package_manager_saved_pipefail
