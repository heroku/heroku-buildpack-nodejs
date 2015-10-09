info() {
  echo "       $*"
}

# format output and send a copy to the log
output() {
  local logfile="$1"

  while read LINE;
  do
    echo "       $LINE"
    echo "$LINE" >> "$logfile"
  done
}

header() {
  echo ""
  echo "-----> $*"
}

error() {
  echo " !     $*" >&2
  echo ""
}
