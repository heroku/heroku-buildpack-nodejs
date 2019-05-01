#!/usr/bin/env bash
# download.sh <tag-name>

set -o errexit    # always exit on error
set -o pipefail   # don't ignore exit codes when piping output

TAG_NAME=${1:-}
PLUGIN_DIR=$(dirname $0)

handle_failure() {
    echo "Failure running script on line $1."

    
    echo "This may be rate-limiting from Github if you've run this script a few times. Here is the rate limit response:"
    curl "https://api.github.com/rate_limit"
}

get_latest_release() {
    # Get latest release tag from GitHub api
    curl --silent --write-out "%{http_code}" "https://api.github.com/repos/heroku/heroku-nodejs-plugin/releases/latest" | 
        grep '"tag_name":' | 
        sed -E 's/.*"([^"]+)".*/\1/'                                    
}

download() {
    local url=${1}
    local file=${2}
    local code=$(curl "$url" -L --fail --retry 5 --retry-max-time 15 -o "${file}" --write-out "%{http_code}")
    if [[ "$code" != "200" ]]; then
        echo "Unable to download from url: $url http code: $code"
        exit 1
    fi
}

delete_old_plugin() {
    local dir=${1}
    rm -f "$dir/heroku-nodejs-plugin-node-12.sha512"
    rm -f "$dir/heroku-nodejs-plugin-node-12.tar.gz"
    rm -f "$dir/heroku-nodejs-plugin-node-11.sha512"
    rm -f "$dir/heroku-nodejs-plugin-node-11.tar.gz"
    rm -f "$dir/heroku-nodejs-plugin-node-10.sha512"
    rm -f "$dir/heroku-nodejs-plugin-node-10.tar.gz"
    rm -f "$dir/heroku-nodejs-plugin-node-8.sha512"
    rm -f "$dir/heroku-nodejs-plugin-node-8.tar.gz"
    rm -f "$dir/heroku-nodejs-plugin-node-9.sha512"
    rm -f "$dir/heroku-nodejs-plugin-node-9.tar.gz"
    rm -f "$dir/version"
}

download_assets_for_release() {
    local tag=${1}
    local dir=${2}

    # Node 8
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-8-$tag.sha512" "$dir/heroku-nodejs-plugin-node-8.sha512"
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-8-$tag.tar.gz" "$dir/heroku-nodejs-plugin-node-8.tar.gz"

    # Node 9
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-9-$tag.sha512" "$dir/heroku-nodejs-plugin-node-9.sha512"
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-9-$tag.tar.gz" "$dir/heroku-nodejs-plugin-node-9.tar.gz"

    # Node 10 
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-10-$tag.sha512" "$dir/heroku-nodejs-plugin-node-10.sha512"
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-10-$tag.tar.gz" "$dir/heroku-nodejs-plugin-node-10.tar.gz"

    # Node 11
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-11-$tag.sha512" "$dir/heroku-nodejs-plugin-node-11.sha512"
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-11-$tag.tar.gz" "$dir/heroku-nodejs-plugin-node-11.tar.gz"

    # Node 12
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-12-$tag.sha512" "$dir/heroku-nodejs-plugin-node-12.sha512"
    download "https://github.com/heroku/heroku-nodejs-plugin/releases/download/$tag/heroku-nodejs-plugin-node-12-$tag.tar.gz" "$dir/heroku-nodejs-plugin-node-12.tar.gz"
}

test_hash() {
    local major=${1}
    local dir=${2}

    local downloaded_sha=$(cat $dir/heroku-nodejs-plugin-node-$major.sha512 | awk '{print substr($0,0,128)}')
    local binary_sha=$(shasum -a 512 $dir/heroku-nodejs-plugin-node-$major.tar.gz | awk '{print substr($0,0,128)}')

    if [[ "$downloaded_sha" != "$binary_sha" ]]; then
        echo "Invalid SHA for file: $dir/heroku-nodejs-plugin-node-$major.tar.gz"
        exit 1
    else
        echo "Verified SHA for file: $dir/heroku-nodejs-plugin-node-$major.tar.gz"
    fi
}

trap 'handle_failure ${LINENO}' ERR

if [[ -z $TAG_NAME ]]; then
    TAG_NAME=$(get_latest_release)
fi

echo "Removing any old versions of the plugin"
delete_old_plugin $PLUGIN_DIR

echo "Downloading plugins"
download_assets_for_release $TAG_NAME $PLUGIN_DIR
echo $TAG_NAME > "$PLUGIN_DIR/version"

echo "Plugins downloaded"

test_hash 8 $PLUGIN_DIR
test_hash 9 $PLUGIN_DIR
test_hash 10 $PLUGIN_DIR
test_hash 11 $PLUGIN_DIR
test_hash 12 $PLUGIN_DIR

echo "Done"
