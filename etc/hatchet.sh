#!/usr/bin/env bash

set -e

if [ "$CIRCLECI" == "true" ] && [ -n "$CI_PULL_REQUEST" ]; then
  if [ "$CIRCLE_PR_USERNAME" != "heroku" ]; then
    echo "Skipping integration tests on forked PR."
    exit 0
  fi
fi

if [ "$TRAVIS" == "true" ] && [ "$TRAVIS_PULL_REQUEST" != "false" ]; then
  if [ "$TRAVIS_PULL_REQUEST_SLUG" != "heroku/heroku-buildpack-nodejs" ]; then
    echo "Skipping integration tests on forked PR."
    exit 0
  fi
fi

if [ -z "$HEROKU_API_KEY" ]; then
  echo ""
  echo "ERROR: Missing \$HEROKU_API_KEY."
  echo ""
  echo "NOTE: You can create token this by running: heroku authorizations:create --description \"For Travis\""
  echo ""
  exit 1
fi

if [ -n "$CIRCLE_BRANCH" ]; then
  HATCHET_BUILDPACK_BRANCH="$CIRCLE_BRANCH"
elif [ -n "$TRAVIS_PULL_REQUEST_BRANCH" ]; then
  export IS_RUNNING_ON_TRAVIS=true
  HATCHET_BUILDPACK_BRANCH="$TRAVIS_PULL_REQUEST_BRANCH"
else
  HATCHET_BUILDPACK_BRANCH=$(git name-rev HEAD 2> /dev/null | sed 's#HEAD\ \(.*\)#\1#' | sed 's#tags\/##')
fi

export HATCHET_BUILDPACK_BRANCH

gem install bundler
bundle install

export HATCHET_RETRIES=3
export HATCHET_APP_LIMIT=20
export HATCHET_DEPLOY_STRATEGY=git
export HATCHET_BUILDPACK_BASE="https://github.com/heroku/heroku-buildpack-nodejs"

bundle exec rspec "$@"
