#!/usr/bin/env bash

calculate_concurrency() {
  WEB_CONCURRENCY=${WEB_CONCURRENCY-$((MEMORY_AVAILABLE/WEB_MEMORY))}
  if (( WEB_CONCURRENCY < 1 )); then
    WEB_CONCURRENCY=1
  elif (( WEB_CONCURRENCY > 200 )); then
    # Ex: This will happen on Dokku on DO
    WEB_CONCURRENCY=1
  fi
  echo $WEB_CONCURRENCY
}

log_concurrency() {
  echo "Detected $MEMORY_AVAILABLE MB available memory, $WEB_MEMORY MB limit per process (WEB_MEMORY)"
  echo "Recommending WEB_CONCURRENCY=$WEB_CONCURRENCY"
}

detect_memory() {
  local default=$1

  if [ -e /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    expr "$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)" / 1048576
  else
    echo "$default"
  fi
}

warn_bad_web_concurrency() {
  local concurrency=$((MEMORY_AVAILABLE/WEB_MEMORY))
  if [ "$concurrency" -gt "200" ]; then
    echo "Could not determine a reasonable value for WEB_CONCCURENCY.
This is likely due to running the Heroku NodeJS buildpack on a non-Heroku
platform.

WEB_CONCURRENCY has been set to 1. Please review whether this value is
appropriate for your application."
    echo ""
  fi
}

export MEMORY_AVAILABLE=${MEMORY_AVAILABLE-$(detect_memory 512)}
export WEB_MEMORY=${WEB_MEMORY-512}
export WEB_CONCURRENCY=$(calculate_concurrency)

warn_bad_web_concurrency

if [[ "${LOG_CONCURRENCY+isset}" && "$LOG_CONCURRENCY" == "true" ]]; then
  log_concurrency
fi
