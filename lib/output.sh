info() {
  echo "       $*"
}

# format output on both OSX and Ubuntu, cedar-10 and cedar-14, while also splitting to a log file
output() {
  local logfile="$1"
  local c='s/^/       /'

  if [ "${STACK:-cedar-14}" = "cedar" ]; then
    tee -a "$logfile" | awk -W interactive '{ print "       " $0 }'
  else
    case $(uname) in
      Darwin) sed -l "$c" | tee -i -a "$logfile" 2> /dev/null;;
      *)      stdbuf -oL -eL sed -u "$c" | tee -i -a "$logfile" 2> /dev/null;;
    esac
  fi
}

header() {
  echo ""
  echo "-----> $*"
}

error() {
  echo " !     $*" >&2
  echo ""
}
