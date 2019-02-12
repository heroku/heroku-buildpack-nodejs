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
  # fallback just to be sure
  else
    uuid_fallback
  fi
}
