#!/usr/bin/env bash

# Enable strict mode for ShellCheck's benefit, but restore the caller's options at the end of
# the file (see epilogue) so these don't bleed into the un-migrated scripts that source this
# lib. The caller's flags are read from `$-`, which reflects the *current* shell — a
# `$(set +o)` capture runs in a command-substitution subshell where bash always forces errexit
# off, so it would record (and later restore) errexit as disabled even when the caller had it
# enabled. `$-` has no letter for pipefail, so that one option is captured separately (it is
# reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__failures_saved_flags="$-"
__failures_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

# Records a classified failure in build data, prints its message, and exits the build. This is
# the only side-effecting layer; classifiers (e.g. npm::_handle_npm_install_failure) stay pure
# by filling an associative array that is passed here by name.
#
# The named array may define:
#   [id]              build_data `failure` value          (required)
#   [message]         multi-line message shown to user     (required)
#   [detail]          build_data `failure_detail` value    (optional)
#   [classification]  build_data `failure_classification`  (optional)
#
# Usage (quote the subscripts on assignment so ShellCheck doesn't read the bare keys as
# references to unassigned variables):
# ```
# declare -A failure
# failure["id"]="install-dependencies::npm"
# failure["message"]="Error: ..."
# failure::emit failure
# ```
function failure::emit() {
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${1}"

 	# This function may run inside a pipe whose stdout is styled by `output`
	# (e.g. `build_dependencies | output "$LOG_FILE"`), which indents every non-header line and
	# copies it to the build log. To avoid double styling, anything emitted here must either:
	#   - Be a header, which `output` passes through untouched via its `^----->` check, or
	#   - Be piped through `output::error`, which writes to stderr and bypasses `output` entirely.
	header "Build failed"
	echo "${__failure[message]}" | output::error

	build_data::set_string "failure" "${__failure[id]}"
	[[ -n "${__failure[detail]:-}" ]] && build_data::set_string "failure_detail" "${__failure[detail]}"
	[[ -n "${__failure[classification]:-}" ]] && build_data::set_string "failure_classification" "${__failure[classification]}"

	# Signal that this failure is fully handled so the legacy ERR trap skips its classification
	# matchers and doesn't re-report it. A file (not a variable) because emit may run inside a
	# subshell (e.g. the left side of `build_dependencies | output`) where the trap, running in
	# the parent shell, would never see a variable assignment.
	[[ -n "${FAILURE_EMITTED_MARKER:-}" ]] && : >"${FAILURE_EMITTED_MARKER}"

	fail
}

# Restore the sourcing shell's original options (see preamble) so strict mode doesn't leak
# into un-migrated callers. errexit/nounset come from the saved `$-`; pipefail from its own
# saved `set +o` line.
case "${__failures_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__failures_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__failures_saved_pipefail}"
unset __failures_saved_flags __failures_saved_pipefail
