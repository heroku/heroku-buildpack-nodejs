export PATH="$HOME/.heroku/node/bin:$HOME/.heroku/yarn/bin:$PATH:$HOME/bin:$HOME/node_modules/.bin"
export NODE_HOME="$HOME/.heroku/node"
export NODE_ENV=${NODE_ENV:-production}

# If the user has opted into the feature
if [[ -n "$HEROKU_METRICS_URL" ]] && \
   # if we're not on a one-off dyno
   [[ "${DYNO}" != run\.* ]] && \
   # if the plugin was installed for this node version
   [[ -d $HOME/.heroku/heroku-nodejs-plugin ]] && \
   # the user has not opted out
   [[ -z "$HEROKU_SKIP_NODE_PLUGIN" ]]; then

  # Don't clobber NODE_OPTIONS if the user has set it, just add the require flag to the end
  if [[ -z "$NODE_OPTIONS" ]]; then
      export NODE_OPTIONS="--require $HOME/.heroku/heroku-nodejs-plugin"
  else
      export NODE_OPTIONS="${NODE_OPTIONS} --require $HOME/.heroku/heroku-nodejs-plugin"
  fi

fi

# because the default OpenSSL v3 config in Ubuntu gets read by Node.js's bundled OpenSSL 1.1.1o
# we need to use the patched config that was created during the compile step
if [[ -f "$(pwd)/openssl.cnf" ]]; then
  export OPENSSL_CONF="$(pwd)/openssl.cnf"
fi
