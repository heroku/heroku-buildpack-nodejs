#!/usr/bin/env bash

uuid_fallback()
{
    local N B C='89ab'

    for (( N=0; N < 16; ++N ))
    do
        B=$(( RANDOM%256 ))

        case $N in
            6)
                printf '4%x' $(( B%16 ))
                ;;
            8)
                printf '%c%x' ${C:$RANDOM%${#C}:1} $(( B%16 ))
                ;;
            3 | 5 | 7 | 9)
                printf '%02x-' $B
                ;;
            *)
                printf '%02x' $B
                ;;
        esac
    done

    echo
}

uuid() {
  # On Heroku's stack, there is a uuid command
  if [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  # on macOS there is also a command
  elif [[ -x "$(command -v uuidgen)" ]]; then
    uuidgen | tr "[:upper:]" "[:lower:]"
  # If you are running this buildpack on an image without either of the above binaries
  # then let's provide something that approximates this functionality, but beware that
  # we can make no guarantees of true randomness or uniqueness of this ID. However it is
  # likely only being piped to /dev/null
  #
  # If that's not true for you, please file an issue and let us know: 
  # https://github.com/heroku/heroku-buildpack-nodejs/issues
  else
    uuid_fallback
  fi
}
