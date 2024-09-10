#!/usr/bin/env bash

export PATH="$HOME/.heroku/node/bin:$HOME/.heroku/yarn/bin:$PATH:$HOME/bin:$HOME/node_modules/.bin"
export NODE_HOME="$HOME/.heroku/node"
export NODE_ENV=${NODE_ENV:-test}
export COREPACK_HOME="$HOME/.heroku/corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
