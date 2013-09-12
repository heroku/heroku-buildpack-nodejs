#!/usr/bin/env bash

# fail fast
set -e

# Uncomment the line below to enable debugging
# set -x

download_and_install_node() {
  version="$1"
  node_url="http://s3pository.heroku.com/node/v$version/node-v$version-linux-x64.tar.gz"
  curl $node_url -s -o - | tar xzf - -C $build_dir
  mkdir -p $build_dir/vendor

  # Remove node in case we're overwriting a previously-downloaded version
  rm -rf $build_dir/vendor/node

  mv $build_dir/node-v$version-linux-x64 $build_dir/vendor/node
  chmod +x $build_dir/vendor/node/bin/*
  PATH=$PATH:$build_dir/vendor/node/bin
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

status() {
  echo "-----> $*"
}

# sed -l basically makes sed replace and buffer through stdin to stdout
# so you get updates while the command runs and dont wait for the end
# e.g. npm install | indent
indent() {
  c='s/^/       /'
  case $(uname) in
    Darwin) sed -l "$c";; # mac/bsd sed: -l buffers on line boundaries
    *)      sed -u "$c";; # unix/gnu sed: -u unbuffered (arbitrary) chunks of data
  esac
}

function cat_npm_debug_log() {
  test -f $build_dir/npm-debug.log && cat $build_dir/npm-debug.log
}
