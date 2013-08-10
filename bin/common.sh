#!/usr/bin/env bash

# fail fast
set -e

# debug
set -x

function tar_download() {
  url="$1"
  location="$2"
  mkdir -p $location
  curl $url -s -o - | tar xzf - -C $location
}

function error() {
  echo " !     $*" >&2
  exit 1
}

function status() {
  echo "-----> $*"
}

function mktmpdir() {
  dir=$(mktemp -t node-$1-XXXX)
  rm -rf $dir
  mkdir -p $dir
  echo $dir
}

function indent() {
  c='s/^/       /'
  case $(uname) in
    Darwin) sed -l "$c";;
    *)      sed -u "$c";;
  esac
}

function cat_npm_debug_log() {
  if [ -f $BUILD_DIR/npm-debug.log ]; then
    cat $BUILD_DIR/npm-debug.log
  fi
}