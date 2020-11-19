#!/usr/bin/env bash

[ "$CI" != "true" ] && echo "Not running on CI!" && exit 1
[ "$CIRCLE_PROJECT_USERNAME" != "heroku" ] && echo "Run tests manually for forked PRs." && exit 0

bundle install
bundle exec hatchet ci:setup
