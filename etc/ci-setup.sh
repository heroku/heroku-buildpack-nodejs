#!/usr/bin/env bash

[ "$CI" != "true" ] && echo "Not running on CI!" && exit 1
[ "$TRAVIS_PULL_REQUEST_SLUG" != "heroku/heroku-buildpack-nodejs" ] && echo "Run tests manually for forked PRs." && exit 0

bundle install
bundle exec hatchet ci:setup
