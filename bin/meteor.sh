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
  curl -Ls https://install.meteor.com | HOME=$METEOR_HOME PREFIX=$build_dir/vendor/node /bin/sh | indent
  status "Meteor installed"

  npm  install -g meteorite demeteorizer | indent
  status "Demeteorizer installed"

  mkdir meteor_app
  mv .meteor meteor_app

  for file in * .* ; do
    if echo "$file" | grep -qvE "^\\.|\\.\\.|meteor_app|tmp|vendor|${meteor_temp}|Procfile|\\.npm$" ; then
      mv "$file" meteor_app
    fi
  done

  cd meteor_app
  HOME=$METEOR_HOME PREFIX=$build_dir/vendor/node demeteorizer -o "$build_dir/demeteorized" -n "v$node_version" | indent
  cd $build_dir

  ln -s "$build_dir"/demeteorized/package.json "$build_dir"/package.json
  sed -i 's/node main\.js/node demeteorized\/main.js/' "$build_dir"/package.json

  status "Application demeteorized"

  create_mongo_profile $build_dir
}
