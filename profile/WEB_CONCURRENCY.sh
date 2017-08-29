#!/usr/bin/env bash

calculate_concurrency() {
  WEB_CONCURRENCY=${WEB_CONCURRENCY-$((MEMORY_AVAILABLE/WEB_MEMORY))}
  if (( WEB_CONCURRENCY < 1 )); then
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
  local limit=$(ulimit -u)

  case $limit in
    256) echo "512";;      # Standard-1X
    512) echo "1024";;     # Standard-2X
    16384) echo "2560";;   # Performance-M
    32768) echo "14336";;  # Performance-L
    *) echo "$default";;
  esac
}

export MEMORY_AVAILABLE=${MEMORY_AVAILABLE-$(detect_memory 512)}
export WEB_MEMORY=${WEB_MEMORY-512}
export WEB_CONCURRENCY=$(calculate_concurrency)

if [ "$LOG_CONCURRENCY" = "true" ]; then
  log_concurrency
fi
