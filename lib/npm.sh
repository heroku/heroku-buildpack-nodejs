#!/usr/bin/env bash

npm_version_major() {
  npm --version | cut -d "." -f 1
}
