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

function package_manager::_run_if_present() {
	local build_dir=${1:-}
	local script_name=${2:-}
	local has_script_name
	local script

	has_script_name=$(has_script "${build_dir}/package.json" "${script_name}")
	script=$(read_json "${build_dir}/package.json" ".scripts[\"${script_name}\"]")
	monitor_name="${script_name//[^[:alnum:]]/_}_script"

	if [[ "${has_script_name}" == "true" ]]; then
		# YARN, YARN_2, and PNPM are globals exported by the caller (bin/compile).
		# shellcheck disable=SC2154 # set by the caller (bin/compile)
		if ${YARN} || ${YARN_2}; then
			echo "Running ${script_name} (yarn)"
			# yarn will throw an error if the script is an empty string, so check for this case
			if [[ -n "${script}" ]]; then
				monitor "${monitor_name}" yarn run "${script_name}"
			fi
		elif ${PNPM}; then
			echo "Running ${script_name}"
			monitor "${monitor_name}" pnpm run --if-present "${script_name}"
		else
			echo "Running ${script_name}"
			monitor "${monitor_name}" npm run "${script_name}" --if-present
		fi
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
		# YARN, YARN_2, PNPM, and NODE_BUILD_FLAGS are globals exported by the caller (bin/compile).
		# shellcheck disable=SC2154 # set by the caller (bin/compile)
		if ${YARN} || ${YARN_2}; then
			echo "Running ${script_name} (yarn)"
			# yarn will throw an error if the script is an empty string, so check for this case
			if [[ -n "${script}" ]]; then
				if [[ -n ${NODE_BUILD_FLAGS} ]]; then
					echo "Running with ${NODE_BUILD_FLAGS} flags"
					monitor "build_script" yarn run "${script_name}" "${NODE_BUILD_FLAGS}"
				else
					monitor "build_script" yarn run "${script_name}"
				fi
			fi
		elif ${PNPM}; then
			echo "Running ${script_name}"
			if [[ -n ${NODE_BUILD_FLAGS} ]]; then
				echo "Running with ${NODE_BUILD_FLAGS} flags"
				monitor "build_script" pnpm run --if-present "${script_name}" -- "${NODE_BUILD_FLAGS}"
			else
				monitor "build_script" pnpm run --if-present "${script_name}"
			fi
		else
			echo "Running ${script_name}"
			if [[ -n ${NODE_BUILD_FLAGS} ]]; then
				echo "Running with ${NODE_BUILD_FLAGS} flags"
				monitor "build_script" npm run "${script_name}" --if-present -- "${NODE_BUILD_FLAGS}"
			else
				monitor "build_script" npm run "${script_name}" --if-present
			fi
		fi
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
