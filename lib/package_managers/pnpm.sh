#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. The
# caller's flags are read from `$-` (the current shell); a `$(set +o)` capture runs in a
# command-substitution subshell where bash always forces errexit off, so it would later
# restore errexit as disabled even when the caller had it on. pipefail has no `$-` letter, so
# it is captured separately (it is reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__pnpm_saved_flags="$-"
__pnpm_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

package_managers::pnpm::install_dependencies() {
	local build_dir=${1:-}
	local cache_dir=${2:-}

	echo "Running 'pnpm install' with pnpm-lock.yaml"
	cd "${build_dir}" || return

	pnpm_install_args=("install" "--prod=false" "--frozen-lockfile")

	if [[ -n "${PNPM_INSTALL_REPORTER}" ]]; then
		case "${PNPM_INSTALL_REPORTER}" in
			default | ndjson | append-only | silent)
				pnpm_install_args+=("--reporter=${PNPM_INSTALL_REPORTER}")
				;;
			*)
				echo "Warning: Invalid PNPM_INSTALL_REPORTER value '${PNPM_INSTALL_REPORTER}'. Valid values: default, ndjson, append-only, silent"
				echo "Proceeding with default reporter"
				;;
		esac
	fi

	monitor "install_dependencies" pnpm "${pnpm_install_args[@]}" 2>&1

	# prune the store when the counter reaches zero to clean up errant package versions which may have been upgraded/removed
	counter=$(load_pnpm_prune_store_counter "${cache_dir}")
	if ((counter == 0)); then
		echo "Cleaning up pnpm store"
		# pnpm <9.12.0 errors with `ENOENT: ... scandir '<store>/v*/files'`
		# when the store has no fetched package files (e.g. an install with
		# no external dependencies), because pnpm only creates that
		# directory on first download. Treat any ENOENT-on-scandir of the
		# store's `vN/files` directory during prune as a benign empty-store
		# no-op; surface every other failure so we don't mask unrelated
		# prune errors. Fixed upstream in pnpm/pnpm#8555.
		# TODO: remove when minimum supported pnpm is >= 9.12.0.
		local prune_output prune_exit=0
		prune_output=$(mktemp)
		# shellcheck disable=SC2064 # expand prune_output now so the RETURN trap removes this exact temp file
		trap "rm -f '${prune_output}' >/dev/null" RETURN
		pnpm store prune >"${prune_output}" 2>&1 || prune_exit=$?
		if ((prune_exit != 0)) && ! grep -qE "ENOENT.*scandir" "${prune_output}"; then
			cat "${prune_output}"
			return "${prune_exit}"
		fi
	fi
	save_pnpm_prune_store_counter "${cache_dir}" "$((counter - 1))"
}

function package_managers::pnpm::prune_devdependencies() {
	local build_dir=${1:-}

	cd "${build_dir}" || return

	# NODE_ENV and PNPM_SKIP_PRUNING are globals exported by the caller (bin/compile via
	# lib/environment.sh / the app's config vars).
	# shellcheck disable=SC2154 # set by the caller (bin/compile)
	if [[ "${NODE_ENV}" == "test" ]]; then
		echo "Skipping because NODE_ENV is 'test'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	elif [[ "${NODE_ENV}" != "production" ]]; then
		echo "Skipping because NODE_ENV is not 'production'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	elif [[ "${PNPM_SKIP_PRUNING}" == "true" ]]; then
		echo "Skipping because PNPM_SKIP_PRUNING is '${PNPM_SKIP_PRUNING}'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	fi

	local workspace_configured
	# shellcheck disable=SC2312 # package_managers::pnpm::_workspace_configured echoes the boolean; masking its exit is intentional (matches pre-migration behavior)
	workspace_configured=$(package_managers::pnpm::_workspace_configured "${build_dir}")
	if [[ "${workspace_configured}" == "true" ]]; then
		# Get pnpm projects
		local project_paths
		# shellcheck disable=SC2312 # package_managers::pnpm::_list_workspace_projects streams the project list; its exit is not consulted (matches pre-migration behavior)
		mapfile -t project_paths < <(package_managers::pnpm::_list_workspace_projects)
		# Check if any projects contain lifecycle scripts, and skip pruning if true
		local project_path
		for project_path in "${project_paths[@]}"; do
			# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
			if package_managers::pnpm::_has_lifecycle_script "${project_path}/package.json"; then
				warn_skipping_unsafe_pnpm_workspace_prune "${project_path}"
				build_data::set_raw "skipped_prune" "true"
				return 0
			fi
		done
		# Remove node_modules from each project
		for project_path in "${project_paths[@]}"; do
			rm -rf "${project_path}/node_modules"
		done
		# Reinstall with production-only dependencies
		monitor "prune_dev_dependencies" pnpm install --prod --frozen-lockfile 2>&1
		build_data::set_raw "skipped_prune" "false"
		return 0
	fi

	local pnpm_version pnpm_major_version pnpm_minor_version pnpm_patch_version
	pnpm_version=$(pnpm --version)
	pnpm_major_version=$(echo "${pnpm_version}" | cut -d "." -f 1)
	pnpm_minor_version=$(echo "${pnpm_version}" | cut -d "." -f 2)
	pnpm_patch_version=$(echo "${pnpm_version}" | cut -d "." -f 3)

	local pnpm_prune_args=("prune" "--prod")

	# prior to 8.15.6, pnpm prune would execute lifecycle scripts such as `preinstall` and `postinstall`
	# so we should check if we're on that version + there are lifecycle scripts registered and, if so,
	# we'll let the user know that pruning can't be done safely so we're skipping it
	if ((pnpm_major_version < 8)) \
		|| ((pnpm_major_version == 8 && pnpm_minor_version < 15)) \
		|| ((pnpm_major_version == 8 && pnpm_minor_version == 15 && pnpm_patch_version < 6)); then
		# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
		if package_managers::pnpm::_has_lifecycle_script "${build_dir}/package.json"; then
			warn_skipping_unsafe_pnpm_prune "${pnpm_version}"
			build_data::set_raw "skipped_prune" "true"
			return
		fi
	else
		# we're on a version that supports this flag (8.15.6 and higher)
		pnpm_prune_args+=("--ignore-scripts")
	fi

	monitor "prune_dev_dependencies" pnpm "${pnpm_prune_args[@]}" 2>&1

	build_data::set_raw "skipped_prune" "false"
}

function package_managers::pnpm::_workspace_configured() {
	local build_dir=${1:-}
	local workspace_file="${build_dir}/pnpm-workspace.yaml"
	local result

	if [[ -f "${workspace_file}" ]]; then
		# prior to pnpm 10.5.0, the `packages` key was mandatory, but now, you can store
		# other pnpm-related config settings in `pnpm-workspace.yaml`.
		result=$(read_yaml "${workspace_file}" '.packages')

		if [[ -n "${result}" && "${result}" != "null" ]]; then
			echo "true"
			return
		fi
	fi

	echo "false"
}

function package_managers::pnpm::_has_lifecycle_script() {
	local package_json=$1
	# the following are lifecycle scripts that will execute on install/prune by pnpm
	[[ -f "${package_json}" ]] \
		&& jq -e '.scripts | (has("pnpm:devPreinstall") or has("preinstall") or has("install") or has("postinstall") or has("prepare"))' \
			"${package_json}" >/dev/null 2>&1
}

function package_managers::pnpm::_list_workspace_projects() {
	pnpm list --recursive --json --depth -1 2>/dev/null | jq -r '.[].path'
}

function package_managers::pnpm::install_binary() {
	local version="$1"
	echo "Downloading and installing pnpm (${version})"
	# npm 12 removed the --unsafe-perm flag and rejects it with EUNKNOWNCONFIG, so only pass it
	# to the currently-active npm when that npm still accepts it.
	local unsafe_perm=()
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside; a non-match just omits the flag
	if package_managers::npm::supports_unsafe_perm; then
		unsafe_perm=(--unsafe-perm)
	fi
	if ! utils::command::suppress_output npm install "${unsafe_perm[@]}" --quiet --no-audit --no-progress -g "pnpm@${version}"; then
		build_data::set_string "failure" "pnpm-install-failed"
		output::error <<-EOF
			Unable to install pnpm ${version}.
			Does pnpm ${version} exist? (https://help.heroku.com/8MEL050H)
			Is ${version} valid semver? (https://help.heroku.com/0ZIOF3ST)
			Is pnpm ${version} compatible with this Node.js version?
		EOF
		false
	fi
	# Verify pnpm works before capturing and ensure its stderr is inspectable later
	utils::command::suppress_output pnpm --version
	# shellcheck disable=SC2312 # the preceding utils::command::suppress_output already verified pnpm works, so masking its exit here is intentional (matches pre-migration behavior)
	echo "Using pnpm $(pnpm --version)"
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__pnpm_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__pnpm_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__pnpm_saved_pipefail}"
unset __pnpm_saved_flags __pnpm_saved_pipefail
