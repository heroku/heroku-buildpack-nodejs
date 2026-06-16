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

# Builds a validatable JSON classification object from a multi-line message passed on stdin.
#
# The message body is read from stdin (typically a here-document) so that error text can be
# authored in the familiar heredoc style without hand-escaping JSON. Doc/help URLs go inline
# in the message body; there is no separate URL field.
#
# Usage:
# ```
# failure::message --reason "install-dependencies::npm" --detail "EBADPLATFORM" \
#   --classification "user" <<-EOF
#     Error: ...
#   EOF
# ```
function failure::message() {
	local reason="" detail="" classification=""

	while (("$#")); do
		case "${1}" in
			--reason)
				reason="${2}"
				shift 2
				;;
			--detail)
				detail="${2}"
				shift 2
				;;
			--classification)
				classification="${2}"
				shift 2
				;;
			*)
				echo "failure::message: unknown argument '${1}'" >&2
				return 1
				;;
		esac
	done

	# `--rawfile` ingests the stdin heredoc body verbatim as a JSON string, so newlines and
	# special characters are encoded safely without manual escaping.
	jq -n --rawfile message /dev/stdin \
		--arg reason "${reason}" \
		--arg detail "${detail}" \
		--arg classification "${classification}" \
		'{
			failure_reason: $reason,
			failure_detail: $detail,
			failure_classification: $classification,
			message: $message
		}'
}

# Renders a classification object (produced by failure::message / a handler), records the
# failure in build data, and exits the build. This is the only side-effecting layer.
#
# Usage:
# ```
# failure::emit "${classification_json}"
# ```
function failure::emit() {
	local json="${1}"
	local reason detail classification message

	reason=$(echo "${json}" | jq -r '.failure_reason')
	detail=$(echo "${json}" | jq -r '.failure_detail')
	classification=$(echo "${json}" | jq -r '.failure_classification')
	message=$(echo "${json}" | jq -r '.message')

	# Print to stderr so the message bypasses any stdout pipes (e.g. `| output "$LOG_FILE"`).
	echo "${message}" | output::error

	build_data::set_string "failure" "${reason}"
	[[ -n "${detail}" ]] && build_data::set_string "failure_detail" "${detail}"
	[[ -n "${classification}" ]] && build_data::set_string "failure_classification" "${classification}"

	fail
}

# Restore the sourcing shell's original options (see preamble) so strict mode doesn't leak
# into un-migrated callers. errexit/nounset come from the saved `$-`; pipefail from its own
# saved `set +o` line.
case "${__failures_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__failures_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__failures_saved_pipefail}"
unset __failures_saved_flags __failures_saved_pipefail
