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
	# Capture only stdout into the log: `_install` echoes its failure discriminators to stdout
	# for the classifier, while user-facing warnings/errors go to stderr (via output::*) and must
	# pass straight through to the real stderr — so we deliberately do NOT merge `2>&1` here.
	# `tee` passes stdout through, so normal install output still reaches the caller's pipe.
	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! { runtimes::nodejs::_install "${requested_version}" "${dir}" | tee "${log_file}"; }; then
		# Capture the full pipe status before any other command clobbers PIPESTATUS.
		local install_exit="${PIPESTATUS[0]}"
		build_data::set_duration "install_node_binary_time" "${start}"

		local -A failure
		# shellcheck disable=SC2310 # the classifier fills `failure` by nameref; invoked directly so its writes survive
		if runtimes::nodejs::_handle_install_failure "${log_file}" "${requested_version}" failure; then
			failure::emit failure
		fi

		# No known failure mode recognised. Bubble up so the legacy ERR trap classifies it
		# (generic fallback) while matchers not yet migrated here still get handled.
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
	local resolve_result

	if [[ -n "${NODE_BINARY_URL}" ]]; then
		download_url="${NODE_BINARY_URL}"
		echo "Downloading and installing node from ${download_url}"
	else
		if [[ -z "${requested_version}" ]]; then
			echo "No Node.js version specified, resolving current LTS version..."
		else
			echo "Resolving node version ${requested_version}..."
		fi

		# The resolver prints "No result" on stdout (exit 0) for an unknown version, or
		# "Could not parse"/"Could not get …" for a malformed requirement; capture stderr too so
		# either surfaces in a single invocation.
		local resolve_result resolve_exit_code
		resolve_result=$("${RESOLVE}" "${BP_DIR}/inventory/node.toml" "${requested_version}" 2>&1) && resolve_exit_code=0 || resolve_exit_code=$?

		if [[ "${resolve_exit_code}" -ne 0 || "${resolve_result}" == "No result" ]]; then
			# Print the canonical discriminating line so _handle_install_failure can classify it.
			if [[ "${resolve_result}" == "No result" ]]; then
				echo "Could not find Node version corresponding to version requirement: ${requested_version}"
			elif [[ "${resolve_result}" == "Could not parse"* ]] || [[ "${resolve_result}" == "Could not get"* ]]; then
				echo "Error: Invalid semantic version \"${requested_version}\""
			else
				echo "Error: Unknown error installing \"${requested_version}\" of node"
			fi
			return 1
		fi

		version=$(echo "${resolve_result}" | jq -r .version)
		download_url=$(echo "${resolve_result}" | jq -r .url)
		checksum_type=$(echo "${resolve_result}" | jq -r .checksum_type)
		checksum_value=$(echo "${resolve_result}" | jq -r .checksum_value)
		uses_wide_range=$(echo "${resolve_result}" | jq .uses_wide_range)
		lts_upper_bound_enforced=$(echo "${resolve_result}" | jq .lts_upper_bound_enforced)
		lts_version=$(echo "${resolve_result}" | jq -r .lts_version)
		eol=$(echo "${resolve_result}" | jq .eol)

		build_data::set_raw "node_version_eol" "${eol}"

		[[ "${uses_wide_range}" == "true" ]] && runtimes::nodejs::_warn_wide_range "${requested_version}" "${lts_version}"
		[[ "${lts_upper_bound_enforced}" == "true" ]] && runtimes::nodejs::_warn_lts_upper_bound "${requested_version}" "${version}"
		[[ "${eol}" == "true" ]] && runtimes::nodejs::_warn_eol "${version}"

		echo "Downloading and installing node ${version}..."

		[[ "${version}" == "22.5.0" ]] && runtimes::nodejs::_warn_known_bad_release
	fi

	output_file="/tmp/node.tar.gz"
	if ! curl "${download_url}" --no-progress-meter --location --fail --max-time 30 --retry 5 --retry-connrefused --connect-timeout 5 -o "${output_file}"; then
		build_data::set_string "failure" "node-download-failed"
		output::error <<-EOF
			Error: Unable to download Node.js.

			Failed to download Node.js from:
			${download_url}

			In some cases, this happens due to a temporary network
			issue or an outage with the Node.js distribution server.

			Confirm the download url ({url}) works then try building again
			to see if the error resolves itself.

			If that doesn't help, check the Node.js status page:
			https://status.nodejs.org/
		EOF
		return 1
	fi

	if [[ -z "${NODE_BINARY_URL}" ]]; then
		case "${checksum_type}" in
		"sha256")
			echo "Validating checksum"
			if ! echo "${checksum_value} ${output_file}" | sha256sum --check --status; then
				build_data::set_string "failure" "checksum-validation-failed"
				output::error <<-EOF
					Checksum validation failed for Node.js ${version} - ${checksum_type}:${checksum_value}
				EOF
				return 1
			fi
			;;
		*)
			build_data::set_string "failure" "unsupported-checksum"
			output::error <<-EOF
				Unsupported checksum for Node.js ${version} - ${checksum_type}:${checksum_value}
			EOF
			return 1
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

# Pure classifier for Node.js install failures.
#
# Input:  $1 path to the captured Node install log; $2 the requested version requirement;
#         $3 name of an associative array to fill.
# Returns 0 + fills the array on a known failure; returns 1 untouched otherwise. No side effects.
function runtimes::nodejs::_handle_install_failure() {
	local log_file="${1}"
	local requested_version="${2}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${3}"

	if grep -qi 'Could not find Node version corresponding to version requirement' "${log_file}"; then
		__failure["id"]="invalid-node-version"
		__failure["classification"]="user"
		__failure["detail"]="${requested_version}"
		__failure["message"]=$(
			cat <<-EOF
				No matching version found for Node: ${requested_version}

				Heroku supports the latest Stable version of Node.js as well as all
				active LTS (Long-Term-Support) versions, however you have specified
				a version in package.json (${requested_version}) that does not correspond to
				any published version of Node.js.

				You should always specify a Node.js version that matches the runtime
				you're developing and testing with. To find your version locally:

				$ node --version
				v6.11.1

				Use the engines section of your package.json to specify the version of
				Node.js to use on Heroku. Drop the 'v' to save only the version number:

				"engines": {
				  "node": "6.11.1"
				}

				https://help.heroku.com/6235QYN4/
			EOF
		)
		return 0
	fi

	if grep -qi 'Error: Invalid semantic version' "${log_file}"; then
		__failure["id"]="invalid-semver-requirement"
		__failure["classification"]="user"
		__failure["detail"]="${requested_version}"
		__failure["message"]=$(
			cat <<-EOF
				Invalid semver requirement

				Node, Yarn, and npm adhere to semver, the semantic versioning convention
				popularized by GitHub.

				http://semver.org/

				However you have specified a version requirement that is not a valid
				semantic version.

				https://help.heroku.com/0ZIOF3ST
			EOF
		)
		return 0
	fi

	# No known failure mode recognised — let the caller fall through.
	return 1
}

# Restore the sourcing shell's original options (see preamble).
case "${__nodejs_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__nodejs_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__nodejs_saved_pipefail}"
unset __nodejs_saved_flags __nodejs_saved_pipefail
