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

	# Signal that this failure is fully handled so the generic ERR-trap fallback (failure::handle_uncaught)
	# ignores it and doesn't re-report it. A file (not a variable) because emit may run inside a
	# subshell (e.g. the left side of `build_dependencies | output`) where the trap, running in
	# the parent shell, would never see a variable assignment.
	[[ -n "${FAILURE_EMITTED_MARKER:-}" ]] && : >"${FAILURE_EMITTED_MARKER}"

	fail
}

# Generic, last-resort ERR-trap handler for any non-zero exit that no migrated code path
# classified — including a user's own build script failing. Modelled on the fully-migrated
# Python buildpack's `utils::err_trap`: it renders a neutral "internal error" message with a
# stack trace, records a generic failure reason for observability, and terminates the build.
# Because this repo does not enable `errtrace`, a command failing inside this handler will not
# re-trigger the ERR trap, so no recursion guard beyond the marker check below is needed.
function failure::handle_uncaught() {
	# A migrated code path may have already classified, rendered, and recorded this failure via
	# `failure::emit` (which writes this marker). If so, stay quiet so it isn't reported twice.
	[[ -e "${FAILURE_EMITTED_MARKER:-}" ]] && return

	# Capture the failing command from BASH_COMMAND before the work below overwrites it. The
	# marker guard above is a bare `[[ ]]` test, so it does not disturb BASH_COMMAND.
	local failing_command="${BASH_COMMAND}"

	local stack_trace
	stack_trace=$(
		local frame=0
		while read -r line_number function_name source_file < <(caller "${frame}" || true); do
			echo "${function_name} @ ${source_file}:${line_number}"
			((++frame))
		done
	)

	header "Build failed"
	output::error <<-EOF
		An unexpected error occurred while building your app.

		Review the build log above for the cause. If this looks like a bug in the
		buildpack rather than your app, open a support ticket:
		https://help.heroku.com/

		Failing command:
		${failing_command}

		Stack trace:
		${stack_trace}
	EOF

	# Record a generic failure reason for observability. The classification is intentionally left
	# unset: this handler fires for any unclassified failure, so we can't attribute it to the
	# user, the buildpack, or upstream.
	build_data::set_string "failure" "internal-error"
	build_data::set_string "failure_detail" "${failing_command}"

	# Write the marker then call `fail`, exactly like `failure::emit`, so `build_time` is recorded
	# on every failure path and the build always exits non-zero.
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

# Pure classifier for a network connection reset while communicating with a remote server
# (ECONNRESET). This is a cross-cutting network-layer failure, not a single package-manager
# error code: npm, yarn (classic and Berry), and pnpm can all hit it while installing,
# rebuilding, or pruning dependencies, or while running a build-script lifecycle hook. It is
# therefore shared across every call site rather than living in a per-manager classifier.
# Mirrors failure::handle_git_auth_failure. Checked as a LAST-RESORT fallback at every call
# site — after the site's tool-specific classifier — because a transient ECONNRESET retry can
# appear in the same log as an unrelated, permanent failure the tool-specific classifier owns.
#
# Input:
#   $1  path to a log file containing the captured output of the failed command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when a TERMINAL ECONNRESET is recognised (not a retry-warning
# line); returns 1 and leaves the array untouched otherwise. Has no side effects: it does not
# write build data, print to the build log, or exit.
function failure::handle_econnreset() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	# Match only a TERMINAL/fatal ECONNRESET, not the retry-warning noise every tool logs while
	# it is still retrying a request. A bare `grep -qi "econnreset"` also matches those retry
	# lines, so a build that retries past a transient reset and then fails for an unrelated,
	# permanent reason (e.g. npm EBADPLATFORM) would be misclassified as "just retry" instead of
	# surfacing the real cause.
	#
	# Each alternative below is a tool's TERMINAL form, not its retry form:
	#   - npm: the `npm ERR!`/`npm error` summary line (`code ECONNRESET`, npm <=7/>=8) or its
	#     `network` block, which only prints once retries are exhausted. Excludes `npm warn` and
	#     `npm http fetch ... attempt N ...` retry noise (neither is ERR!/error-prefixed).
	#   - yarn classic: an `error `-prefixed line (the same severity prefix yarn uses for other
	#     fatal failures; see failure::_extract_git_auth_detail).
	#   - yarn Berry: a `YN####:` report line (Berry has no separate retry-warning line format
	#     for a network reset).
	#   - pnpm: an `ERR_PNPM_*` error code, or a line whose severity marker at the START of the
	#     line is `ERROR`. Anchoring to the start of the line excludes pnpm's
	#     `WARN  GET ... error (ECONNRESET), will retry` line, which only has "error" as prose
	#     inside the message, not as its severity marker.
	if grep -qiE '^npm (ERR!|error) (code ECONNRESET|network.*ECONNRESET)|^error .*ECONNRESET|YN[0-9]{4}:.*ECONNRESET|ERR_PNPM_[A-Z_]+.*ECONNRESET|^[[:space:]]*ERROR[[:space:]].*ECONNRESET' "${log_file}"; then
		__failure["id"]="econnreset"
		__failure["classification"]="upstream"
		__failure["message"]=$(
			cat <<-EOF
				Error: A network connection was reset while communicating with a remote server (ECONNRESET).

				This is usually a transient upstream or registry issue — retrying the build often
				resolves it.
			EOF
		)
		return 0
	fi

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

# Pure classifier for a Node.js binary that is not compatible with the current stack's glibc
# (the dynamic linker reports a missing `GLIBC_x.y` version). This is a cross-cutting
# runtime-layer failure, not a single package-manager error code: it can surface from any
# package manager's install/rebuild/prune, or from a build-script lifecycle hook, since it's
# the Node.js binary itself (not the package manager) that fails to even start. It is therefore
# shared across every call site rather than living in a per-manager classifier. Mirrors
# failure::handle_git_auth_failure.
#
# Input:
#   $1  path to a log file containing the captured output of the failed command
#   $2  name of an associative array to fill (see failure::emit for its fields)
# Returns 0 and fills the array when the glibc incompatibility is recognised; returns 1 and
# leaves the array untouched otherwise. Has no side effects: it does not write build data,
# print to the build log, or exit.
function failure::handle_libc6_incompatibility() {
	local log_file="${1}"
	# shellcheck disable=SC2178 # nameref alias to the caller's associative array, not a string
	local -n __failure="${2}"

	# Preserve the legacy `libc6-incompatibility` build-data id and message verbatim for
	# observability and user-facing continuity.
	if grep -qP "version \`GLIBC_\d+\.\d+' not found" "${log_file}"; then
		__failure["id"]="libc6-incompatibility"
		__failure["classification"]="user"
		__failure["message"]=$(
			cat <<-EOF
				This Node.js version is not compatible with the current stack.

				For Node.js versions 18 and greater, heroku-22 or newer is required.
				Consider updating to a stack that is compatible with the Node.js version
				or pinning the Node.js version to be compatible with the current
				stack.
				https://help.heroku.com/R7DTSTD0
			EOF
		)
		return 0
	fi

	# No known failure mode recognised — signal no match so the caller can fall through.
	return 1
}

# Restore the sourcing shell's original options (see preamble) so strict mode doesn't leak
# into un-migrated callers. errexit/nounset come from the saved `$-`; pipefail from its own
# saved `set +o` line.
case "${__failures_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__failures_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__failures_saved_pipefail}"
unset __failures_saved_flags __failures_saved_pipefail
