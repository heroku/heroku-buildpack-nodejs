info() {
  echo "       $*"
}

# sed has a problem with the huge build output from npm 3
# try awk? awk  '{ print "       " $0 }'
output() {
  local logfile="$1"

  tee -i -a "$logfile" 2> /dev/null
}

header() {
  echo ""
  echo "-----> $*"
}

error() {
  echo " !     $*" >&2
  echo ""
}
