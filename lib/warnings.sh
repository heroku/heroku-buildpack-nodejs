warn_node_engine() {
  local node_engine=$1
  if [ "$meteor_version" != "" ] ; then
    if [ "${node_engine:0:4}" == "0.11" -o "${node_engine:0:4}" == "0.12" ] ; then
      warning "Meteor is not compatible with version ${node_engine} of Node.JS" "http://doc.scalingo.com/languages/javascript/nodejs/meteor"
    fi
  else
    if [ "$node_engine" == "" ]; then
      warning "Node version not specified in package.json" "http://doc.scalingo.com/languages/javascript/nodejs"
    elif [ "$node_engine" == "*" ]; then
      warning "Avoid semver ranges like '*' in engines.node" "http://doc.scalingo.com/languages/javascript/nodejs"
    elif [ ${node_engine:0:1} == ">" ]; then
      warning "Avoid semver ranges starting with '>' in engines.node" "http://doc.scalingo.com/languages/javascript/nodejs"
    fi
  fi
}

warn_node_modules() {
  local modules_source=$1
  if [ "$modules_source" == "prebuilt" ]; then
    warning "Avoid checking node_modules into source control" "https://www.npmjs.org/doc/misc/npm-faq.html#should-i-check-my-node_modules-folder-into-git-"
  elif [ "$modules_source" == "" -a -z "$meteor_version" ]; then
    warning "No package.json found"
  fi
}

warn_start() {
  local start_method=$1
  if [ "$start_method" == "" -a -z "$meteor_version" ]; then
    warning "No Procfile, package.json start script, or server.js file found" "http://doc.scalingo.com/languages/javascript/nodejs"
  fi
}

warn_old_npm() {
  local npm_version=$1
  if [ "${npm_version:0:1}" -lt "2" ]; then
    local latest_npm=$(curl --silent --get https://semver.herokuapp.com/npm/stable)
    warning "This version of npm ($npm_version) has several known issues - consider upgrading to the latest release ($latest_npm)" "http://doc.scalingo.com/languages/javascript/nodejs"
  fi
}

warn_meteor_npm_dir() {
  if [ ! -d "packages/npm-container" ] ; then
    warning "Your Meteor app is using '${meteorhacks_npm_version}', check in the 'packages/npm-container' directory in your GIT repository" "http://doc.scalingo.com/languages/javascript/nodejs/meteor/npm"
  fi
}

warn_meteor_npm_packages_json() {
  if [ ! -e "packages.json" ] ; then
    warning "Your Meteor app is using '${meteorhacks_npm_version}', check in 'packages.json' in your GIT repository" "http://doc.scalingo.com/languages/javascript/nodejs/meteor/npm"
  fi
}

warn_meteor_npm_package() {
  if ! grep -q npm-container ".meteor/packages" ; then
    warning "Your Meteor app is using '${meteorhacks_npm_version}', add 'npm-container' in '.meteor/packages'" "http://doc.scalingo.com/languages/javascript/nodejs/meteor/npm"
  fi
}
