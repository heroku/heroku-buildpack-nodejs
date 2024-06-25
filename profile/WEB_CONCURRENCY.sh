#!/usr/bin/env bash

calculate_concurrency() {
  local available=$1
  local web_memory=$2

  echo $(( available / web_memory ))
}

validate_concurrency() {
  local concurrency=$1
  local ret=0

  if (( concurrency < 1 )); then
    concurrency=1
  elif (( concurrency > 200 )); then
    # Ex: This will happen on Dokku on DO
    concurrency=1
    ret=1
  fi

  echo "$concurrency"
  return $ret
}

log_concurrency() {
  echo "Detected $MEMORY_AVAILABLE MB available memory, $WEB_MEMORY MB limit per process (WEB_MEMORY)"
  echo "Recommending WEB_CONCURRENCY=$WEB_CONCURRENCY"
}

detect_memory() {
  local default=$1

  local memory_limit
  memory_limit=$(cgroup_util_read_cgroup_memory_limit_with_fallback) && {
    echo $(( memory_limit / 1024 / 1024 ))
    return
  }

  if (($? == 99)); then
    dne_memory
  else
    echo "$default"
	fi
}

dne_memory() {
	echo "129024"
}

bound_memory() {
  local detected=$1
  # Memory is bound to the maximum memory of known dyno types: ~126 GB
  local max_detected_memory
  max_detected_memory=$(dne_memory)
  if (( detected > max_detected_memory )); then
    echo "$max_detected_memory"
  else
    echo "$detected"
  fi
}

default_web_memory() {
    local available_memory=$1
    # Allow more memory per process on memory heavy dyno types.
    if (( available_memory > 16384 )); then
        echo 2048
    else
        echo 512
    fi
}

warn_web_concurrency() {
  echo "Could not determine a reasonable value for WEB_CONCURRENCY.
This is likely due to running the Heroku Node.js buildpack on a non-Heroku
platform.

WEB_CONCURRENCY has been set to ${1}. Please review whether this value is
appropriate for your application.
"
}

DETECTED=$(detect_memory 512)
export MEMORY_AVAILABLE=${MEMORY_AVAILABLE-$(bound_memory "$DETECTED")}
export WEB_MEMORY=${WEB_MEMORY-$(default_web_memory "$MEMORY_AVAILABLE")}

# Calculate/validate WEB_CONCURRENCY if not already set
if [ -z "${WEB_CONCURRENCY}" ]; then
    calculated_concurrency=$(calculate_concurrency "$MEMORY_AVAILABLE" "$WEB_MEMORY")
    if ! validated_concurrency=$(validate_concurrency "$calculated_concurrency"); then
        warn_web_concurrency "$validated_concurrency"
    fi
    export WEB_CONCURRENCY=$validated_concurrency
fi

if [[ "${LOG_CONCURRENCY+isset}" && "$LOG_CONCURRENCY" == "true" ]]; then
  log_concurrency
fi
