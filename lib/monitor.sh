#!/usr/bin/env bash

monitor_memory_usage() {
  local output_file="$1"

  # drop the first argument, and leave other arguments in place
  shift

  # Run the command in the background
  "${@:-}" &

  # save the PID of the running command
  pid=$!

  # if this build process is SIGTERM'd
  trap 'kill -TERM $pid' TERM

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

  # ps gives us kb, let's convert to mb for convenience
  echo "$((peak / 1024))" > "$output_file"

  # After wait returns we can get the exit code of $command
  wait $pid

  # wait a second time in case the trap was executed
  # http://veithen.github.io/2014/11/16/sigterm-propagation.html
  wait $pid

  # return the exit code of $command
  return $?
}

monitor() {
  local peak_mem_output start
  local command_name=$1
  shift
  local command=( "$@" )

  peak_mem_output=$(mktemp)
  start=$(nowms)

  # execute the subcommand and save the peak memory usage
  monitor_memory_usage "$peak_mem_output" "${command[@]}"

  mtime "exec.$command_name.time" "${start}"
  mmeasure "exec.$command_name.memory" "$(cat "$peak_mem_output")"

  meta_time "$command_name-time" "$start"
  meta_set "$command_name-memory" "$(cat "$peak_mem_output")"
}
