#!/usr/bin/env bash

# Strict mode. The bin/* entry points that source this lib run under the same options; the
# test runners disable errexit after sourcing (see test/unit and test/run-helpers) so this
# no longer needs an epilogue to restore the caller's options.
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
