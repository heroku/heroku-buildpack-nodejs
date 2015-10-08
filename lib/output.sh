info() {
  echo "       $*"
}

# sed has a problem with the huge build output from npm 3
# try awk? awk  '{ print "       " $0 }'
output() {
  local logfile="$1"
  local c='s/^/       /'

  tee -a "$logfile"
}

header() {
  echo ""
  echo "-----> $*"
}

error() {
  echo " !     $*" >&2
  echo ""
}
