info() {
  echo "       $*"
}

# sed's buffer can't hold some of the huge build output from JS asset builders
# try awk next? awk  '{ print "       " $0 }'
output() {
  local logfile="$1"
  local c='s/^/       /'

  case $(uname) in
    Darwin) tee -a "$logfile";;
    *)      tee -a "$logfile";;
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
