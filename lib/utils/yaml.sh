#!/usr/bin/env bash

# Strict mode. The bin/* entry points that source this lib run under the same options; the
# test runners disable errexit after sourcing (see test/unit and test/run-helpers) so this
# no longer needs an epilogue to restore the caller's options.
set -euo pipefail

# BP_DIR is a global set by the caller (bin/compile) and environment::get_os comes from lib/environment.sh,
# which is sourced first.
# shellcheck disable=SC2154
YQ="${BP_DIR}/lib/vendor/yq-4.52.4-$(environment::get_os)"

# Reads a yq expression from a YAML file, emitting an empty string for a missing file or an
# unreadable/unparseable one (mirrors utils::json::read's missing-file contract so callers that
# capture its output via `$(...)` under `inherit_errexit` can't be aborted by yq's non-zero exit).
function utils::yaml::read() {
	local file="$1"
	local key="$2"

	if test -f "${file}"; then
		"${YQ}" "${key}" "${file}" || echo ""
	else
		echo ""
	fi
}
