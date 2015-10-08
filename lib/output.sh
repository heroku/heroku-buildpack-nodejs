info() {
  echo "       $*"
}

# sed has a problem with the huge build output from npm 3
# try awk? awk  '{ print "       " $0 }'
output() {
  local logfile="$1"
  local c='s/^/       /'

  case $(uname) in
    Darwin) tee -a "$logfile" | awk '{ print "       " $0 }';;
    *)      tee -a "$logfile" | awk -W interactive '{ print "       " $0 }';;
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
