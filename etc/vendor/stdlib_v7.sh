# Buildpack defaults
# ---------------

export BUILDPACK_LOG_FILE=${BUILDPACK_LOG_FILE:-/dev/null}

# Standard Output
# ---------------

# Buildpack Steps.
puts_step() {
  if [[ "$@" == "-" ]]; then
    read output
  else
    output=$@
  fi
  echo -e "\e[1m\e[36m=== $output\e[0m"
  unset output
}

# Buildpack Error.
puts_error() {
  if [[ "$@" == "-" ]]; then
    read output
  else
    output=$@
  fi
  echo -e "\e[1m\e[31m=!= $output\e[0m"
}

# Buildpack Warning.
puts_warn() {
  if [[ "$@" == "-" ]]; then
    read output
  else
    output=$@
  fi
  echo -e "\e[1m\e[33m=!= $output\e[0m"
}


# Buildpack Utilities
# -------------------

# Usage: $ set-env key value
# NOTICE: Expects PROFILE_PATH & EXPORT_PATH to be set!
set_env() {
  # TODO: automatically create profile path directory if it doesn't exist.
  echo "export $1=$2" >> $PROFILE_PATH
  echo "export $1=$2" >> $EXPORT_PATH
}

# Usage: $ set-default-env key value
# NOTICE: Expects PROFILE_PATH & EXPORT_PATH to be set!
set_default_env() {
  echo "export $1=\${$1:-$2}" >> $PROFILE_PATH
  echo "export $1=\${$1:-$2}" >> $EXPORT_PATH
}

# Usage: $ un-set-env key
# NOTICE: Expects PROFILE_PATH to be set!
un_set_env() {
  echo "unset $1" >> $PROFILE_PATH
}

# Usage: $ _env-blacklist pattern
# Outputs a regex of default blacklist env vars.
_env_blacklist() {
  local regex=${1:-''}
  if [ -n "$regex" ]; then
    regex="|$regex"
  fi
  echo "^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH$regex)$"
}

# Usage: $ export-env ENV_DIR WHITELIST BLACKLIST
# Exports the environment variables defined in the given directory.
export_env() {
  local env_dir=${1:-$ENV_DIR}
  local whitelist=${2:-''}
  local blacklist="$(_env_blacklist $3)"
  if [ -d "$env_dir" ]; then
    for e in $(ls $env_dir); do
      echo "$e" | grep -E "$whitelist" | grep -qvE "$blacklist" &&
      export "$e=$(cat $env_dir/$e)"
      :
    done
  fi
}

# Usage: $ sub-env command
# Runs a subshell of specified command with user-provided config.
# NOTICE: Expects ENV_DIR to be set. WHITELIST & BLACKLIST are optional.
# Examples:
#    WHITELIST=${2:-''}
#    BLACKLIST=${3:-'^(GIT_DIR|PYTHONHOME|LD_LIBRARY_PATH|LIBRARY_PATH|PATH)$'}
sub_env() {
  (
    export_env $ENV_DIR $WHITELIST $BLACKLIST

    $1
  )
}

# Logging
# -------

# Notice: These functions expect BPLOG_PREFIX and BUILDPACK_LOG_FILE to be defined (BUILDPACK_LOG_FILE can point to /dev/null if not provided by the buildpack).
# Example: BUILDPACK_LOG_FILE=${BUILDPACK_LOG_FILE:-/dev/null}; BPLOG_PREFIX="buildpack.go"

# Returns now, in milleseconds. Useful for logging.
# Example: $ let start=$(nowms); sleep 30; mtime "glide.install.time" "${start}"
nowms() {
    date +%s%3N
}

# Log arbitrary data to the logfile (e.g. a packaging file).
# Usage: $ bplog "$(<${vendorJSON})
bplog() {
  echo -n ${@} | awk 'BEGIN {printf "msg=\""; f="%s"} {gsub(/"/, "\\\"", $0); printf f, $0} {if (NR == 1) f="\\n%s" } END { print "\"" }' >> ${BUILDPACK_LOG_FILE}
}

# Measures time elapsed for a specific build step.
# Usage: $ let start=$(nowms); mtime "glide.install.time" "${start}"
# https://github.com/heroku/engineering-docs/blob/master/guides/logs-as-data.md#distributions-measure
mtime() {
    local key="${BPLOG_PREFIX}.${1}"
    local start="${2}"
    local end="${3:-$(nowms)}"
    echo "${key} ${start} ${end}" | awk '{ printf "measure#%s=%.3f\n", $1, ($3 - $2)/1000 }' >> ${BUILDPACK_LOG_FILE}
}

# Logs a count for a specific built step.
# Usage: $ mcount "tool.govendor"
# https://github.com/heroku/engineering-docs/blob/master/guides/logs-as-data.md#counting-count
mcount() {
    local k="${BPLOG_PREFIX}.${1}"
    local v="${2:-1}"
    echo "count#${k}=${v}" >> ${BUILDPACK_LOG_FILE}
}

# Logs a measure for a specific build step.
# Usage: $ mmeasure "tool.installed_dependencies" 42
# https://github.com/heroku/engineering-docs/blob/master/guides/logs-as-data.md#distributions-measure
mmeasure() {
    local k="${BPLOG_PREFIX}.${1}"
    local v="${2}"
    echo "measure#${k}=${v}" >> ${BUILDPACK_LOG_FILE}
}

# Logs a unuique measurement build step.
# Usage: $ munique "versions.count" 2.7.13
# https://github.com/heroku/engineering-docs/blob/master/guides/logs-as-data.md#uniques-unique
munique() {
    local k="${BPLOG_PREFIX}.${1}"
    local v="${2}"
    echo "unique#${k}=${v}" >> ${BUILDPACK_LOG_FILE}
}

# Measures when an exit path to the buildpack is reached, given a name, then exits 1.
# Usage: $ mcount-exi "binExists"
mcount_exit() {
    mcount "error.${1}"
    exit 1
}
