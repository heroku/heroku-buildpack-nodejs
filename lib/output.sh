info() {
  echo "       $*"
}

# sed has a problem with the huge build output from npm 3
# try awk? awk  '{ print "       " $0 }'
output() {
  local logfile="$1"
  local c='s/^/       /'

  case $(uname) in
    Darwin) stdbuf -oL -eL sed -l "$c" | tee -i -a "$logfile" 2> /dev/null;;
    *)      stdbuf -oL -eL sed -u "$c" | tee -i -a "$logfile" 2> /dev/null;;
  esac
}

header() {
  echo ""
  echo "-----> $*"
}

error() {
  echo " !     $*" >&2
  echo ""
}
