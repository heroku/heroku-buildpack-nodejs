#!/usr/bin/env bash

# Strict mode. The bin/* entry points that source this lib run under the same options; the
# test runners disable errexit after sourcing (see test/unit and test/run-helpers) so this
# no longer needs an epilogue to restore the caller's options.
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
		output::indent <"${TMP_COMMAND_OUTPUT}"
		return "${exit_code}"
	}
	return 0
}
