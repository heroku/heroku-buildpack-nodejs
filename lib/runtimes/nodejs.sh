#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. See
# lib/package_managers/npm.sh for the full rationale on reading $- vs $(set +o).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__nodejs_saved_flags="$-"
__nodejs_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

# shellcheck disable=SC2154 # BP_DIR is a global set by the caller
RESOLVE="${BP_DIR}/lib/vendor/resolve-version-$(get_os)"

function runtimes::nodejs::install() {
	local requested_version="${1:-}"
	local dir="${2:?}"

	local log_file
	log_file=$(mktemp)

	local start
	start=$(build_data::current_unix_realtime)

	# Run inside `if !` so errexit is suppressed and we can inspect the failure ourselves.
	# `_install` handles every failure it anticipates at the site (each `_fail_*` helper emits via
	# `failure::emit` and exits the process), so control only reaches this branch on a genuinely
	# unexpected, non-emitting failure. `tee` passes stdout through, so normal install output still
	# reaches the caller's pipe; user-facing warnings/errors go to stderr and pass straight through.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { runtimes::nodejs::_install "${requested_version}" "${dir}" | tee "${log_file}"; }; then
		# Capture the full pipe status before any other command clobbers PIPESTATUS.
		local install_exit="${PIPESTATUS[0]}"
		build_data::set_duration "install_node_binary_time" "${start}"

		# Nothing emitted a classified failure. Bubble up so the legacy ERR trap reports it as a
		# generic internal error while matchers not yet migrated here still get handled.
		return "${install_exit}"
	fi

	build_data::set_duration "install_node_binary_time" "${start}"

	local node_version node_version_major bundled_npm_version
	node_version=$(node --version)
	node_version_major=$(get_node_major_version)
	bundled_npm_version=$(npm --version)
	build_data::set_string "node_version" "${node_version}"
	build_data::set_raw "node_version_major" "${node_version_major}"
	build_data::set_string "bundled_npm_version" "${bundled_npm_version}"
}

function runtimes::nodejs::_install() {
	local requested_version="${1:-}"
	local dir="${2:?}"

	if [[ -n "${NODE_BINARY_URL}" ]]; then
		download_url="${NODE_BINARY_URL}"
		echo "Downloading and installing node from ${download_url}"
	else
		if [[ -z "${requested_version}" ]]; then
			echo "No Node.js version specified, resolving current LTS version..."
		else
			echo "Resolving node version ${requested_version}..."
		fi

		# The resolver always prints a single JSON object with a `status` discriminator to stdout,
		# on both success (exit 0) and error (exit 1). Capture stdout only; a genuinely broken
		# binary (crash / non-JSON) is caught by the `jq -e` guard below and bubbled to the trap.
		local resolve_result
		resolve_result=$("${RESOLVE}" "${BP_DIR}/inventory/node.toml" "${requested_version}") || true

		local resolve_status
		if ! resolve_status=$(jq -e -r '.status' <<<"${resolve_result}" 2>/dev/null); then
			# The binary produced no parseable JSON — an unexpected failure. Let it bubble up to
			# the global ERR trap rather than guessing at a classification.
			return 1
		fi

		if [[ "${resolve_status}" != "resolved" ]]; then
			# Decode the error fields in a single jq call. `lts_major` is absent for internal
			# errors (jq `// ""`), which is fine — the catch-all handler doesn't use it. Capture
			# jq's output on its own line for readability; errexit is disabled here (this runs
			# inside the `if !` pipe), and the payload was already validated as well-formed JSON
			# by the `jq -e` guard above, so this static-field extraction cannot fail on it.
			# @tsv escapes any embedded tab/newline so the field split is safe.
			local error lts_major resolve_error
			resolve_error=$(jq -r '[.error, (.lts_major // "")] | @tsv' <<<"${resolve_result}")
			IFS=$'\t' read -r error lts_major <<<"${resolve_error}"

			case "${resolve_status}" in
			no-version-resolved)
				runtimes::nodejs::_fail_no_version_resolved "${requested_version}" "${lts_major}"
				;;
			invalid-semver-requirement)
				runtimes::nodejs::_fail_invalid_semver_requirement "${requested_version}" "${lts_major}"
				;;
			*)
				# Catch-all for `internal-error` (inventory read/parse, unsupported OS/arch, missing
				# recommended LTS) and any future/unknown status. Each _fail_* handler emits and exits.
				runtimes::nodejs::_fail_resolve "${requested_version}" "${resolve_status}" "${error}"
				;;
			esac
		fi

		# Success: read all fields in a single batched jq call. Capture jq's output on its own
		# line for readability; errexit is disabled here (this runs inside the `if !` pipe), and
		# the payload was already validated as well-formed JSON by the `jq -e` guard above, so
		# this static-field extraction cannot fail on it. Split the result into individual
		# variables. Booleans arrive as the strings "true"/"false", matching the checks further down.
		local version download_url checksum_type checksum_value
		local uses_wide_range lts_upper_bound_enforced lts_version eol resolve_fields
		resolve_fields=$(jq -r '[.version, .url, .checksum_type, .checksum_value,
			.uses_wide_range, .lts_upper_bound_enforced, .lts_version, .eol] | @tsv' \
			<<<"${resolve_result}")
		IFS=$'\t' read -r version download_url checksum_type checksum_value \
			uses_wide_range lts_upper_bound_enforced lts_version eol <<<"${resolve_fields}"

		build_data::set_raw "node_version_eol" "${eol}"

		[[ "${uses_wide_range}" == "true" ]] && runtimes::nodejs::_warn_wide_range "${requested_version}" "${lts_version}"
		[[ "${lts_upper_bound_enforced}" == "true" ]] && runtimes::nodejs::_warn_lts_upper_bound "${requested_version}" "${version}"
		[[ "${eol}" == "true" ]] && runtimes::nodejs::_warn_eol "${version}"

		echo "Downloading and installing node ${version}..."

		[[ "${version}" == "22.5.0" ]] && runtimes::nodejs::_warn_known_bad_release
	fi

	output_file="/tmp/node.tar.gz"
	if ! curl "${download_url}" --no-progress-meter --location --fail --max-time 30 --retry 5 --retry-connrefused --connect-timeout 5 -o "${output_file}"; then
		runtimes::nodejs::_fail_node_download "${download_url}"
	fi

	if [[ -z "${NODE_BINARY_URL}" ]]; then
		case "${checksum_type}" in
		"sha256")
			echo "Validating checksum"
			local actual_checksum
			actual_checksum=$(sha256sum "${output_file}" | cut -d " " -f 1)
			if [[ "${actual_checksum}" != "${checksum_value}" ]]; then
				runtimes::nodejs::_fail_checksum_validation "${version}" "${checksum_type}" "${checksum_value}" "${actual_checksum}"
			fi
			;;
		*)
			runtimes::nodejs::_fail_unsupported_checksum "${version}" "${checksum_type}" "${checksum_value}"
			;;
		esac
	fi

	rm -rf "${dir:?}"/*
	tar xzf /tmp/node.tar.gz --strip-components 1 -C "${dir}"
	chmod +x "${dir}"/bin/*
}

function runtimes::nodejs::_warn_wide_range() {
	local requested_version="$1"
	local lts_version="$2"
	output::warning <<-EOF
		The requested Node.js version is using a wide range (${requested_version}) that can resolve to a Node.js major version
		higher than you intended. Limiting the requested range to a major LTS range like \`${lts_version}\` is recommended.
		https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version
	EOF
}

function runtimes::nodejs::_warn_lts_upper_bound() {
	local requested_version="$1"
	local version="$2"
	output::warning <<-EOF
		The resolved Node.js version has been limited to the Active LTS (${version}) for the requested range of \`${requested_version}\`.
		To opt-out of this behavior, set the following config var: \`NODEJS_ALLOW_WIDE_RANGE=true\`
		https://devcenter.heroku.com/articles/nodejs-support#supported-node-js-versions
	EOF
}

function runtimes::nodejs::_warn_eol() {
	local version="$1"
	output::warning <<-EOF
		Node.js ${version} is now End-of-Life (EOL). It no longer receives security
		updates, bug fixes, or support from the Node.js project and is no longer
		supported on Heroku.

		In a future buildpack release, this warning will become a build error. Please
		upgrade to a supported version as soon as possible to avoid build failures.

		https://devcenter.heroku.com/articles/nodejs-support#supported-node-js-versions
	EOF
}

function runtimes::nodejs::_warn_known_bad_release() {
	output::warning <<-EOF
		Issues with Node.js v22.5.0

		Shortly after the release of Node.js v22.5.0, users began reporting issues around broken
		or hanging installs for npm and Yarn. To avoid experiencing these problems with your builds
		on Heroku, we recommend avoiding this release version until a fix has been released by
		pinning to an earlier version of Node.js (e.g.; 22.4.1).
		https://github.com/nodejs/node/pull/53934
	EOF
}

# Emits the classified failure for a Node.js download error and exits. Called directly at the
# failure site because the cause is known locally — the buildpack knows exactly what failed here,
# so it can render a specific message and exit without any further inspection.
function runtimes::nodejs::_fail_node_download() {
	local download_url="${1}"
	local -A failure
	failure["id"]="node-download-failed"
	failure["classification"]="buildpack"
	failure["detail"]="${download_url}"
	failure["message"]=$(
		cat <<-EOF
			Error: Unable to download Node.js.

			Failed to download Node.js from:
			${download_url}

			In some cases, this happens due to a temporary network
			issue or an outage with the Node.js distribution server.

			Confirm the download url (${download_url}) works then try building again
			to see if the error resolves itself.

			If that doesn't help, check the Node.js status page:
			https://status.nodejs.org/
		EOF
	)
	failure::emit failure
}

# Emits the classified failure for a Node.js checksum mismatch and exits. See
# runtimes::nodejs::_fail_node_download for why this is called directly at the failure site.
function runtimes::nodejs::_fail_checksum_validation() {
	local version="${1}"
	local checksum_type="${2}"
	local checksum_value="${3}"
	local actual_checksum="${4}"
	local -A failure
	failure["id"]="checksum-validation-failed"
	failure["classification"]="buildpack"
	failure["detail"]="${checksum_type} expected:${checksum_value} actual:${actual_checksum}"
	failure["message"]=$(
		cat <<-EOF
			Checksum validation failed for Node.js ${version} - ${checksum_type}:${checksum_value}
		EOF
	)
	failure::emit failure
}

# Emits the classified failure for an unsupported Node.js checksum type and exits. See
# runtimes::nodejs::_fail_node_download for why this is called directly at the failure site.
function runtimes::nodejs::_fail_unsupported_checksum() {
	local version="${1}"
	local checksum_type="${2}"
	local checksum_value="${3}"
	local -A failure
	failure["id"]="unsupported-checksum"
	failure["classification"]="buildpack"
	failure["detail"]="${checksum_type}:${checksum_value}"
	failure["message"]=$(
		cat <<-EOF
			Unsupported checksum for Node.js ${version} - ${checksum_type}:${checksum_value}
		EOF
	)
	failure::emit failure
}

# Emits the classified failure for resolver status `no-version-resolved`: the requested version
# is a valid semver range but matches no published Node.js version. Keeps the historical
# `invalid-node-version` failure id for observability/metric continuity. See
# runtimes::nodejs::_fail_node_download for why this emits directly at the call site.
function runtimes::nodejs::_fail_no_version_resolved() {
	local requested_version="${1}"
	local lts_major="${2}"
	local -A failure
	failure["id"]="invalid-node-version"
	failure["classification"]="user"
	failure["detail"]="${requested_version}"
	failure["message"]=$(
		cat <<-EOF
			Error: No published Node.js version matches the requested range.

			The version requirement in your package.json (${requested_version}) is a valid
			semver range, but it does not match any Node.js version available on Heroku.

			We recommend requesting a major version range so you automatically receive
			security and bug-fix updates for that release line, for example:

			"engines": {
			  "node": "${lts_major}.x"
			}

			https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version
		EOF
	)
	failure::emit failure
}

# Emits the classified failure for resolver status `invalid-semver-requirement`: the requested
# version is not a valid semver range. See runtimes::nodejs::_fail_node_download for why this
# emits directly at the call site.
function runtimes::nodejs::_fail_invalid_semver_requirement() {
	local requested_version="${1}"
	local lts_major="${2}"
	local -A failure
	failure["id"]="invalid-semver-requirement"
	failure["classification"]="user"
	failure["detail"]="${requested_version}"
	failure["message"]=$(
		cat <<-EOF
			Error: Invalid Node.js version requirement.

			The version requirement in your package.json (${requested_version}) is not a
			valid semantic version range, so we can't determine which Node.js version to
			install.

			We recommend requesting a major version range so you automatically receive
			security and bug-fix updates for that release line, for example:

			"engines": {
			  "node": "${lts_major}.x"
			}

			https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version
		EOF
	)
	failure::emit failure
}

# Catch-all for resolver status `internal-error` (inventory read/parse, unsupported OS/arch,
# missing recommended LTS) and any future/unknown status. Captures the resolver's own error text
# in `detail` for observability. Classified `buildpack` — this replaces the previously opaque
# `unknown-install-nodejs-error`. See runtimes::nodejs::_fail_node_download for the direct-emit
# rationale.
function runtimes::nodejs::_fail_resolve() {
	local requested_version="${1}"
	local status="${2}"
	local error="${3}"
	local -A failure
	failure["id"]="node-version-resolution-failed"
	failure["classification"]="buildpack"
	failure["detail"]="${status}: ${error}"
	failure["message"]=$(
		cat <<-EOF
			Error: Unable to resolve a Node.js version to install.

			An unexpected error occurred while resolving the requested Node.js version
			(${requested_version}):

			${error}

			This is usually a temporary problem on our side. Please try building again.
			If the problem persists, open a support ticket:
			https://help.heroku.com/
		EOF
	)
	failure::emit failure
}

# Restore the sourcing shell's original options (see preamble).
case "${__nodejs_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__nodejs_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__nodejs_saved_pipefail}"
unset __nodejs_saved_flags __nodejs_saved_pipefail
