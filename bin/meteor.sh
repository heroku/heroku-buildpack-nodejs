create_mongo_profile() {
  build_dir=$1

  if [ "x$MONGOHQ_URL" != "x" ] ; then
    MONGO_URL=$MONGOHQ_URL
  elif [ "x$APPSDECK_MONGO_URL" != "x" ] ; then
    MONGO_URL=$APPSDECK_MONGO_URL
  fi

  mkdir -p "$build_dir"/.profile.d
  cat > "$build_dir"/.profile.d/mongo.sh <<EOF
  #!/bin/sh

  export MONGO_URL=\$MONGO_URL
EOF
}

demeteorize_app() {
  node_version=$1
  build_dir=$2
  cache_dir=$3

  meteor_temp=$(mktempdir meteor)
  METEOR_HOME=$(pwd)/$meteor_temp
  curl -Ls https://install.meteor.com | HOME=$METEOR_HOME PREFIX=$build_dir/.vendor/node /bin/sh | indent
  status "Meteor installed"

  if [ -e "$build_dir/smart.json" ] ; then
    if [ ! -e "$build_dir/smart.lock" ] ; then
      error "smart.lock is not present, run 'mrt install' to freeze dependencies"
    fi
    npm install -g meteorite | indent
    status "Meteorite installed"
    mrt install | indent
    status "Meteorite packaged installed"
  fi

  npm  install -g demeteorizer | indent
  status "Demeteorizer installed"

  HOME=$METEOR_HOME PREFIX=$build_dir/.vendor/node demeteorizer -o "$build_dir/demeteorized" | indent

  if [ ! -e "$build_dir/Procfile" ] ; then
    echo "web: cd demeteorized && npm start" > "$build_dir/Procfile"
  fi

  if [ ! -d "$build_dir/node_modules" ] ; then
    mkdir "$build_dir/node_modules"
  fi
  ln -s "$build_dir/node_modules" "$build_dir/demeteorized/node_modules"
  ln -s "$build_dir/demeteorized/package.json" "$build_dir/package.json"

  status "Application demeteorized"

  create_mongo_profile $build_dir
}
