export PATH="$HOME/.heroku/node/bin:$HOME/.heroku/yarn/bin:$PATH:$HOME/bin:$HOME/node_modules/.bin"
export NODE_HOME="$HOME/.heroku/node"
export NODE_ENV=${NODE_ENV:-production}
export COREPACK_HOME="$HOME/.heroku/corepack"


# If the user has opted into the feature
if [[ -n "$HEROKU_METRICS_URL" ]] && \
   # if we're not on a one-off dyno
   [[ "${DYNO}" != run\.* ]] && \
   # the user has not opted out
   [[ -z "$HEROKU_SKIP_NODE_PLUGIN" ]]; then

  if [[ -d $HOME/.heroku/heroku-nodejs-plugin ]]; then
    # if the plugin was installed for this node version
    metrics_handler="$HOME/.heroku/heroku-nodejs-plugin"
  elif [[ -d $HOME/.heroku/metrics ]]; then
    # or if the metrics script was installed
    metrics_handler="$HOME/.heroku/metrics/metrics_collector.cjs"
  else
    return
  fi

  # Don't clobber NODE_OPTIONS if the user has set it, just add the require flag to the end
  if [[ -z "$NODE_OPTIONS" ]]; then
    export NODE_OPTIONS="--require $metrics_handler"
  else
    export NODE_OPTIONS="${NODE_OPTIONS} --require $metrics_handler"
  fi
fi
