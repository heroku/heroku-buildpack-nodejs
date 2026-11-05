#!/usr/bin/env bash

# Exports HEROKU_NODEJS_RECOMMENDED_CONCURRENCY and
# HEROKU_NODEJS_RECOMMENDED_MAX_OLD_SPACE_SIZE (MB) at dyno boot. Values already set
# (for example as config vars) are never overwritten.
#
# This file is sourced into the dyno's startup shell: it must not use set -e/-u, exit, trap,
# or print anything. All helpers are prefixed and unset at the end.
#
# HEROKU_NODEJS_RECOMMENDED_CGROUP_ROOT is a test hook that overrides /sys/fs/cgroup. It is
# unset at the end of this script.

# Sets _heroku_nodejs_recommended_num to the first word of file $1 if it is a plausible unsigned integer
# (at most 18 digits, so shell arithmetic can't overflow), otherwise to the empty string.
heroku_nodejs_recommended::read_num() {
	_heroku_nodejs_recommended_num=""
	local word
	[[ -r $1 ]] || return 0
	read -r word _ <"$1" 2>/dev/null
	if [[ ${word} =~ ^[0-9]{1,18}$ ]]; then
		_heroku_nodejs_recommended_num=${word}
	fi
	return 0
}

# Sets _heroku_nodejs_recommended_memory_mb to the dyno memory limit in MB.
heroku_nodejs_recommended::detect_memory_mb() {
	local root=$1
	local high max bytes
	_heroku_nodejs_recommended_memory_mb=512

	heroku_nodejs_recommended::read_num "${root}/memory.high"
	high=${_heroku_nodejs_recommended_num}
	heroku_nodejs_recommended::read_num "${root}/memory.max"
	max=${_heroku_nodejs_recommended_num}
	if [[ -n ${high} && -n ${max} ]]; then
		bytes=$((high < max ? high : max))
	else
		bytes=${high:-${max}}
	fi

	if [[ -z ${bytes} ]]; then
		heroku_nodejs_recommended::read_num "${root}/memory/memory.limit_in_bytes"
		bytes=${_heroku_nodejs_recommended_num}
		# cgroup v1 reports a huge sentinel when unlimited; anything over 1 TB is not a dyno limit
		if [[ -n ${bytes} ]] && ((bytes / 1048576 > 1048576)); then
			bytes=""
		fi
	fi

	if [[ -n ${bytes} ]] && ((bytes >= 1048576)); then
		_heroku_nodejs_recommended_memory_mb=$((bytes / 1048576))
	fi
	return 0
}

# Sets _heroku_nodejs_recommended_cpus to the CPU count, clamped to [1, nproc].
heroku_nodejs_recommended::detect_cpus() {
	local root=$1
	local quota period
	local max_cpus
	max_cpus=$(nproc 2>/dev/null)
	if ! [[ ${max_cpus} =~ ^[0-9]{1,6}$ ]] || ((max_cpus < 1)); then
		max_cpus=1
	fi
	_heroku_nodejs_recommended_cpus=${max_cpus}

	if [[ -r "${root}/cpu.max" ]]; then
		read -r quota period <"${root}/cpu.max" 2>/dev/null
		if [[ ${quota} =~ ^[0-9]{1,18}$ && ${period} =~ ^[0-9]{1,18}$ ]] && ((period > 0)); then
			_heroku_nodejs_recommended_cpus=$(((quota + period - 1) / period))
		fi
	fi

	if ((_heroku_nodejs_recommended_cpus < 1)); then
		_heroku_nodejs_recommended_cpus=1
	elif ((_heroku_nodejs_recommended_cpus > max_cpus)); then
		_heroku_nodejs_recommended_cpus=${max_cpus}
	fi
	return 0
}

heroku_nodejs_recommended::main() {
	local root=${HEROKU_NODEJS_RECOMMENDED_CGROUP_ROOT:-/sys/fs/cgroup}
	local concurrency=1
	local max_old_space

	heroku_nodejs_recommended::detect_memory_mb "${root}"
	# On <= 1 GB dynos the CPU count is deliberately not read: shared Cedar dynos report the host's CPUs
	if ((_heroku_nodejs_recommended_memory_mb > 1024)); then
		heroku_nodejs_recommended::detect_cpus "${root}"
		concurrency=${_heroku_nodejs_recommended_cpus}
	fi

	max_old_space=$((_heroku_nodejs_recommended_memory_mb / 2 / concurrency))
	if ((max_old_space > 4096)); then
		max_old_space=4096
	fi

	export HEROKU_NODEJS_RECOMMENDED_CONCURRENCY=${HEROKU_NODEJS_RECOMMENDED_CONCURRENCY-${concurrency}}
	export HEROKU_NODEJS_RECOMMENDED_MAX_OLD_SPACE_SIZE=${HEROKU_NODEJS_RECOMMENDED_MAX_OLD_SPACE_SIZE-${max_old_space}}
	return 0
}

heroku_nodejs_recommended::main
unset -f heroku_nodejs_recommended::read_num heroku_nodejs_recommended::detect_memory_mb heroku_nodejs_recommended::detect_cpus heroku_nodejs_recommended::main
unset _heroku_nodejs_recommended_num _heroku_nodejs_recommended_memory_mb _heroku_nodejs_recommended_cpus HEROKU_NODEJS_RECOMMENDED_CGROUP_ROOT
