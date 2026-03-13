#!/usr/bin/env bash

# Node.js version lifecycle data.
# EOL dates sourced from the official Node.js release schedule:
# https://raw.githubusercontent.com/nodejs/Release/main/schedule.json
#
# Format: NODEJS_VERSION_STATUS[major]="status|eol_date"
# Status values: current, active_lts, maintenance_lts, eol

declare -A NODEJS_VERSION_STATUS

# NOTE: Node.js "skipped" v1-v3 because those version numbers were used by a
#       fork of Node called io.js and when the two projects merged back together
#       they continued from io.js's latest major version (3.x) and called the
#       merged release Node.js v4.
#       See - https://nodejs.org/en/blog/announcements/foundation-v4-announce/

# Currently supported releases
# https://devcenter.heroku.com/articles/nodejs-support#supported-node-js-versions
NODEJS_VERSION_STATUS[25]="current|June 1, 2026"
NODEJS_VERSION_STATUS[24]="active_lts|April 30, 2028"
NODEJS_VERSION_STATUS[22]="maintenance_lts|April 30, 2027"
NODEJS_VERSION_STATUS[20]="maintenance_lts|April 30, 2026" # When this version reaches EOL, consider setting status to "eol_grace" first to give users a warning grace period before transitioning to "eol" which can fail builds (TODO: eol-grace implementation)

# Even numbered releases are stable, have extended support, and are recommended for production use
NODEJS_VERSION_STATUS[18]="eol|April 30, 2025"
NODEJS_VERSION_STATUS[16]="eol|September 11, 2023" # EOL moved earlier than normal due to OpenSSL 1.1.1 (https://nodejs.org/en/blog/announcements/nodejs16-eol)
NODEJS_VERSION_STATUS[14]="eol|April 30, 2023"
NODEJS_VERSION_STATUS[12]="eol|April 30, 2022"
NODEJS_VERSION_STATUS[10]="eol|April 30, 2021"
NODEJS_VERSION_STATUS[8]="eol|December 31, 2019"   # EOL moved earlier than normal due to OpenSSL 1.0.2
NODEJS_VERSION_STATUS[6]="eol|April 30, 2019"
NODEJS_VERSION_STATUS[4]="eol|April 30, 2018"
NODEJS_VERSION_STATUS[0]="eol|December 31, 2016"   # Covers v0.8, v0.10, and v0.12 — treated as equivalent for support messaging

# Odd numbered releases are experimental, short-lived, and not recommended for
# production use
NODEJS_VERSION_STATUS[23]="eol|June 1, 2025"
NODEJS_VERSION_STATUS[21]="eol|June 1, 2024"
NODEJS_VERSION_STATUS[19]="eol|June 1, 2023"
NODEJS_VERSION_STATUS[17]="eol|June 1, 2022"
NODEJS_VERSION_STATUS[15]="eol|June 1, 2021"
NODEJS_VERSION_STATUS[13]="eol|June 1, 2020"
NODEJS_VERSION_STATUS[11]="eol|June 1, 2019"
NODEJS_VERSION_STATUS[9]="eol|June 30, 2018"
NODEJS_VERSION_STATUS[7]="eol|June 30, 2017"
NODEJS_VERSION_STATUS[5]="eol|June 30, 2016"

NODEJS_SUPPORT_URL="https://devcenter.heroku.com/articles/nodejs-support#supported-node-js-versions"

format_supported_versions() {
  local result=""
  local major status_entry node_status label

  # Collect supported versions, sort numerically
  for major in $(echo "${!NODEJS_VERSION_STATUS[@]}" | tr ' ' '\n' | sort -n); do
    status_entry="${NODEJS_VERSION_STATUS[$major]}"
    node_status="${status_entry%%|*}"
    case "$node_status" in
      current) label="Current" ;;
      active_lts|maintenance_lts) label="LTS" ;;
      *) continue ;;
    esac
    if [[ -n "$result" ]]; then
      result="${result}, "
    fi
    result="${result}${major}.x (${label})"
  done
  echo "$result"
}

format_lts_versions() {
  local result=""
  local major status_entry node_status

  for major in $(echo "${!NODEJS_VERSION_STATUS[@]}" | tr ' ' '\n' | sort -n); do
    status_entry="${NODEJS_VERSION_STATUS[$major]}"
    node_status="${status_entry%%|*}"
    case "$node_status" in
      active_lts|maintenance_lts)
        if [[ -n "$result" ]]; then
          result="${result}, "
        fi
        result="${result}${major}.x"
        ;;
    esac
  done
  echo "$result"
}

check_nodejs_support_status() {
  local major_version="$1"
  local ignore_eol_error="${IGNORE_EOL_ERROR_NODEJS:-true}"

  local status_entry="${NODEJS_VERSION_STATUS[$major_version]:-}"

  # Unknown version - no warning
  if [[ -z "$status_entry" ]]; then
    return 0
  fi

  local node_status="${status_entry%%|*}"
  local eol_date="${status_entry#*|}"

  # Supported version - no warning
  if [[ "$node_status" != "eol" ]]; then
    return 0
  fi

  if [[ "$ignore_eol_error" == "true" ]]; then
    # Emit warning but allow build to continue
    local supported_versions
    supported_versions=$(format_supported_versions)

    cat <<EOF

 !     Node.js ${major_version}.x reached end-of-life on ${eol_date} and is no longer
 !     supported on Heroku. EOL versions no longer receive security updates
 !     or bug fixes from the Node.js project.
 !
 !     In a future buildpack release, this warning will become a build error.
 !     Please upgrade to a supported version as soon as possible to avoid
 !     build failures.
 !
 !     Supported versions: ${supported_versions}
 !
 !     ${NODEJS_SUPPORT_URL}

EOF
    return 0
  else
    # Emit error and fail the build
    local lts_versions
    lts_versions=$(format_lts_versions)

    cat <<EOF

 !     Node.js version not supported
 !
 !     Node.js ${major_version}.x reached end-of-life on ${eol_date} and is no longer
 !     supported on Heroku.
 !
 !     Suggestions:
 !     - Upgrade to a supported LTS version (${lts_versions})
 !     - Set the IGNORE_EOL_ERROR_NODEJS=true config var to temporarily
 !       bypass this check
 !
 !     ${NODEJS_SUPPORT_URL}

EOF
    return 1
  fi
}
