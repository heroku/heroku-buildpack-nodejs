if [ "$node_engine" == "" ]; then
  protip "Specify a node version in package.json" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
elif [ "$node_engine" == "*" ]; then
  protip "Avoid semver ranges like '*' in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
elif [ ${node_engine:0:1} == ">" ]; then
  protip "Avoid semver ranges starting with '>' in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
fi

if [ "$modules_source" == "prebuilt" ]; then
  protip "Avoid checking node_modules into source control" "https://www.npmjs.org/doc/misc/npm-faq.html#should-i-check-my-node_modules-folder-into-git-"
elif [ "$modules_source" == "" ]; then
  protip "Use 'npm init' and 'npm install --save' to define dependencies"
fi

if [ "$start_method" == "" ]; then
  protip "Include a Procfile, package.json start script, or server.js file to start your app" "https://devcenter.heroku.com/articles/nodejs-support#runtime-behavior"
fi
