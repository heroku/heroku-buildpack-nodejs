#!/usr/bin/env bash

# Enable strict mode for ShellCheck but restore the caller's options at the end of the file
# (see epilogue) so they don't bleed into un-migrated scripts that source this lib. The
# caller's flags are read from `$-` (the current shell); a `$(set +o)` capture runs in a
# command-substitution subshell where bash always forces errexit off, so it would later
# restore errexit as disabled even when the caller had it on. pipefail has no `$-` letter, so
# it is captured separately (it is reported correctly inside command substitution).
# shellcheck disable=SC2034 # both are consumed by the epilogue
__cache_saved_flags="$-"
__cache_saved_pipefail="$(set +o | grep pipefail)"
set -euo pipefail

DEFAULT_PNPM_PRUNE_COUNTER_VALUE="40"

# STACK and PREBUILD are globals set by the caller (bin/compile).
# shellcheck disable=SC2154
cache::_create_signature() {
	echo "v2; ${STACK}; $(node --version || true); $(npm --version || true); $(yarn --version 2>/dev/null || true); ${PREBUILD}"
}

cache::save_signature() {
	local cache_dir="${1}"
	cache::_create_signature >"${cache_dir}/node/signature"
}

cache::_load_signature() {
	local cache_dir="${1}"
	if test -f "${cache_dir}/node/signature"; then
		cat "${cache_dir}/node/signature"
	else
		echo ""
	fi
}

cache::get_cache_status() {
	local cache_dir="${1}"
	# The signature comparison invokes the two helpers in the elif condition, so set -e is
	# disabled inside (intentional: the version probes are guarded with `|| true`) and only their
	# stdout matters, so the masked return value is fine.
	# shellcheck disable=SC2310,SC2312
	if ! "${NODE_MODULES_CACHE:-true}"; then
		echo "disabled"
	elif ! test -d "${cache_dir}/node/"; then
		echo "not-found"
	elif [[ "$(cache::_create_signature)" != "$(cache::_load_signature "${cache_dir}")" ]]; then
		echo "new-signature"
	else
		echo "valid"
	fi
}

cache::get_cache_directories() {
	local build_dir="${1}"
	local dirs1 dirs2
	dirs1=$(utils::json::read "${build_dir}/package.json" ".cacheDirectories | .[]?")
	dirs2=$(utils::json::read "${build_dir}/package.json" ".cache_directories | .[]?")

	if [[ -n "${dirs1}" ]]; then
		echo "${dirs1}"
	else
		echo "${dirs2}"
	fi
}

# YARN, YARN_ZERO_INSTALL, PNPM, and USE_NPM_INSTALL are globals set by the caller (bin/compile).
# shellcheck disable=SC2154
cache::restore_default_cache_directories() {
	local build_dir=${1:-}
	local cache_dir=${2:-}
	local yarn_cache_dir=${3:-}
	local npm_cache=${4:-}
	local pnpm_cache_dir=${5:-}

	if [[ "${YARN}" == "true" ]]; then
		if [[ "${YARN_ZERO_INSTALL}" == "true" ]]; then
			output::info "- yarn cache is checked into source control and cannot be cached"
		elif [[ -e "${cache_dir}/node/cache/yarn" ]]; then
			rm -rf "${yarn_cache_dir}"
			mkdir -p "$(dirname "${yarn_cache_dir}")"
			mv "${cache_dir}/node/cache/yarn" "${yarn_cache_dir}"
			if [[ -d "${yarn_cache_dir}/yarn" ]]; then
				# Older versions of the buildpack may have created nested yarn caches.
				# This will remove the nested cache. This correction may be removed in
				# the near future.
				rm -rf "${yarn_cache_dir}/yarn"
			fi
			output::info "- yarn cache"
		else
			output::info "- yarn cache (not cached - skipping)"
		fi
	elif [[ "${PNPM}" == "true" ]]; then
		if [[ -d "${cache_dir}/node/cache/pnpm" ]]; then
			rm -rf "${pnpm_cache_dir}"
			mv "${cache_dir}/node/cache/pnpm" "${pnpm_cache_dir}"
			output::info "- pnpm cache"
			build_data::set_raw "pnpm_cache" "true"
		else
			output::info "- pnpm cache (not cached - skipping)"
		fi
	elif [[ "${USE_NPM_INSTALL}" == "false" ]]; then
		if [[ -d "${cache_dir}/node/cache/npm" ]]; then
			rm -rf "${npm_cache}"
			mv "${cache_dir}/node/cache/npm" "${npm_cache}"
			output::info "- npm cache"
			build_data::set_raw "npm_cache" "true"
		else
			output::info "- npm cache (not cached - skipping)"
		fi
	else
		# node_modules
		if [[ -e "${build_dir}/node_modules" ]]; then
			output::info "- node_modules is checked into source control and cannot be cached"
		elif [[ -e "${cache_dir}/node/cache/node_modules" ]]; then
			output::info "- node_modules"
			mkdir -p "$(dirname "${build_dir}/node_modules")"
			mv "${cache_dir}/node/cache/node_modules" "${build_dir}/node_modules"
		else
			output::info "- node_modules (not cached - skipping)"
		fi
	fi

	# bower_components, should be silent if it is not in the cache
	if [[ -e "${cache_dir}/node/cache/bower_components" ]]; then
		output::info "- bower_components"
	fi
}

# PNPM is a global set by the caller (bin/compile).
# shellcheck disable=SC2154
cache::restore_custom_cache_directories() {
	local cache_directories cachepath
	local build_dir=${1:-}
	local cache_dir=${2:-}
	local pnpm_cache_dir=${3:-}
	# Parse the input string with multiple lines: "a\nb\nc" into an array
	mapfile -t cache_directories <<<"${4}"

	output::info "Loading from cacheDirectories (package.json):"

	for cachepath in "${cache_directories[@]}"; do
		if [[ "${PNPM}" == "true" ]] && [[ "${cachepath}" =~ ^node_modules(/|$) ]]; then
			output::info "- ${cachepath} (skipping because pnpm is used)"
		elif [[ -e "${build_dir}/${cachepath}" ]]; then
			output::info "- ${cachepath} (exists - skipping)"
		else
			if [[ -e "${cache_dir}/node/cache/${cachepath}" ]]; then
				output::info "- ${cachepath}"
				mkdir -p "$(dirname "${build_dir}/${cachepath}")"
				mv "${cache_dir}/node/cache/${cachepath}" "${build_dir}/${cachepath}"
			else
				output::info "- ${cachepath} (not cached - skipping)"
			fi
		fi
	done

	if [[ "${PNPM}" == "true" ]] && [[ -e "${cache_dir}/node/cache/pnpm/store" ]]; then
		output::info "- pnpm store (included because pnpm is used)"
		# the $pnpm_cache_dir is created at the start of the build so, now, if we want to
		# rename the cache directory to $pnpm_cache_dir, we have to remove it or we'll
		# end up with a $pnpm_cache_dir/store directory instead of $pnpm_cache_dir.
		rm -rf "${pnpm_cache_dir}"
		mv "${cache_dir}/node/cache/pnpm/store" "${pnpm_cache_dir}"
	fi
}

cache::clear_cache() {
	local cache_dir="${1}"
	rm -rf "${cache_dir}/node"
	mkdir -p "${cache_dir}/node"
	mkdir -p "${cache_dir}/node/cache"
}

# YARN, YARN_ZERO_INSTALL, YARN_2, PNPM, and USE_NPM_INSTALL are globals set by the caller (bin/compile).
# shellcheck disable=SC2154
cache::save_default_cache_directories() {
	local build_dir=${1:-}
	local cache_dir=${2:-}
	local yarn_cache_dir=${3:-}
	local npm_cache=${4:-}
	local pnpm_cache_dir=${5:-}

	if [[ "${YARN}" == "true" ]]; then
		if [[ -d "${yarn_cache_dir}" ]]; then
			if [[ "${YARN_ZERO_INSTALL}" == "true" ]]; then
				output::info "- yarn cache is checked into source control and cannot be cached"
			elif [[ "${YARN_2}" == "true" ]]; then
				# For improved performance, we copy using hard links if possible. This
				# requires that the yarn cache and build cache directories are on the
				# same filesystem mount — which is the case for standard builds but not
				# Heroku CI or build-in-app-dir.
				local yarn_cache_fs cache_fs
				yarn_cache_fs=$(df --output=target "${yarn_cache_dir}" 2>/dev/null | tail -n1)
				cache_fs=$(df --output=target "${cache_dir}" 2>/dev/null | tail -n1)
				if [[ "${yarn_cache_fs}" == "${cache_fs}" && -n "${yarn_cache_fs}" ]]; then
					cp -RTf --no-dereference --link "${yarn_cache_dir}" "${cache_dir}/node/cache/yarn"
				else
					cp -RTf "${yarn_cache_dir}" "${cache_dir}/node/cache/yarn"
				fi
				output::info "- yarn cache"
			else
				mv "${yarn_cache_dir}" "${cache_dir}/node/cache/yarn"
				output::info "- yarn cache"
			fi
		fi
	elif [[ "${PNPM}" == "true" ]]; then
		if [[ -d "${pnpm_cache_dir}" ]]; then
			mv "${pnpm_cache_dir}" "${cache_dir}/node/cache/pnpm"
			output::info "- pnpm cache"
		fi
	elif [[ "${USE_NPM_INSTALL}" == "false" ]]; then
		if [[ -d "${npm_cache}" ]]; then
			mv "${npm_cache}" "${cache_dir}/node/cache/npm"
			output::info "- npm cache"
		else
			output::info "- npm cache (nothing to cache)"
		fi
	else
		# node_modules
		if [[ -e "${build_dir}/node_modules" ]]; then
			output::info "- node_modules"
			mkdir -p "${cache_dir}/node/cache/node_modules"
			cp -a "${build_dir}/node_modules" "$(dirname "${cache_dir}/node/cache/node_modules")"
		else
			# this can happen if there are no dependencies
			output::info "- node_modules (nothing to cache)"
		fi
	fi

	# bower_components
	if [[ -e "${build_dir}/bower_components" ]]; then
		build_data::set_raw "has_cached_bower_components" "true"
		output::info "- bower_components"
		mkdir -p "${cache_dir}/node/cache/bower_components"
		cp -a "${build_dir}/bower_components" "$(dirname "${cache_dir}/node/cache/bower_components")"
	else
		build_data::set_raw "has_cached_bower_components" "false"
	fi

	build_data::set_raw "has_custom_cache_dirs" "false"
}

# PNPM is a global set by the caller (bin/compile).
# shellcheck disable=SC2154
cache::save_custom_cache_directories() {
	local cache_directories cachepath
	local build_dir=${1:-}
	local cache_dir=${2:-}
	local pnpm_cache_dir=${3:-}
	# Parse the input string with multiple lines: "a\nb\nc" into an array
	mapfile -t cache_directories <<<"${4}"

	output::info "Saving cacheDirectories (package.json):"

	for cachepath in "${cache_directories[@]}"; do
		if [[ "${PNPM}" == "true" ]] && [[ "${cachepath}" =~ ^node_modules(/|$) ]]; then
			output::info "- ${cachepath} (skipping because pnpm is used)"
		elif [[ -e "${build_dir}/${cachepath}" ]]; then
			output::info "- ${cachepath}"
			mkdir -p "${cache_dir}/node/cache/${cachepath}"
			cp -a "${build_dir}/${cachepath}" "$(dirname "${cache_dir}/node/cache/${cachepath}")"
		else
			output::info "- ${cachepath} (nothing to cache)"
		fi
	done

	if [[ "${PNPM}" == "true" ]] && [[ -e "${pnpm_cache_dir}" ]]; then
		output::info "- pnpm store (included because pnpm is used)"
		mkdir -p "${cache_dir}/node/cache/pnpm"
		cp -a "${pnpm_cache_dir}" "${cache_dir}/node/cache/pnpm/store"
	fi

	build_data::set_raw "has_custom_cache_dirs" "true"
}

cache::load_pnpm_prune_store_counter() {
	local cache_dir=${1:-}
	local counter

	if [[ -f "${cache_dir}/pnpm_prune_store_counter" ]]; then
		counter=$(<"${cache_dir}/pnpm_prune_store_counter")
		# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside (a non-int falls through to the default)
		if ! cache::_is_int "${counter}" || ((counter < 0)); then
			counter="${DEFAULT_PNPM_PRUNE_COUNTER_VALUE}"
		fi
	else
		counter="${DEFAULT_PNPM_PRUNE_COUNTER_VALUE}"
	fi

	echo "${counter}"
}

cache::save_pnpm_prune_store_counter() {
	local cache_dir=${1:-}
	local new_value=${2:-}

	# shellcheck disable=SC2310 # invoked in a condition so set -e is disabled inside (a non-int falls through to the default)
	if ! cache::_is_int "${new_value}" || ((new_value < 0)); then
		new_value="${DEFAULT_PNPM_PRUNE_COUNTER_VALUE}"
	fi

	echo "${new_value}" >"${cache_dir}/pnpm_prune_store_counter"
}

cache::_is_int() {
	case "${1#[-+]}" in
		'' | *[!0-9]*) return 1 ;;
		*) ;;
	esac
}

# Restore the sourcing shell's original options (see preamble). errexit/nounset come from the
# saved `$-`; pipefail from its own saved `set +o` line.
case "${__cache_saved_flags}" in *e*) set -e ;; *) set +e ;; esac
case "${__cache_saved_flags}" in *u*) set -u ;; *) set +u ;; esac
eval "${__cache_saved_pipefail}"
unset __cache_saved_flags __cache_saved_pipefail
