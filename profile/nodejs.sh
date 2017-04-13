calculate_concurrency() {
  local memory_available=$1
  local web_memory=$2
  local concurrency=$((memory_available/web_memory))

  if (( concurrency < 1 )); then
    concurrency=1
  fi

  # We prepend the calculated value with a leading '0' so that other buildpacks
  # can distinguish between a value set by the Node buildpack  and a value set 
  # by the user
  echo "0$concurrency"
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

export PATH="$HOME/.heroku/node/bin:$HOME/.heroku/yarn/bin:$PATH:$HOME/bin:$HOME/node_modules/.bin"
export NODE_HOME="$HOME/.heroku/node"
export NODE_ENV=${NODE_ENV:-production}

export MEMORY_AVAILABLE=${MEMORY_AVAILABLE:-$(detect_memory 512)}
export WEB_MEMORY=${WEB_MEMORY:-512}

# if the user hasn't set a value for WEB_CONCURRENCY we compute a reasonable value
export WEB_CONCURRENCY=${WEB_CONCURRENCY:-$(calculate_concurrency $MEMORY_AVAILABLE $WEB_MEMORY)}

if [ "$LOG_CONCURRENCY" = "true" ]; then
  log_concurrency
fi
