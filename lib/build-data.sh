# variable shared by this whole module
BUILD_DATA_FILE=""

bd_create() {
  local cache_dir=$1
  BUILD_DATA_FILE="$cache_dir/build-data/node"
  kv_create $BUILD_DATA_FILE
}

bd_get() {
  kv_get $BUILD_DATA_FILE $1
}

bd_set() {
  kv_set $BUILD_DATA_FILE $1 $2 
}

bd_bool() {
  local condition=$2
  local result="true"

  # Adapted from shunit2: https://github.com/kward/shunit2/blob/master/shunit2#L478-L492

  # see if condition is an integer, i.e. a return value
  match=`expr "${condition}" : '\([0-9]*\)'`

  if [[ -z "$condition" ]]; then
    # null condition = false
    result="false"
  elif [ -n "$match" -a "$condition" = "$match" ]; then
    # possible return value, treating 0 as true, and non-zero as false
    [[ "${condition}" -ne 0 ]] && result="false"
  else
    # hopefully a condition
    ( eval "$condition" ) > /dev/null 2>&1
    [[ $? -ne 0 ]] && result="false"
  fi

  kv_set $BUILD_DATA_FILE $1 "$result"
}

bd_time() {
  local start="${2}"
  local end="${3:-$(nowms)}"
  local time="$(echo \"${start}\" \"${end}\" | awk '{ printf "%.3f", ($2 - $1)/1000 }')"
  kv_set $BUILD_DATA_FILE $1 "$time"
}

log_build_data() {
  kv_list $BUILD_DATA_FILE
}

 # bootstrap
bd_create
