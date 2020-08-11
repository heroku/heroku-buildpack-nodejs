#!/usr/bin/env bash

[ "$CI" != "true" ] && echo "Not running on CI!" && exit 1

bundle install
bundle exec hatchet ci:setup
