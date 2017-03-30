calculate_concurrency() {
  MEMORY_AVAILABLE=${MEMORY_AVAILABLE-$(detect_memory 512)}
  WEB_MEMORY=${WEB_MEMORY-512}
  WEB_CONCURRENCY=${WEB_CONCURRENCY-$((MEMORY_AVAILABLE/WEB_MEMORY))}
  if (( WEB_CONCURRENCY < 1 )); then
    WEB_CONCURRENCY=1
  fi
  WEB_CONCURRENCY=$WEB_CONCURRENCY
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

detect_node_opts() {
    local mem

    if (( ENV_WEB_MEMORY > 0 )); then
      # WEB_MEMORY was manually set, assume user knows what they are doing
      mem=${ENV_WEB_MEMORY}
    else
        # WEB_MEMORY was not set, optimize node memory for concurrency and available memory
      mem=$((MEMORY_AVAILABLE / WEB_CONCURRENCY))
    fi

    local old_space=$((mem / 10 * 9)) # max old space size ~90% of available

    echo "--optimize_for_size --max_old_space_size=$old_space --gc_interval=100"
}

export PATH="$HOME/.heroku/node/bin:$HOME/.heroku/yarn/bin:$PATH:$HOME/bin:$HOME/node_modules/.bin"
export NODE_HOME="$HOME/.heroku/node"
export NODE_ENV=${NODE_ENV:-production}

ENV_WEB_MEMORY=${WEB_MEMORY-0}

calculate_concurrency

export MEMORY_AVAILABLE=$MEMORY_AVAILABLE
export WEB_MEMORY=$WEB_MEMORY
export WEB_CONCURRENCY=$WEB_CONCURRENCY

export NODE_OPTS=${NODE_OPTS-$(detect_node_opts)}

if [ "$LOG_CONCURRENCY" = "true" ]; then
  log_concurrency
fi
