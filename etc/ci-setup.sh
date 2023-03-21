#!/usr/bin/env bash

[ "$CI" != "true" ] && echo "Not running on CI!" && exit 1
ci_repo_owner=${CIRCLE_PROJECT_USERNAME:-${GITHUB_REPOSITORY_OWNER}}
[ "$ci_repo_owner" != "heroku" ] && echo "Run tests manually for forked PRs." && exit 0

bundle exec hatchet ci:setup
