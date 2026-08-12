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
# the only side-effecting layer; classifiers (e.g. package_managers::npm::_handle_npm_install_failure) stay pure
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

# Emits a buildpack-classified failure for the case where the tool inside a `tool | tee log`
# pipeline exited 0 but a downstream stage (typically `tee` writing to the log) failed — for
# example the build ran out of disk space. Callers pass a stable failure id, the PIPESTATUS
# array joined as a string (typically "${pipe_status[*]}") for observability, and the
# user-facing message. Records classification=buildpack and detail=PIPESTATUS=[...].
function failure::handle_pipefail() {
	local id="${1}"
	local pipe_status="${2}"
	local message="${3}"
	local -A failure=(
		[id]="${id}"
		[classification]="buildpack"
		[detail]="PIPESTATUS=[${pipe_status}]"
		[message]="${message}"
	)
	failure::emit failure
}

# Pure classifier for a private git dependency whose SSH host-key verification failed. This is
# a cross-cutting git-layer failure, not a single package-manager command: npm, yarn (classic
# and Berry), and pnpm all shell out to git to fetch a `git+ssh://` dependency, and a
# missing/untrusted host key surfaces the same `Host key verification failed.` line from ssh in
# the merged install log regardless of which package manager drove it. It is therefore shared
# across every install (and reinstall/prune) call site rather than living in a per-manager
# classifier.
#
# Input:
#   $1  path to a log file containing the captured output of the failed install command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when the host-key failure is recognised; returns 1 and leaves
# the array untouched otherwise. Has no side effects: it does not write build data, print to the
# build log, or exit. Mirrors the per-manager `_handle_*_failure` classifiers.
function failure::handle_git_auth_failure() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	# `Host key verification failed.` is printed by ssh (not the package manager) when git
	# fetches a `git+ssh://` dependency and the remote host key is not trusted. Preserve the
	# legacy `private-git-dependency-without-auth` build-data id verbatim for observability
	# continuity.
	if grep -qi "Host key verification failed" "${log_file}"; then
		__failure["id"]="private-git-dependency-without-auth"
		__failure["classification"]="user"
		__failure["detail"]="$(failure::_extract_git_auth_detail "${log_file}")"
		__failure["message"]=$(
			cat <<-EOF
				Error: Unable to install a git dependency over SSH.

				One of your dependencies points at a private git repository over SSH
				(git+ssh://), and the host key / SSH authentication was not available during
				the build. Heroku builds do not have access to your SSH keys, so they cannot
				authenticate to a private git remote.

				Update the dependency to use an https git URL with an access token, or point
				it at a published version on a package registry, then redeploy.
			EOF
		)
		return 0
	fi

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

# Returns the first descriptive host-key line for use as failure detail: the first
# `Host key verification failed` line, with any package-manager prefix (`npm error`/`npm ERR!`,
# yarn/berry framing) and leading indentation stripped so the detail carries just the descriptive
# text. `|| true` so a no-match never trips errexit. Internal helper to
# failure::handle_git_auth_failure; not meant to be called directly.
function failure::_extract_git_auth_detail() {
	local log_file="${1}"
	grep -i "Host key verification failed" "${log_file}" \
		| head -n 1 \
		| sed -E 's/^(npm (ERR!|error)|error|warning|➤[[:space:]]*YN[0-9]{4}:)[[:space:]]*//I' \
		| sed -E 's/^[│├└┌─┐┘[:space:]]+//' \
		|| true
}

# Restore the sourcing shell's original options (see preamble) so strict mode doesn't leak
# into un-migrated callers. errexit/nounset come from the saved `$-`; pipefail from its own
# saved `set +o` line.
case "${__failures_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__failures_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__failures_saved_pipefail}"
unset __failures_saved_flags __failures_saved_pipefail
