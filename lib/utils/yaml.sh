#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. See
# lib/package_managers/npm.sh for the full rationale on reading $- vs $(set +o).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__yaml_saved_flags="$-"
__yaml_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

# BP_DIR is a global set by the caller (bin/compile) and get_os comes from lib/environment.sh,
# which is sourced first.
# shellcheck disable=SC2154
YQ="${BP_DIR}/lib/vendor/yq-4.52.4-$(get_os)"

# Reads a yq expression from a YAML file.
function utils::yaml::read() {
	local file="$1"
	local key="$2"
	"${YQ}" "${key}" "${file}"
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__yaml_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__yaml_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__yaml_saved_pipefail}"
unset __yaml_saved_flags __yaml_saved_pipefail
