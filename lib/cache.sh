#!/usr/bin/env bash

source $BP_DIR/lib/binaries.sh

create_signature() {
  echo "v2; ${STACK}; $(node --version); $(npm --version); $(yarn --version 2>/dev/null || true); ${PREBUILD}"
}

save_signature() {
  create_signature > $CACHE_DIR/node/signature
}

load_signature() {
  if test -f $CACHE_DIR/node/signature; then
    cat $CACHE_DIR/node/signature
  else
    echo ""
  fi
}

get_cache_status() {
  if ! ${NODE_MODULES_CACHE:-true}; then
    echo "disabled"
  elif ! test -d "${CACHE_DIR}/node/"; then
    echo "not-found"
  elif [ "$(create_signature)" != "$(load_signature)" ]; then
    echo "new-signature"
  else
    echo "valid"
  fi
}

get_cache_directories() {
  local dirs1 dirs2
  dirs1=$(read_json "$BUILD_DIR/package.json" ".cacheDirectories | .[]?")
  dirs2=$(read_json "$BUILD_DIR/package.json" ".cache_directories | .[]?")

  if [ -n "$dirs1" ]; then
    echo "$dirs1"
  else
    echo "$dirs2"
  fi
}

restore_default_cache_directories() {
  local build_dir=${1:-}
  local cache_dir=${2:-}

  # node_modules
  if [[ -e "$build_dir/node_modules" ]]; then
    echo "- node_modules is checked into source control and cannot be cached"
  elif [[ -e "$cache_dir/node/cache/node_modules" ]]; then
    echo "- node_modules"
    mkdir -p "$(dirname "$build_dir/node_modules")"
    mv "$cache_dir/node/cache/node_modules" "$build_dir/node_modules"
  else
    echo "- node_modules (not cached - skipping)"
  fi

  # bower_components, should be silent if it is not in the cache
  if [[ -e "$cache_dir/node/cache/bower_components" ]]; then
    echo "- bower_components"
  fi
}

restore_custom_cache_directories() {
  local cache_directories
  local build_dir=${1:-}
  local cache_dir=${2:-}
  # Parse the input string with multiple lines: "a\nb\nc" into an array
  mapfile -t cache_directories <<< "$3"

  echo "Loading ${#cache_directories[@]} from cacheDirectories (package.json):"

  for cachepath in "${cache_directories[@]}"; do
    if [ -e "$build_dir/$cachepath" ]; then
      echo "- $cachepath (exists - skipping)"
    else
      if [ -e "$cache_dir/node/cache/$cachepath" ]; then
        echo "- $cachepath"
        mkdir -p "$(dirname "$build_dir/$cachepath")"
        mv "$cache_dir/node/cache/$cachepath" "$build_dir/$cachepath"
      else
        echo "- $cachepath (not cached - skipping)"
      fi
    fi
  done
}

clear_cache() {
  rm -rf $CACHE_DIR/node
  mkdir -p $CACHE_DIR/node
  mkdir -p $CACHE_DIR/node/cache
}

save_default_cache_directories() {
  local build_dir=${1:-}
  local cache_dir=${2:-}

  # node_modules
  if [[ -e "$build_dir/node_modules" ]]; then
    echo "- node_modules"
    mkdir -p "$cache_dir/node/cache/node_modules"
    cp -a "$build_dir/node_modules" "$(dirname "$cache_dir/node/cache/node_modules")"
  else
    # this can happen if there are no dependencies
    mcount "cache.no-node-modules"
    echo "- node_modules (nothing to cache)"
  fi

  # bower_components
  if [[ -e "$build_dir/bower_components" ]]; then
    mcount "cache.saved-bower-components"
    echo "- bower_components"
    mkdir -p "$cache_dir/node/cache/bower_components"
    cp -a "$build_dir/bower_components" "$(dirname "$cache_dir/node/cache/bower_components")"
  fi
}

save_custom_cache_directories() {
  local cache_directories
  local build_dir=${1:-}
  local cache_dir=${2:-}
  # Parse the input string with multiple lines: "a\nb\nc" into an array
  mapfile -t cache_directories <<< "$3"

  echo "Saving ${#cache_directories[@]} cacheDirectories (package.json):"

  for cachepath in "${cache_directories[@]}"; do
    if [ -e "$build_dir/$cachepath" ]; then
      echo "- $cachepath"
      mkdir -p "$cache_dir/node/cache/$cachepath"
      cp -a "$build_dir/$cachepath" "$(dirname "$cache_dir/node/cache/$cachepath")"
    else
      echo "- $cachepath (nothing to cache)"
    fi
  done
}
