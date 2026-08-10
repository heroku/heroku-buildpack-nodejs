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
		# shellcheck disable=SC2002
		cat "${file}" | jq ".[\"scripts\"] | has(\"${key}\")"
	else
		echo "false"
	fi
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__package_json_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__package_json_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__package_json_saved_pipefail}"
unset __package_json_saved_flags __package_json_saved_pipefail
