#!/usr/bin/env bash

# Enable strict mode for ShellCheck's benefit, but restore the caller's options at the end of
# the file (see epilogue) so these don't bleed into the un-migrated scripts that source this
# lib. The caller's flags are read from `$-`, which reflects the *current* shell — a
# `$(set +o)` capture runs in a command-substitution subshell where bash always forces errexit
# off, so it would record (and later restore) errexit as disabled even when the caller had it
# enabled. `$-` has no letter for pipefail, so that one option is captured separately (it is
# reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__output_saved_flags="$-"
__output_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

ANSI_RED=$'\e[1;31m'
ANSI_YELLOW=$'\e[1;33m'
ANSI_RESET=$'\e[0m'

# Output a styled multi-line error message to stderr.
#
# Usage:
# ```
# output_error <<-EOF
# 	Error: The error summary.
#
# 	Detailed description.
# EOF
# ```
output::error() {
	echo >&2
	sed --unbuffered "s/^/${ANSI_RED} !     /" | sed --unbuffered "s/$/${ANSI_RESET}/" >&2
	echo >&2
}

output::step() {
	echo ""
	echo "-----> $*"
}

output::indent() {
	sed --unbuffered 's/^/       /'
}

# Prints a single informational line, indented to sit under the current `output::step` header.
# The counterpart to `output::indent` for one-off lines that aren't part of a piped command's
# output (replaces the legacy bare-`echo`-through-the-`output`-pipe idiom).
output::info() {
	echo "       $*"
}

output::warning() {
	echo >&2
	sed --unbuffered "s/^/${ANSI_YELLOW} !     /" | sed --unbuffered "s/$/${ANSI_RESET}/" >&2
	echo >&2
}

# Restore the sourcing shell's original options (see preamble) so strict mode doesn't leak
# into un-migrated callers. errexit/nounset come from the saved `$-`; pipefail from its own
# saved `set +o` line.
case "${__output_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__output_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__output_saved_pipefail}"
unset __output_saved_flags __output_saved_pipefail
