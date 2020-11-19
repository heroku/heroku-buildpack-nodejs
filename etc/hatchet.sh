#!/usr/bin/env bash

set -e

[ "$CIRCLE_PROJECT_USERNAME" != "heroku" ] && echo "Run tests manually for forked PRs." && exit 0

if [[ "$CIRCLE_PROJECT_REPONAME" == "nodebin" ]]; then
  HATCHET_BUILDPACK_BRANCH="main"
elif [ -n "$CIRCLE_BRANCH" ]; then
  HATCHET_BUILDPACK_BRANCH="$CIRCLE_BRANCH"
elif [ -n "$TRAVIS_PULL_REQUEST_BRANCH" ]; then
  export IS_RUNNING_ON_TRAVIS=true
  HATCHET_BUILDPACK_BRANCH="$TRAVIS_PULL_REQUEST_BRANCH"
else
  HATCHET_BUILDPACK_BRANCH=$(git name-rev HEAD 2> /dev/null | sed 's#HEAD\ \(.*\)#\1#' | sed 's#tags\/##')
fi

export HATCHET_BUILDPACK_BRANCH

export HATCHET_RETRIES=3
export HATCHET_APP_LIMIT=100
export HATCHET_DEPLOY_STRATEGY=git
export HATCHET_BUILDPACK_BASE="https://github.com/heroku/heroku-buildpack-nodejs"

bundle exec parallel_split_test "$@"
