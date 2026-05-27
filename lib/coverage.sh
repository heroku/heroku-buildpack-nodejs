#!/usr/bin/env bash
# Coverage trace shim. Sourced from bin/compile and test/unit.
# No-op unless BUILDPACK_COVERAGE=1.
#
# Caller contract:
#   - BP_DIR must be set to the buildpack root before sourcing this file.
#   - BUILDPACK_COVERAGE_DIR may be set to override the trace output dir.
#     Defaults to $BUILD_DIR/.heroku/coverage when running under bin/compile.

if [[ "${BUILDPACK_COVERAGE:-}" != "1" ]]; then
  return 0
fi

: "${BUILDPACK_COVERAGE_DIR:=${BUILD_DIR:-/tmp}/.heroku/coverage}"
mkdir -p "$BUILDPACK_COVERAGE_DIR"

# Strip $BP_DIR/ prefix from $BASH_SOURCE so traces use repo-relative paths.
# The literal +COV: prefix lets the parser distinguish our records from any
# other xtrace output that might leak in from sourced third-party scripts.
export PS4='+COV:${BASH_SOURCE#${BP_DIR}/}:${LINENO}: '

# Per-process trace file. fd 19 is arbitrary but unlikely to collide.
exec 19>>"${BUILDPACK_COVERAGE_DIR}/trace-$$.log"
export BASH_XTRACEFD=19
set -x
