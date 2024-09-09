#!/usr/bin/env bash

export PATH="$HOME/.scalingo/node/bin:$HOME/.scalingo/yarn/bin:$PATH:$HOME/bin:$HOME/node_modules/.bin"
export NODE_HOME="$HOME/.scalingo/node"
export NODE_ENV=${NODE_ENV:-test}
export COREPACK_HOME="$BUILD_DIR/.scalingo/corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
