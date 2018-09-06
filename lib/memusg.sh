#!/usr/bin/env bash

output_file=$1
command="${@:2}"

# Run the command in the background
exec $command & 

# save the PID of the running command
pid=$! 

# set the peak memory usage to 0 to start
peak="0"

while true; do
  sleep .1

  # check the memory usage
  sample="$(ps -o rss= $pid 2> /dev/null)" || break

  if [[ $sample -gt $peak ]]; then
    peak=$sample 
  fi
done

echo "$peak" > $output_file
