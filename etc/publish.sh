#!/bin/bash

set -e

BP_NAME=${1:-"heroku/nodejs"}

# if buildpack-registry CLI plugin is not installed, show a help message and exit
if ! heroku plugins | grep -q "buildpack-registry"; then
  echo "Releasing the buildpack requires the buildpack-registry CLI plugin."
  echo "https://github.com/heroku/languages-team/blob/master/languages/nodejs/buildpack.md"
  echo ""
  echo "heroku plugins:install buildpack-registry"
  echo ""
  echo "Current CLI plugins:"
  heroku plugins
  exit 1
fi

curVersion=$(heroku buildpacks:versions "$BP_NAME" | awk 'FNR == 3 { print $1 }')
newVersion="v$((curVersion + 1))"

read -r -p "Deploy as version: $newVersion [y/n]? " choice
case "$choice" in
  y|Y ) echo "";;
  n|N ) exit 0;;
  * ) exit 1;;
esac

originMaster=$(git rev-parse origin/master)
echo "Tagging commit $originMaster with $newVersion... "
git tag "$newVersion" "${originMaster:?}"
git push origin refs/tags/$newVersion

heroku buildpacks:publish "$BP_NAME" "$newVersion"

echo "Done."