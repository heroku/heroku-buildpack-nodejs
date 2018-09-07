
monitor_memory_usage() {
  local output_file=$1
  local command="${@:2}"

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

  # ps gives us kb, let's convert to mb for convenience
  echo "$(($peak / 1024))" > $output_file

  # After wait returns we can get the exit code of $command
  wait $pid

  # return the exit code of $command
  return $?
}

monitor() {
  local command_name=$1
  local command="${@:2}"
  local peak_mem_output=$(mktemp)
  local start=$(nowms)

  # execute the subcommand and save the peak memory usage
  monitor_memory_usage $peak_mem_output $command

  mtime "exec.$command_name.time" "${start}"
  mmeasure "exec.$command_name.memory" "$(cat $peak_mem_output)"
}
