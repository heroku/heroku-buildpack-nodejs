#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. The
# caller's flags are read from `$-` (the current shell); a `$(set +o)` capture runs in a
# command-substitution subshell where bash always forces errexit off, so it would later
# restore errexit as disabled even when the caller had it on. pipefail has no `$-` letter, so
# it is captured separately (it is reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__command_saved_flags="$-"
__command_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

# Runs a command, discarding its output unless it fails. On a non-zero exit the captured
# output is printed so the failure is still diagnosable, and the command's exit code is
# returned.
function utils::command::suppress_output() {
	local TMP_COMMAND_OUTPUT
	TMP_COMMAND_OUTPUT=$(mktemp)
	# shellcheck disable=SC2064 # expand TMP_COMMAND_OUTPUT now so the RETURN trap removes this exact temp file
	trap "rm -rf '${TMP_COMMAND_OUTPUT}' >/dev/null" RETURN

	"$@" >"${TMP_COMMAND_OUTPUT}" 2>&1 || {
		local exit_code="$?"
		cat "${TMP_COMMAND_OUTPUT}"
		return "${exit_code}"
	}
	return 0
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__command_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__command_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__command_saved_pipefail}"
unset __command_saved_flags __command_saved_pipefail
