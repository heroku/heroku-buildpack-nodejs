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
	if ! suppress_output npm install "${unsafe_perm[@]}" --quiet --no-audit --no-progress -g "pnpm@${version}"; then
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
	suppress_output pnpm --version
	# shellcheck disable=SC2312 # the preceding suppress_output already verified pnpm works, so masking its exit here is intentional (matches pre-migration behavior)
	echo "Using pnpm $(pnpm --version)"
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__pnpm_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__pnpm_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__pnpm_saved_pipefail}"
unset __pnpm_saved_flags __pnpm_saved_pipefail
