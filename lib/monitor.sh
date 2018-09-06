#!/usr/bin/env bash


trap onexit SIGTERM


onexit() {
  echo "exit"
}

while :			# This is the same as "while true".
do
        sleep 60	# This script is not really doing anything.
done
