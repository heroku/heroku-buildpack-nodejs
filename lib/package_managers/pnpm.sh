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

	output::info "Running 'pnpm install' with pnpm-lock.yaml"
	cd "${build_dir}" || return

	pnpm_install_args=("install" "--prod=false" "--frozen-lockfile")

	if [[ -n "${PNPM_INSTALL_REPORTER}" ]]; then
		case "${PNPM_INSTALL_REPORTER}" in
			default | ndjson | append-only | silent)
				pnpm_install_args+=("--reporter=${PNPM_INSTALL_REPORTER}")
				;;
			*)
				output::info "Warning: Invalid PNPM_INSTALL_REPORTER value '${PNPM_INSTALL_REPORTER}'. Valid values: default, ndjson, append-only, silent"
				output::info "Proceeding with default reporter"
				;;
		esac
	fi

	local log_file
	log_file=$(mktemp)

	local start
	start=$(build_data::current_unix_realtime)

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves.
	# pnpm writes progress and errors across stdout+stderr; merge them with `2>&1`, pass the
	# merged stream through `tee` for classification, and indent it with `output::indent`.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { pnpm "${pnpm_install_args[@]}" 2>&1 | tee "${log_file}" | output::indent; }; then
		# Capture the full pipe status first (before any other command clobbers PIPESTATUS).
		# The pipeline is `pnpm 2>&1 | tee | output::indent`, so [0] is pnpm's exit code (tee is [1], output::indent [2]).
		local pipe_status=("${PIPESTATUS[@]}")
		local pnpm_exit="${pipe_status[0]}"
		build_data::set_duration "install_dependencies_time" "${start}"

		local -A failure
		# shellcheck disable=SC2310 # the elif calls a function in a condition, so set -e is disabled inside
		if [[ "${pnpm_exit}" -eq 0 ]]; then
			# pnpm succeeded but the pipeline failed (tee couldn't write the log — e.g. out of
			# disk). Buildpack-side, so don't run it through the pnpm classifier.
			package_managers::pnpm::_handle_install_pipefail "${pipe_status[*]}"
		elif failure::handle_git_auth_failure "${log_file}" failure; then
			# A private git+ssh dependency failed SSH host-key verification. This is a
			# cross-cutting git-layer failure (every package manager shells out to git), so it is
			# classified before the pnpm-specific matcher below.
			failure::emit failure
		elif package_managers::pnpm::_handle_install_failure "${log_file}" failure; then
			# The classifier fills `failure` by nameref and returns 0 on a match. It is invoked
			# directly in the `elif` condition (not wrapped in `$(...)`) so its writes survive — a
			# command substitution runs in a subshell where the nameref updates would be lost.
			failure::emit failure
		elif failure::handle_econnreset "${log_file}" failure; then
			# A network connection was reset. This is a cross-cutting network-layer failure
			# (every package manager can hit it). Checked last, as a fallback after the
			# pnpm-specific matcher above.
			failure::emit failure
		elif failure::handle_libc6_incompatibility "${log_file}" failure; then
			# The Node.js binary itself is incompatible with the current stack's glibc. This is a
			# cross-cutting runtime-layer failure (not a pnpm error code). Checked last, as a
			# fallback after the pnpm-specific matcher above.
			failure::emit failure
		fi

		# No known failure mode recognised. Bubble up by returning pnpm's exit code: the bare
		# `build_dependencies` call in bin/compile then fails under errexit and the generic
		# failure::handle_uncaught ERR trap records it as failure=internal-error — covering the
		# pnpm codes not yet migrated here.
		return "${pnpm_exit}"
	fi

	build_data::set_duration "install_dependencies_time" "${start}"

	# prune the store when the counter reaches zero to clean up errant package versions which may have been upgraded/removed
	counter=$(cache::load_pnpm_prune_store_counter "${cache_dir}")
	if ((counter == 0)); then
		output::info "Cleaning up pnpm store"
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
			output::indent <"${prune_output}"
			return "${prune_exit}"
		fi
	fi
	cache::save_pnpm_prune_store_counter "${cache_dir}" "$((counter - 1))"
}

# Emits the pnpm-install pipefail failure for the case where pnpm exited 0 but a downstream
# pipe stage (typically `tee` writing to the log) failed — for example the build ran out of
# disk space. Wraps `failure::handle_pipefail` with the pnpm-specific id and message so callers
# pass only the joined PIPESTATUS string.
function package_managers::pnpm::_handle_install_pipefail() {
	local pipe_status_str="${1}"
	local message
	message=$(
		cat <<-EOF
			Error: Unable to capture the pnpm install log output.

			The dependency install ran, but writing its log to disk failed (for example,
			the build ran out of disk space). This is not a problem with your
			dependencies. Please try again.
		EOF
	)
	failure::handle_pipefail "pnpm-install-pipefail" "${pipe_status_str}" "${message}"
}

# Emits the pnpm-prune pipefail failure. Both prune paths (`pnpm install --prod` for workspaces
# and `pnpm prune --prod` otherwise) run `pnpm 2>&1 | tee log`, and a tee-side failure (typically
# the build ran out of disk space) classifies as buildpack-side rather than blaming the app's
# dependencies. Callers pass only the joined PIPESTATUS string.
function package_managers::pnpm::_handle_prune_pipefail() {
	local pipe_status_str="${1}"
	local message
	message=$(
		cat <<-EOF
			Error: Unable to capture the pnpm prune log output.

			The dependency prune ran, but writing its log to disk failed (for example,
			the build ran out of disk space). This is not a problem with your
			dependencies. Please try again.
		EOF
	)
	failure::handle_pipefail "pnpm-prune-pipefail" "${pipe_status_str}" "${message}"
}

# Runs a pnpm dev-dependency prune command with call-site failure classification. Shared by both
# prune strategies: the workspace path (`pnpm install --prod --frozen-lockfile`, a production
# reinstall) and the non-workspace path (`pnpm prune --prod [--ignore-scripts]`). Both record the
# same `prune_dev_dependencies_time` metric and have the same failure surface — a tee-side pipe
# failure is buildpack-side, and a git+ssh host-key failure is classified generically (see below);
# any other pnpm tool failure bubbles to the generic ERR-trap fallback — so the two paths differ only in the
# command, which the caller passes as arguments.
function package_managers::pnpm::_run_prune() {
	local prune_command=("$@")

	local log_file
	log_file=$(mktemp)

	local start
	start=$(build_data::current_unix_realtime)

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves.
	# pnpm writes progress and errors across stdout+stderr; merge them with `2>&1`, pass the
	# merged stream through `tee` for classification, and indent it with `output::indent`.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { "${prune_command[@]}" 2>&1 | tee "${log_file}" | output::indent; }; then
		# Capture the full pipe status first (before any other command clobbers PIPESTATUS).
		# The pipeline is `pnpm 2>&1 | tee | output::indent`, so [0] is pnpm's exit code (tee is [1], output::indent [2]).
		local pipe_status=("${PIPESTATUS[@]}")
		local pnpm_exit="${pipe_status[0]}"
		build_data::set_duration "prune_dev_dependencies_time" "${start}"

		local -A failure
		# shellcheck disable=SC2310 # the elif calls a function in a condition, so set -e is disabled inside
		if [[ "${pnpm_exit}" -eq 0 ]]; then
			# pnpm succeeded but the pipeline failed (tee couldn't write the log — e.g. out of
			# disk). Buildpack-side, so don't blame the app.
			package_managers::pnpm::_handle_prune_pipefail "${pipe_status[*]}"
		elif failure::handle_git_auth_failure "${log_file}" failure; then
			# Only the workspace reinstall variant (`pnpm install --prod --frozen-lockfile`) can
			# hit this — it re-fetches dependencies and can re-trigger a git+ssh host-key failure.
			# The non-workspace `pnpm prune` path never touches git, so this simply never matches
			# there.
			failure::emit failure
		elif failure::handle_econnreset "${log_file}" failure; then
			# Only the workspace reinstall variant can re-fetch dependencies and hit a network
			# reset the same way a fresh install can; the non-workspace `pnpm prune` path never
			# hits the network, so this simply never matches there.
			failure::emit failure
		elif failure::handle_libc6_incompatibility "${log_file}" failure; then
			# The Node.js binary itself is incompatible with the current stack's glibc. Unlike the
			# git-auth/econnreset checks above, this can surface on either prune path (it's the
			# Node.js binary invoked by pnpm that fails to start, not a re-fetch).
			failure::emit failure
		fi

		# No known failure mode recognised. Bubble up by returning pnpm's exit code: the bare
		# `prune_devdependencies` call in bin/compile then fails under errexit and the generic
		# failure::handle_uncaught ERR trap records it as failure=internal-error — there is no
		# migrated pnpm-prune tool-error classifier to add here yet.
		return "${pnpm_exit}"
	fi

	build_data::set_duration "prune_dev_dependencies_time" "${start}"
	build_data::set_raw "skipped_prune" "false"
}

# Pure classifier for pnpm dependency-install failures.
#
# Input:
#   $1  path to a log file containing the captured output of the failed pnpm command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when a known failure mode is recognised; returns 1 and leaves
# the array untouched otherwise. Has no side effects: it does not write build data, print to
# the build log, or exit. Detail is set to the pnpm error code plus the first descriptive error
# line, giving observability a precise discriminator within each failure bucket.
function package_managers::pnpm::_handle_install_failure() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	# ERR_PNPM_OUTDATED_LOCKFILE — pnpm refuses to install under `--frozen-lockfile` when
	# pnpm-lock.yaml has drifted from package.json (thrown from pnpm's install index.ts). Gate on
	# the stable error code rather than the message, which has drifted across pnpm versions. The
	# ERR_PNPM_ prefix is stamped by the PnpmError constructor and survives in non-TTY dynos even
	# when chalk wraps it in ANSI color.
	if grep -qi 'ERR_PNPM_OUTDATED_LOCKFILE' "${log_file}"; then
		__failure["id"]="pnpm-lockfile-out-of-sync"
		__failure["classification"]="user"
		__failure["detail"]="ERR_PNPM_OUTDATED_LOCKFILE: $(package_managers::pnpm::_extract_error_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: pnpm lockfile is not in sync.

				This error occurs when the contents of \`package.json\` contains a different
				set of dependencies than the contents of \`pnpm-lock.yaml\`. This can happen
				when a package is added, modified, or removed but the lockfile was not updated.

				To fix this, run \`pnpm install\` locally in your app directory to regenerate the
				lockfile, commit the changes to \`pnpm-lock.yaml\`, and redeploy.
			EOF
		)
		return 0
	fi

	# TODO: classify additional pnpm codes surfaced by pnpm's default reporter but not yet handled
	# here, e.g. ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE (lockfile format-version mismatch),
	# ERR_PNPM_NO_MATCHING_VERSION, ERR_PNPM_FETCH_401/403/404, ERR_PNPM_PEER_DEP_ISSUES, ELIFECYCLE.
	# Add each as its own matcher above, verified against pnpm source.

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

# Returns the first descriptive pnpm error line for use as failure detail: pnpm's default
# reporter renders the summary as `[ERR_PNPM_<CODE>] <message>`, so grab that first line and
# strip the leading `[CODE] ` bracket prefix. `|| true` so a no-match never trips errexit.
# Internal helper to package_managers::pnpm::_handle_install_failure; not meant to be called
# directly.
function package_managers::pnpm::_extract_error_detail() {
	local log_file="${1}"
	grep -aE '^\[ERR_PNPM_[A-Z_]+\]' "${log_file}" \
		| head -n 1 \
		| sed -E 's/^\[[A-Z_]+\][[:space:]]*//' \
		|| true
}

function package_managers::pnpm::prune_devdependencies() {
	local build_dir=${1:-}

	cd "${build_dir}" || return

	# NODE_ENV and PNPM_SKIP_PRUNING are globals exported by the caller (bin/compile via
	# lib/environment.sh / the app's config vars).
	# shellcheck disable=SC2154 # set by the caller (bin/compile)
	if [[ "${NODE_ENV}" == "test" ]]; then
		output::info "Skipping because NODE_ENV is 'test'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	elif [[ "${NODE_ENV}" != "production" ]]; then
		output::info "Skipping because NODE_ENV is not 'production'"
		build_data::set_raw "skipped_prune" "true"
		return 0
	elif [[ "${PNPM_SKIP_PRUNING}" == "true" ]]; then
		output::info "Skipping because PNPM_SKIP_PRUNING is '${PNPM_SKIP_PRUNING}'"
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
				output::warning <<-EOF
					Pruning skipped due to presence of lifecycle scripts

					Lifecycle scripts were detected in the \`package.json\` file at \`${project_path}\`. Due to how
					workspace pruning in pnpm operates, it will execute the following lifecycle scripts declared
					in package.json during reinstallation of prod dependencies which can cause build failures:
					- pnpm:devPreinstall
					- preinstall
					- install
					- postinstall
					- prepare

					Since pruning can't be done safely for your build, it will be skipped.
				EOF
				build_data::set_raw "skipped_prune" "true"
				return 0
			fi
		done
		# Remove node_modules from each project
		for project_path in "${project_paths[@]}"; do
			rm -rf "${project_path}/node_modules"
		done
		# Reinstall with production-only dependencies
		package_managers::pnpm::_run_prune pnpm install --prod --frozen-lockfile
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
			output::warning <<-EOF
				Pruning skipped due to presence of lifecycle scripts

				The version of pnpm used (${pnpm_version}) will execute the following lifecycle scripts
				declared in package.json during pruning which can cause build failures:
				- pnpm:devPreinstall
				- preinstall
				- install
				- postinstall
				- prepare

				Since pruning can't be done safely for your build, it will be skipped. To fix this you
				must upgrade your version of pnpm to 8.15.6 or higher.

				https://devcenter.heroku.com/articles/nodejs-support
			EOF
			build_data::set_raw "skipped_prune" "true"
			return
		fi
	else
		# we're on a version that supports this flag (8.15.6 and higher)
		pnpm_prune_args+=("--ignore-scripts")
	fi

	package_managers::pnpm::_run_prune pnpm "${pnpm_prune_args[@]}"
}

function package_managers::pnpm::_workspace_configured() {
	local build_dir=${1:-}
	local workspace_file="${build_dir}/pnpm-workspace.yaml"
	local result

	if [[ -f "${workspace_file}" ]]; then
		# prior to pnpm 10.5.0, the `packages` key was mandatory, but now, you can store
		# other pnpm-related config settings in `pnpm-workspace.yaml`.
		result=$(utils::yaml::read "${workspace_file}" '.packages')

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
	# `|| true` so a non-zero `pnpm list` (or empty workspace) can't abort the <(…) subshell under
	# inherit_errexit — its exit is intentionally not consulted (see caller).
	pnpm list --recursive --json --depth -1 2>/dev/null | jq -r '.[].path' || true
}

function package_managers::pnpm::install_binary() {
	local version="$1"
	output::info "Downloading and installing pnpm (${version})"
	# npm 12 removed the --unsafe-perm flag and rejects it with EUNKNOWNCONFIG, so only pass it
	# to the currently-active npm when that npm still accepts it.
	local unsafe_perm=()
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside; a non-match just omits the flag
	if package_managers::npm::supports_unsafe_perm; then
		unsafe_perm=(--unsafe-perm)
	fi
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
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
	output::info "Using pnpm $(pnpm --version || true)"
}

# Runs a named lifecycle script with pnpm. Spells the pnpm-specific command (`pnpm run
# --if-present <script>`, forwarding NODE_BUILD_FLAGS after a `--` separator) and hands execution
# to the shared coordinator runner, which captures output and routes failures. `build_flags` is
# the optional NODE_BUILD_FLAGS string (empty for prebuild/postbuild/cleanup scripts).
function package_managers::pnpm::run_script() {
	local script_name=${1}
	local build_flags=${2:-}

	output::info "Running ${script_name}"

	local command=(pnpm run --if-present "${script_name}")
	if [[ -n "${build_flags}" ]]; then
		output::info "Running with ${build_flags} flags"
		command+=(-- "${build_flags}")
	fi

	package_manager::run_script_command "${command[@]}"
}

# Lists installed top-level dependencies for the verbose build summary. Wrapped in `|| true` and
# `2>/dev/null` so a listing failure never aborts the summary.
function package_managers::pnpm::list_dependencies() {
	local build_dir=${1:-}

	cd "${build_dir}" || return
	(pnpm list --depth=0 || true) 2>/dev/null
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__pnpm_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__pnpm_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__pnpm_saved_pipefail}"
unset __pnpm_saved_flags __pnpm_saved_pipefail
