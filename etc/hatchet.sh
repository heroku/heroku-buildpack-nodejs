#!/usr/bin/env bash

set -e

BUILDPACK_NAME="heroku-nodejs-metrics-buildpack"

if [ "$CIRCLECI" == "true" ] && [ -n "$CI_PULL_REQUEST" ]; then
  if [ "$CIRCLE_PR_USERNAME" != "heroku" ]; then
    echo "Skipping integration tests on forked PR."
    exit 0
  fi
fi

if [ "$TRAVIS" == "true" ] && [ "$TRAVIS_PULL_REQUEST" != "false" ]; then
  if [ "$TRAVIS_PULL_REQUEST_SLUG" != "heroku/$BUILDPACK_NAME" ]; then
    echo "Skipping integration tests on forked PR."
    exit 0
  fi
fi

if [ -z "$HEROKU_API_KEY" ]; then
  echo "ERROR: Missing \$HEROKU_API_KEY."
  exit 1
fi

if [ -n "$CIRCLE_BRANCH" ]; then
  export HATCHET_BUILDPACK_BRANCH="$CIRCLE_BRANCH"
elif [ -n "$TRAVIS_PULL_REQUEST_BRANCH" ]; then
  export HATCHET_BUILDPACK_BRANCH="$TRAVIS_PULL_REQUEST_BRANCH"
else
  export HATCHET_BUILDPACK_BRANCH=$(git name-rev HEAD 2> /dev/null | sed 's#HEAD\ \(.*\)#\1#')
fi

gem install bundler
bundle install
bundle exec hatchet install

export HATCHET_RETRIES=3
export HATCHET_APP_LIMIT=20
export HATCHET_DEPLOY_STRATEGY=git
export HATCHET_BUILDPACK_BASE="https://github.com/heroku/$BUILDPACK_NAME"

bundle exec rspec "$@"
