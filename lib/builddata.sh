#!/usr/bin/env bash

# Log out information about the build that we can detect without accessing package.json
log_initial_state() {
  if "$YARN"; then
    meta_set "package_manager" "yarn"
  elif "$PNPM"; then
    meta_set "package_manager" "pnpm"
  else
    meta_set "package_manager" "npm"
  fi

  meta_set "has_procfile" "$(if test -f "$BUILD_DIR/Procfile"; then echo "true"; else echo "false"; fi)"
  meta_set "start_script" "$(read_json "$BUILD_DIR/package.json" ".scripts[\"start\"]")"
  meta_set "postinstall_script" "$(read_json "$BUILD_DIR/package.json" ".scripts[\"postinstall\"]")"

  meta_set "heroku_prebuild_script" "$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-prebuild\"]")"
  meta_set "build_script" "$(read_json "$BUILD_DIR/package.json" ".scripts[\"build\"]")"
  meta_set "heroku_postbuild_script" "$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-postbuild\"]")"
  meta_set "heroku_cleanup_script" "$(read_json "$BUILD_DIR/package.json" ".scripts[\"heroku-cleanup\"]")"

  # add any active features to the metadata set
  # prefix the key with "feature-"
  features_list | tr ' ' '\n' | while read -r key; do
    if [[ -n $key ]]; then
      meta_set "feature_$key" "$(features_get "$key")"
    fi
  done
}
