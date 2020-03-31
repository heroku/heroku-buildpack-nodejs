#!/usr/bin/env bash

export PATH="$HOME/.scalingo/node/bin:$HOME/.scalingo/yarn/bin:$PATH:$HOME/bin:$HOME/node_modules/.bin"
export NODE_HOME="$HOME/.scalingo/node"
export NODE_ENV=${NODE_ENV:-test}
