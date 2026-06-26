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

		# shellcheck disable=SC2310 # || disables errexit, but that's intentional for this pattern
		resolve_result=$(runtimes::nodejs::_resolve "${requested_version}" || echo "failed")

		if [[ "${resolve_result}" == "failed" ]]; then
			fail_bin_install "${requested_version}"
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
		false
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
				false
			fi
			;;
		*)
			build_data::set_string "failure" "unsupported-checksum"
			output::error <<-EOF
				Unsupported checksum for Node.js ${version} - ${checksum_type}:${checksum_value}
			EOF
			false
			;;
		esac
	fi

	rm -rf "${dir:?}"/*
	tar xzf /tmp/node.tar.gz --strip-components 1 -C "${dir}"
	chmod +x "${dir}"/bin/*
}

function runtimes::nodejs::_resolve() {
	local node_version="$1"
	local output

	if output=$("${RESOLVE}" "${BP_DIR}/inventory/node.toml" "${node_version}"); then
		if [[ ${output} = "No result" ]]; then
			return 1
		else
			echo "${output}"
			return 0
		fi
	fi
	return 1
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
# Input:  $1 path to the captured Node install log; $2 name of an associative array to fill.
# Returns 0 + fills the array on a known failure; returns 1 untouched otherwise. No side effects.
function runtimes::nodejs::_handle_install_failure() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	return 1
}

# Restore the sourcing shell's original options (see preamble).
case "${__nodejs_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__nodejs_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__nodejs_saved_pipefail}"
unset __nodejs_saved_flags __nodejs_saved_pipefail
