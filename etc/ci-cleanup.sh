#!/usr/bin/env bash

if [[ -n "$HEROKU_API_KEY" ]]; then 
  heroku keys:remove "$USER@$(hostname)"
fi
