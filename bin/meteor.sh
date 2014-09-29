create_meteor_profile() {
  build_dir=$1

  mkdir -p "$build_dir"/.profile.d
  cat > "$build_dir"/.profile.d/meteor.sh <<EOF
  #!/bin/sh

  export PATH=\$PATH:$METEOR_HOME/bin
EOF
}

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

install_meteor() {
  METEOR_HOME=$1
  build_dir=$2
  cache_dir=$3

  [ -d "$METEOR_HOME" ] || mkdir -p $METEOR_HOME

  if [ -d "$cache_dir/meteor" ] ; then
    cp -r "$cache_dir/meteor" "$meteor_home"
    local cached_meteor_version=$(cat "$cache_dir/meteor-version")
  fi

  [ -e "$build_dir/.meteor/release" ] && local meteor_version=$(cat "$build_dir/.meteor/release")

  if [ -z "$cached_meteor_version" -o "$cached_meteor_version" != "$meteor_version" ] ; then
    curl -Ls https://install.meteor.com | sed -e "s+/usr/local+$METEOR_HOME+" | HOME=$METEOR_HOME /bin/sh | indent
    status "Meteor installed → $meteor_version"
  else
    status "Meteor installed from cache → $meteor_version"
  fi
}

install_meteorite_deps() {
  build_dir=$1
  cache_dir=$2

  [ -d "$cache_dir/meteorite" ] && cp -r "$cache_dir/meteorite" "$build_dir/.meteorite"
  [ -d "$cache_dir/meteorite-packages" ] && cp -r "$cache_dir/meteorite-packages" "$build_dir/packages"

  if [ -e "$build_dir/smart.json" ] ; then
    if [ ! -e "$build_dir/smart.lock" ] ; then
      error "smart.lock is not present, run 'mrt install' to freeze dependencies"
    fi
    npm install -g meteorite | indent
    status "Meteorite installed"
    mrt install | indent
    status "Meteorite packaged installed"
  fi
}

install_demeteorizer() {
  npm install -g 'onmodulus/demeteorizer' | indent
  status "Demeteorizer installed"
}

demeteorize_app() {
  node_version=$1
  build_dir=$2
  cache_dir=$3

  METEOR_HOME="$build_dir/.meteor-install"
  [ -e "$build_dir/.meteor/release" ] && meteor_version=$(cat "$build_dir/.meteor/release")

  install_meteor "$METEOR_HOME" "$build_dir" "$cache_dir"
  export PATH=$PATH:${METEOR_HOME}/bin

  install_meteorite_deps "$build_dir" "$cache_dir"
  install_demeteorizer

  HOME=$METEOR_HOME demeteorizer -o "$build_dir/demeteorized" | indent

  if [ ! -e "$build_dir/Procfile" ] ; then
    echo "web: cd demeteorized && npm start" > "$build_dir/Procfile"
  fi

  ln -s "demeteorized/package.json" "package.json"

  status "Caching meteor runtime for future builds"
  rm -rf "$cache_dir/meteor"
  cp -r "$METEOR_HOME" "$cache_dir/meteor"
  echo $meteor_version > "$cache_dir/meteor-version"

  if [ -d "$build_dir/.meteorite" ] ; then
    status "Caching meteorite packages for future builds"
    rm -rf "$cache_dir/meteorite"
    rm -rf "$cache_dir/meteorite-packages"
    cp -r "$build_dir/packages" "$cache_dir/meteorite-packages"
    cp -r "$build_dir/.meteorite" "$cache_dir/meteorite"
  fi

  status "Application demeteorized"

  create_meteor_profile $build_dir
  create_mongo_profile $build_dir
}
