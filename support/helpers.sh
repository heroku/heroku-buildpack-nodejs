function error() {
  echo " !     $*" >&2
  exit 1
}

function mktmpdir() {
  dir=$(mktemp -t node-$1-XXXX)
  rm -rf $dir
  mkdir -p $dir
  echo $dir
}

function indent() {
  c='s/^/       /'
  case $(uname) in
    Darwin) sed -l "$c";;
    *)      sed -u "$c";;
  esac
}