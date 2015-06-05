get_os() {
  uname | tr A-Z a-z
}

get_cpu() {
  if [[ "$(uname -p)" = "i686" ]]; then
    echo "x86"
  else
    echo "x64"
  fi
}

os=$(get_os)
cpu=$(get_cpu)
export JQ="$BP_DIR/vendor/jq-$os"

read_json() {
  local file=$1
  local key=$2
  if test -f $file; then
    cat $file | $JQ --raw-output "$key // \"\"" || return 1
  else
    echo ""
  fi
}
