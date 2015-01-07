warning() {
  tip=$1
  url=$2
  echo "WARNING: $tip" >> $warnings
  echo "${url:-https://devcenter.heroku.com/articles/nodejs-support}" >> $warnings
  echo "" >> $warnings
}

if [ "$node_engine" == "" ]; then
  warning "Node version not specified in package.json" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
elif [ "$node_engine" == "*" ]; then
  warning "Avoid semver ranges like '*' in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
elif [ ${node_engine:0:1} == ">" ]; then
  warning "Avoid semver ranges starting with '>' in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
fi

if [ "$npm_engine" != "" ]; then
  if [ "${npm_engine:0:1}" -lt "2" ]; then
    warning "This version of npm has several known issues - consider upgrading to the latest release"
  fi
fi

if [ "$modules_source" == "prebuilt" ]; then
  warning "Avoid checking node_modules into source control" "https://www.npmjs.org/doc/misc/npm-faq.html#should-i-check-my-node_modules-folder-into-git-"
elif [ "$modules_source" == "" ]; then
  warning "No package.json found"
fi

if [ "$start_method" == "" ]; then
  warning "No Procfile, package.json start script, or server.js file found" "https://devcenter.heroku.com/articles/nodejs-support#runtime-behavior"
fi
