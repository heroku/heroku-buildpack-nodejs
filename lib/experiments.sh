#!/usr/bin/env bash

# This module is designed to be able to roll out experiments to a
# random segment of users for A/B testing. This takes as input a
# list of experiments along with % chance they will be enabled,
# decides which to enable, and persists these decisions into the
# application cache.
#
# This module takes in no outside data, so it is limited in it's
# uses. While an experiment can be persisted between builds for the
# same app, it cannot be consistent for a given user / team. Even
# different PR apps will be decided independently.
#
# This means that this should not be used for changing the build 
# behavior of the buildpack. Builds should always work consistently
# no matter what experiments are turned on or off.
#
# Where this module can be useful is when deciding between two 
# identical behaviors that may have performance trade-offs, or
# testing the efficacy of different messaging. 
#
# Examples: 
#    testing two different caching strategies against each other
#    showing guidance on a particular type of failure
#
# It is expected that these experiments will be short-lived
#
# ** Schema **
#
# This module expects a "schema" file as input. This is used to
# make sure that all current experiments are documented in one 
# place. The file is a list of key=value pairs on individual 
# lines.
#
# The key is the name, and the value is an integery between 0 and
# 100 inclusive that represents the likelyhood that the experiment
# will be turned on for any given app.
#
# Example:
# ```
# always-on=100   // this will always be turned on, not super useful
# ab-test=50      // this will be split 50/50
# small-test=5    // this will be turned on for 5% of apps
# ```
#
# ** Invalidating experiments **
#
# Any time the schema file contents change, the existing experiment
# assignments will be invalidated and re-assigned
#
# ** Testing **
#
# It would be frustrating if it wasn't clear when CI was running which
# branch was being used, or if tests were flaky because they were choosing
# different experiments for each run.
#
# To that end, there is a special file that can be included in test fixtures
# to hard-code experiments to turn on and off.
# 
# $BUILD_DIR/heroku-buildpack-experiments
#
# Example:
# ```
# experiment-a=true 
# experiment-b=true 
# ```
#
# An empty file can be included as part of test code to default all tests
# to off
#
# Once an experiment is in production, checking this file into your app
# can allow you to choose which experiments you want an app to use.

# variables shared by this whole module
EXPERIMENTS_DATA_FILE=""
OVERRIDE_FILE=""

experiments_init() {
  local name="$1"
  local build_dir="$2"
  local cache_dir="$3"
  local schema="$4"

  local last_schema_hash schema_hash random odds hash_file

  EXPERIMENTS_DATA_FILE="$cache_dir/experiments/$name"
  hash_file="$cache_dir/experiments/$name-hash"
  OVERRIDE_FILE="$build_dir/heroku-buildpack-experiments"

  mkdir -p "$cache_dir/experiments/"
  touch "$hash_file"

  last_schema_hash="$(cat "$hash_file")"
  schema_hash="$(sha1sum "$schema" | awk '{ print $1 }')"

  # If the schema has changed, blow away the current values
  # and start fresh. This is essentially "wiping the slate clean"
  # and no previous experiments will be enabled for anyone
  #
  # In the case that the schema hash is the same, we keep
  # all of the previously decided experiments (file is the same)
  # and decide on any new ones
  if [[ "$last_schema_hash" != "$schema_hash" ]]; then
    kv_create "$EXPERIMENTS_DATA_FILE"
    kv_clear "$EXPERIMENTS_DATA_FILE"
    # save out the hash we're using to generate this set of experiments
    echo "$schema_hash" > "$hash_file"
  fi

  # iterate through the schema and decide if each new experiment
  # should be turned on or not
  kv_keys "$schema" | tr ' ' '\n' | while read -r key; do
    if [[ -n "$key" ]]; then
      if [[ -n "$(kv_get "$EXPERIMENTS_DATA_FILE" "$key")" ]]; then
        continue
      else
        # generate a random number between 0 and 100
        random=$((RANDOM % 100))
        # the value in the schema should be a number between 0 and 100 inclusive
        odds=$(kv_get "$schema" "$key")
        if [[ "$random" -lt "$odds" ]]; then
          kv_set "$EXPERIMENTS_DATA_FILE" "$key" "true"
        else
          kv_set "$EXPERIMENTS_DATA_FILE" "$key" "false"
        fi
      fi
    fi
  done
}

# Determine whether an experiment is enabled or disabled
# Must call experiments_init first, otherwise only "false" will be returned
#
# Possible outputs: "true" "false"
experiments_get() {
  local result
  if [[ -f "$OVERRIDE_FILE" ]]; then
    result=$(kv_get "$OVERRIDE_FILE" "$1")
  else
    result=$(kv_get "$EXPERIMENTS_DATA_FILE" "$1")
  fi
  if [[ "$result" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Outputs a list of experiment names, one-per-line
experiments_list() {
  if [[ -f "$OVERRIDE_FILE" ]]; then
    kv_keys "$OVERRIDE_FILE"
  else
    kv_keys "$EXPERIMENTS_DATA_FILE"
  fi
}

# Force an experiment to be turned on or off
# This is expected to be used during development
experiments_override() {
  local name="$1"
  local value="$2"

  if [[ "$value" == "true" ]]; then
    kv_set "$EXPERIMENTS_DATA_FILE" "$name" "true"
  else
    kv_set "$EXPERIMENTS_DATA_FILE" "$name" "false"
  fi
}
