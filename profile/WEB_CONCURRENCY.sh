#!/usr/bin/env bash

calculate_concurrency() {
  local available=$1
  local web_memory=$2
  local concurrency

  concurrency=${WEB_CONCURRENCY-$(($available/$web_memory))}
  if (( concurrency < 1 )); then
    concurrency=1
  elif (( concurrency > 200 )); then
    # Ex: This will happen on Dokku on DO
    concurrency=1
  fi
  echo "$concurrency"
}

log_concurrency() {
  echo "Detected $MEMORY_AVAILABLE MB available memory, $WEB_MEMORY MB limit per process (WEB_MEMORY)"
  echo "Recommending WEB_CONCURRENCY=$WEB_CONCURRENCY"
}

detect_memory() {
  local default=$1

  if [ -e /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    echo $(($(cat /sys/fs/cgroup/memory/memory.limit_in_bytes) / 1048576))
  else
    echo "$default"
  fi
}

bound_memory() {
  local detected=$1
  local detected max_detected_memory=14336

  # The hardcoded value is 16GB of memory
  if (( detected > max_detected_memory )); then
    echo "$max_detected_memory"
  else
    echo "$detected"
  fi
}

warn_bad_web_concurrency() {
  local concurrency=$((MEMORY_AVAILABLE/WEB_MEMORY))
  if [ "$concurrency" -gt "200" ]; then
    echo "Could not determine a reasonable value for WEB_CONCURRENCY.
This is likely due to running the Heroku NodeJS buildpack on a non-Heroku
platform.

WEB_CONCURRENCY has been set to 1. Please review whether this value is
appropriate for your application."
    echo ""
  fi
}

DETECTED=$(detect_memory 512)
export MEMORY_AVAILABLE=${MEMORY_AVAILABLE-$(bound_memory $DETECTED)}
export WEB_MEMORY=${WEB_MEMORY-512}
export WEB_CONCURRENCY=$(calculate_concurrency $MEMORY_AVAILABLE $WEB_MEMORY)

warn_bad_web_concurrency

if [[ "${LOG_CONCURRENCY+isset}" && "$LOG_CONCURRENCY" == "true" ]]; then
  log_concurrency
fi
