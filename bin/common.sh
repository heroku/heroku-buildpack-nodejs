#!/usr/bin/env bash

# fail fast
set -e

# debug
# set -x

download_and_install_node() {
  version="$1"

  status "Downloading node $version"
  node_url="http://s3pository.heroku.com/node/v$version/node-v$version-linux-x64.tar.gz"
  curl $node_url -s -o - | tar xzf - -C $build_dir
  mv $build_dir/node-v$version-linux-x64 $build_dir/node

  status "Adding node and npm to \$PATH"
  chmod +x $build_dir/node/bin/*
  PATH=$PATH:$build_dir/node/bin
}

query_stable_version() {
  curl -s http://nodejs.org/dist/ \
    | egrep -o '[0-9]+\.[0-9]*[02468]\.[0-9]+' \
    | sort -u -k 1,1n -k 2,2n -k 3,3n -t . \
    | tail -n1
}

query_latest_version() {
  curl -s http://nodejs.org/dist/ \
    | egrep -o '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -u -k 1,1n -k 2,2n -k 3,3n -t . \
    | tail -n1
}

query_all_versions() {
  curl -s http://nodejs.org/dist/ \
  | egrep -o '[0-9]+\.[0-9]+\.[0-9]+' \
  | sort -u -k 1,1n -k 2,2n -k 3,3n -t .
}



error() {
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