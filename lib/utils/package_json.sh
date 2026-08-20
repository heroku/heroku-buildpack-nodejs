#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. See
# lib/package_managers/npm.sh for the full rationale on reading $- vs $(set +o).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__package_json_saved_flags="$-"
__package_json_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

# Echoes "true" if package.json declares the named script, "false" otherwise (including when the
# file is absent).
function utils::package_json::has_script() {
	local file="$1"
	local key="$2"

	if test -f "${file}"; then
		# jq's has() errors on a non-object `.scripts` (and on an absent `scripts` key under
		# jq <=1.6); fall back to "false" so a captured `$(...)` can't abort under inherit_errexit.
		# shellcheck disable=SC2002
		cat "${file}" | jq ".[\"scripts\"] | has(\"${key}\")" || echo "false"
	else
		echo "false"
	fi
}

# Pre-flight guard: fails the build when the app's package.json is not parseable JSON. Checks
# the file and, if it is invalid, hands off to the emit-at-site helper (which prints the
# message, records build data, and exits).
function utils::package_json::fail_invalid() {
	local build_dir="${1}"

	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside
	if ! utils::json::is_valid "${build_dir}/package.json"; then
		utils::package_json::_fail_invalid
	fi
}

# Emits the classified failure for an app whose package.json cannot be parsed as JSON. Keeps
# the historical `invalid-package-json` failure id for metric continuity. Classified `user` —
# the app controls this file. See runtimes::nodejs::_fail_iojs_unsupported for why this emits
# directly at the call site.
function utils::package_json::_fail_invalid() {
	local -A failure
	failure["id"]="invalid-package-json"
	failure["classification"]="user"
	failure["message"]=$(
		cat <<-EOF
			Error: Unable to parse your package.json.

			Your package.json contains invalid JSON and could not be read.

			Check the file for syntax errors such as trailing commas, missing commas,
			or unquoted keys, then commit and redeploy. You can validate it locally by
			running \`jq . package.json\` or using an online JSON linter.
		EOF
	)
	failure::emit failure
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__package_json_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__package_json_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__package_json_saved_pipefail}"
unset __package_json_saved_flags __package_json_saved_pipefail
