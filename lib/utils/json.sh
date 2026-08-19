#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. See
# lib/package_managers/npm.sh for the full rationale on reading $- vs $(set +o).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__json_saved_flags="$-"
__json_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

# Reads a jq expression from a JSON file, emitting an empty string for a missing file or a
# null/absent key.
function utils::json::read() {
	local file="$1"
	local key="$2"

	if test -f "${file}"; then
		# -c = print on only one line
		# -M = strip any color
		# --raw-output = if the filter’s result is a string then it will be written directly
		#                to stdout rather than being formatted as a JSON string with quotes
		# `|| echo ""`: on a jq error (e.g. the key resolves to a non-string type, which `// ""` can't
		# coerce, or malformed JSON) degrade to an empty string rather than a hard failure. This
		# matches the missing-file branch below and the sibling utils::yaml::read, and — critically
		# under inherit_errexit — keeps a bad read from tripping the ERR trap and poisoning the failure
		# marker at an unrelated call site.
		# shellcheck disable=SC2002
		cat "${file}" | jq -c -M --raw-output "${key} // \"\"" || echo ""
	else
		echo ""
	fi
}

# Returns success (0) if the file is parseable JSON, failure otherwise. Use it as a condition
# (e.g. `if ! utils::json::is_valid "${file}"; then …`), not by capturing its output.
function utils::json::is_valid() {
	local file="$1"
	# shellcheck disable=SC2002
	cat "${file}" | jq "." 1>/dev/null
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__json_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__json_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__json_saved_pipefail}"
unset __json_saved_flags __json_saved_pipefail
