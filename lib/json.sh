read_json() {
  local file=$1
  local key=$2
  if test -f $file; then
    cat $file | $JQ --raw-output "$key // \"\"" || return 1
  else
    echo ""
  fi
}
