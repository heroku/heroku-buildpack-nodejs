
kv_create() {
  local f=$1
  mkdir -p $(dirname $f)
  touch $f
}

kv_clear() {
  local f=$1
  echo "" > $f
}

kv_set() {
  if [[ $# -eq 3 ]]; then
    local f=$1
    if [[ -f $f ]]; then
      # if the value has any spaces, wrap it in quotes
      if [[ $3 =~ [[:space:]]+ ]]; then
        echo "$2=\"$3\"" >> $f
      else
        echo "$2=$3" >> $f
      fi
    fi
  fi
}

# get the value, but don't unwrap quotes
kv_get_literal() {
  if [[ $# -eq 2 ]]; then
    local f=$1
    if [[ -f $f ]]; then
      grep "^$2=" $f | sed -e "s/^$2=//" | tail -n 1
    fi
  fi
}

kv_get() {
  local value=$(kv_get_literal $1 $2 $3)

  # if the value has been wrapped in quotes, unwrap it
  if [[ $value =~ ^\".+\"$ ]]; then
    echo "${value:1:${#value}-2}"
  else
    echo $value
  fi
}

kv_keys() {
  local f=$1
  local keys=()

  if [[ -f $f ]]; then
    # get list of keys
    while IFS="=" read -r key value; do
      keys+=("$key")
    done < $f

    echo "${keys[@]}" | tr ' ' '\n' | sort -u
  fi
}

kv_list() {
  local f=$1

  kv_keys $f | tr ' ' '\n' | while read -r key; do
    if [[ -n $key ]]; then
      echo "$key=$(kv_get_literal $f $key)"
    fi
  done
}
