#!/usr/bin/env bash

set -e

ci_repo_owner=${CIRCLE_PROJECT_USERNAME:-${GITHUB_REPOSITORY_OWNER}}
ci_repo_name=${CIRCLE_PROJECT_REPONAME:-${GITHUB_REPOSITORY}}
ci_branch=${CIRCLE_BRANCH:-${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}}

[ "$ci_repo_owner" != "heroku" ] && echo "Run tests manually for forked PRs." && exit 0

if [[ "$ci_repo_name" == *nodebin ]]; then
  HATCHET_BUILDPACK_BRANCH="main"
elif [ -n "$ci_branch" ]; then
  HATCHET_BUILDPACK_BRANCH="$ci_branch"
else
  HATCHET_BUILDPACK_BRANCH=$(git name-rev HEAD 2> /dev/null | sed 's#HEAD\ \(.*\)#\1#' | sed 's#tags\/##')
fi

export HATCHET_BUILDPACK_BRANCH

export HATCHET_RETRIES=3
export HATCHET_APP_LIMIT=100
export HATCHET_DEPLOY_STRATEGY=git
export HATCHET_BUILDPACK_BASE="https://github.com/heroku/heroku-buildpack-nodejs"

bundle exec parallel_split_test "$@"
