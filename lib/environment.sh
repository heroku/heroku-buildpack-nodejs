#!/usr/bin/env bash

# Enable strict mode for ShellCheck's benefit, but restore the caller's options at the end of
# the file (see epilogue) so these don't bleed into the un-migrated scripts that source this
# lib. The caller's flags are read from `$-`, which reflects the *current* shell — a
# `$(set +o)` capture runs in a command-substitution subshell where bash always forces errexit
# off, so it would record (and later restore) errexit as disabled even when the caller had it
# enabled. `$-` has no letter for pipefail, so that one option is captured separately (it is
# reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__environment_saved_flags="$-"
__environment_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

environment::get_os() {
	uname | tr '[:upper:]' '[:lower:]'
}

environment::create_default_env() {
	local YARN="${1}"

	export NPM_CONFIG_LOGLEVEL=${NPM_CONFIG_LOGLEVEL:-error}
	export NODE_MODULES_CACHE=${NODE_MODULES_CACHE:-true}
	export NODE_ENV=${NODE_ENV:-production}
	export NODE_VERBOSE=${NODE_VERBOSE:-false}

	if "${YARN}"; then
		export USE_YARN_CACHE=${USE_YARN_CACHE:-true}
	fi

	if [[ -n "${USE_NPM_INSTALL:-}" ]]; then
		export USE_NPM_INSTALL=${USE_NPM_INSTALL}
	fi
}

environment::create_build_env() {
	# if the user hasn't set NODE_OPTIONS, increase the default amount of space
	# that a node process can address to match that of the build dynos (2.5GB)
	if [[ -z "${NODE_OPTIONS:-}" ]]; then
		export NODE_OPTIONS="--max_old_space_size=2560"
	fi
}

environment::list_node_config() {
	# Pure informational output (env dump + notes); indent the whole body under the caller's
	# `output::step` so the call site can invoke this bare, like the other migrated steps.
	{
		echo ""
		printenv | grep ^NPM_CONFIG_ || true
		printenv | grep ^YARN_ || true
		printenv | grep ^USE_NPM_ || true
		printenv | grep ^USE_YARN_ || true
		printenv | grep ^NODE_ || true

		if [[ "${NPM_CONFIG_PRODUCTION:-}" = "true" ]] && [[ "${NODE_ENV:-}" != "production" ]]; then
			echo ""
			echo "npm scripts will see NODE_ENV=production (not '${NODE_ENV:-}')"
			echo "https://docs.npmjs.com/misc/config#production"
		fi
	} | output::indent
}

environment::export_env_dir() {
	local env_dir="${1}"
	if [[ -d "${env_dir}" ]]; then
		local whitelist_regex=${2:-''}
		local blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH|LANG|BUILD_DIR)$'}
		# shellcheck disable=SC2164
		pushd "${env_dir}" >/dev/null
		for e in *; do
			[[ -e "${e}" ]] || continue
			echo "${e}" | grep -E "${whitelist_regex}" | grep -qvE "${blacklist_regex}" \
				&& export "${e}=$(cat "${e}")"
			:
		done
		# shellcheck disable=SC2164
		popd >/dev/null
	fi
}

environment::write_profile() {
	local bp_dir="${1}"
	local build_dir="${2}"
	mkdir -p "${build_dir}/.profile.d"
	cp "${bp_dir}"/profile/* "${build_dir}/.profile.d/"
}

environment::write_ci_profile() {
	local bp_dir="${1}"
	local build_dir="${2}"
	environment::write_profile "${1}" "${2}"
	cp "${bp_dir}"/ci-profile/* "${build_dir}/.profile.d/"
}

environment::write_export() {
	local bp_dir="${1}"
	local build_dir="${2}"

	# only write the export script if the buildpack directory is writable.
	# this may occur in situations outside of Heroku, such as running the
	# buildpacks locally.
	if [[ -w "${bp_dir}" ]]; then
		echo "export PATH=\"${build_dir}/.heroku/node/bin:${build_dir}/.heroku/yarn/bin:\$PATH:${build_dir}/node_modules/.bin\"" >"${bp_dir}/export"
		echo "export NODE_HOME=\"${build_dir}/.heroku/node\"" >>"${bp_dir}/export"
		# shellcheck disable=SC2016
		echo 'export NODE_OPTIONS=${NODE_OPTIONS:-"--max_old_space_size=2560"}' >>"${bp_dir}/export"
	fi
}

# Restore the sourcing shell's original options (see preamble) so strict mode doesn't leak
# into un-migrated callers. errexit/nounset come from the saved `$-`; pipefail from its own
# saved `set +o` line.
case "${__environment_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__environment_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__environment_saved_pipefail}"
unset __environment_saved_flags __environment_saved_pipefail
