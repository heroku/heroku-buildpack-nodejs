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
# Schema
#
# This module expects a "schema" file as input. This is used to
# make sure that all current experiments are documented in one 
# place. The file is a list of key=value pairs on individual 
# lines.
#
# There is a special "#version" key that is expected that can be
# used to invalidate any existing experiments.
#
# The key is the name, and the value is an integery between 0 and
# 100 inclusive that represents the likelyhood that the experiment
# will be turned on for any given app.
#
# Example:
# ```
# #version=1
# always-on=100   // this will always be turned on, not super useful
# ab-test=50      // this will be split 50/50
# small-test=5    // this will be turned on for 5% of apps
# ```
#
# See tests/unit-fixtures/experiments/experiments-v1 for an example

# variables shared by this whole module
EXPERIMENTS_DATA_FILE=""

experiments_init() {
  local name="$1"
  local cache_dir="$2"
  local schema="$3"

  local last_schema_version schema_version random odds

  EXPERIMENTS_DATA_FILE="$cache_dir/experiments/$name"

  last_schema_version="$(kv_get "$EXPERIMENTS_DATA_FILE" "#version")"
  schema_version="$(kv_get "$schema" "#version")"

  # If the schema has changed, blow away the current values
  # and start fresh. This is essentially "wiping the slate clean"
  # and no previous experiments will be enabled for anyone
  #
  # In the case that the schema version is the same, we keep
  # all of the previously decided experiments (file is the same)
  # and decide on any new ones
  if [[ "$last_schema_version" != "$schema_version" ]]; then
    kv_create "$EXPERIMENTS_DATA_FILE"
    kv_clear "$EXPERIMENTS_DATA_FILE"
    # save out the version we're using to generate this set of experiments
    kv_set "$EXPERIMENTS_DATA_FILE" "#version" "$schema_version"
  fi

  # iterate through the schema and decide if each new experiment
  # should be turned on or not
  kv_keys "$schema" | tr ' ' '\n' | while read -r key; do
    # skip the special version key
    if [[ "$key" = "#version" ]]; then
      continue
    # skip any values that are already decided
    elif [[ -n "$(kv_get "$EXPERIMENTS_DATA_FILE" "$key")" ]]; then
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
  done
}

# Determine whether an experiment is enabled or disabled
# Must call experiments_init first
#
# Possible outputs: "true" "false" ""
experiments_get() {
  kv_get "$EXPERIMENTS_DATA_FILE" "$1"
}

# Outputs a list of experiment names, one-per-line
experiments_list() {
  kv_keys "$EXPERIMENTS_DATA_FILE"
}
