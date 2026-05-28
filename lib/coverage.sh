#!/usr/bin/env bash
# Coverage trace shim. Sourced from bin/compile and test/unit.
# No-op unless BUILDPACK_COVERAGE=1.
#
# Usage:
#   source lib/coverage.sh
#   coverage::enable "$BP_DIR" "$BUILD_DIR" "$ENV_DIR"
#
# This function-based design makes dependencies explicit and avoids
# relying on positional arg inheritance or BASH_SOURCE path manipulation.
#
# Activation sources, in order of precedence:
#   1. $BUILDPACK_COVERAGE in the current environment (docker test runs).
#   2. $ENV_DIR/BUILDPACK_COVERAGE file with content "1" (real Heroku
#      build dynos — the slug compiler delivers user config vars to
#      bin/compile via $ENV_DIR rather than the process environment).

coverage::enable() {
  local bp_dir="${1:?coverage::enable: BP_DIR required}"
  local build_dir="${2:-}"
  local env_dir="${3:-}"

  if [[ "${BUILDPACK_COVERAGE:-}" != "1" ]]; then
    if [[ -n "${env_dir}" ]] && [[ -f "${env_dir}/BUILDPACK_COVERAGE" ]] && [[ "$(cat "${env_dir}/BUILDPACK_COVERAGE")" == "1" ]]; then
      export BUILDPACK_COVERAGE=1
    else
      return 0
    fi
  fi

  : "${BUILDPACK_COVERAGE_DIR:=${build_dir:-/tmp}/.heroku/coverage}"
  mkdir -p "$BUILDPACK_COVERAGE_DIR"

  # Strip $bp_dir/ prefix from $BASH_SOURCE so traces use repo-relative paths.
  # The literal +COV: prefix lets the parser distinguish our records from any
  # other xtrace output that might leak in from sourced third-party scripts.
  # ${FUNCNAME[0]:-} reports the current function name, helping correlate
  # function declarations with their execution.
  export PS4="+COV:\${BASH_SOURCE#${bp_dir}/}:\${LINENO}:\${FUNCNAME[0]:-}: "

  # Per-process trace file. fd 19 is arbitrary but unlikely to collide.
  exec 19>>"${BUILDPACK_COVERAGE_DIR}/trace-$$.log"
  export BASH_XTRACEFD=19
  set -x
}
