#!/usr/bin/env bash

# Strict mode. The bin/* entry points that source this lib run under the same options; the
# test runners disable errexit after sourcing (see test/unit and test/run-helpers) so this
# no longer needs an epilogue to restore the caller's options.
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
		# `|| echo ""`: on a jq error (e.g. indexing into a value of the wrong type, which `// ""` does
		# not rescue since it only substitutes null/false, or malformed JSON) degrade to an empty
		# string rather than a hard failure. This
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
