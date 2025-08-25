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
