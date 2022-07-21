#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o ignoreeof
set -o nounset
set -o pipefail

# if [ -n "${DEBUG:-}" ]; then
# 	set -o xtrace
# fi

# if [ -n "${VERBOSE:-}" ]; then
# 	set -o verbose
# fi

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
}

error() {
	local parent_lineno="$1"
	local message="$2"
	local code="${3:-1}"
	local -a callers
	local -i n_callers=$((${#FUNCNAME[@]} - 1))

	local RED
	local LG
	local NC
	RED='\e[91m'  # Light Red
	LG='\e[37m'   # Light Gray
	NC='\e[0m'    # No Color

	# shellcheck disable=SC2001
	callers="$(echo "${FUNCNAME[@]:1:$n_callers}" | sed 's/,\s*/->/g')"
	if [[ -n "$message" ]] ; then
		echo -e "[${RED}Error ${LG}${code} in $callers on #${parent_lineno}${NC}]: ${RED}${message}${NC}" 1>&2
	else
		echo -e "[${RED}Error${NC}] ${code} in $callers on #${parent_lineno}${NC}" 1>&2
	fi
	exit "${code}"
}

trap 'error ${LINENO}' ERR
trap cleanup SIGINT SIGTERM ERR EXIT

echo_log() {
	local level="${1:-'INFO'}"
	local message="$2"
	local parent_lineno="${3:+"${3}: "}"
	printf '[%s]:%s %s\n' "$level" "$parent_lineno" "$message"
}

echo_verbose() {
	if [[ -n "${VERBOSE:-}" ]]; then
		echo_log "VERBOSE" "$1" "${2:-}"
	fi
}

echo_debug() {
	if [[ -n "${DEBUG:-}" ]]; then
		echo_log "DEBUG" "$1" "${2:-}"
	fi
}

sudo_run() {
    # command="$1"
    # params=("${2[@]}")
	if [[ $EUID != 0 ]]; then
    	# sudo "$command" "${params[@]}"
    	sudo "$@"
    	return $?
	else
		# "$command" "${params[@]}"
		"$@"
		return $?
	fi
}

install_packages() {
	local wsl_os
	wsl_os="$(grep ^ID= /etc/os-release | cut -d= -f2)"
	case "$wsl_os" in
		*ubuntu* )
			type ip &>/dev/null || sudo_run apt -y -q install net-tools
			;;
		*fedora* )
			type ip &>/dev/null || sudo_run yum -y -q install iproute
			type ping &>/dev/null || sudo_run yum -y -q install iputils
			;;
		*)
			error ${LINENO} "Only Ubuntu and Fedora Families are are supported, not '$wsl_os'. Terminating..." 6
			;;
	esac
	# if (! type ip &>/dev/null) || (! type ping &>/dev/null)
	# then
	# 	if [[ $EUID != 0 ]]; then
	# 		sudo_run "$0" "$@"
	# 	fi
	# 	$installer -y -q install $packages
	# fi
}

is_valid_ip_address() {
	local ip_pattern='^(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))\.){3}((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))$'
	if (echo "$1" | grep -Pqs "$ip_pattern" &>/dev/null)
	then
		true
	else
		false
	fi
}

format_config() {
	local file=${1:?"Parameter #1 'Path to config file' is required in format_config"}
	# sed -i ':a;N;$!ba;s/\n\s*//g' "$file"  # replace multiple newlines with one
	sed -i '/^[[:blank:]]*$/d' "$file"  # remove empty lines
	printf "\n" >> "$file"
}

set_config() {
	local key=${1:?"Parameter #1 'key' is required in set_config"}
	local value=${2:?"Parameter #2 'value' is required in set_config"}
	local file=${3:?"Parameter #3 'Path to config file' is required in set_config"}
	echo_debug "Setting key: '$key' to '$value' in config file: '$file'"
	if [[ $key != "" ]]
	then
		local replacement="$key = $value"

		test -f "$file" || (printf "%s\n" "$replacement" > "$file"; return 0)
		echo_debug "Modifying existing config file..." ${LINENO}

		if grep -Pqs "^\s*$key\s*=" "$file" &>/dev/null
		then
			echo_debug "Replacing existing key: $key" ${LINENO}
			sed -i -e "s/^\s*$key\s*=.*/$replacement/g" "$file"
		else
			echo_debug "Adding key: $replacement" ${LINENO}
			printf "%s\n" "$replacement" >> "$file"
		fi
	fi
	format_config "$file"
}

remove_config() {
	local key=${1:?"Parameter #1 'key' is required in remove_config"}
	local file=${2:?"Parameter #2 'Path to config file' is required in remove_config"}
	echo_debug "Removing key: '$key' in config file: '$file'" ${LINENO}
	if [[ $key != "" ]]
	then
		test -f "$file" || (echo_debug "File '$file' does not exist. Exiting..." ${LINENO}; return 0)

		if grep -Pqs "^\s*$key\s*=" "$file" &>/dev/null
		then
			echo_debug "Removing existing key: $key" ${LINENO}
			sed -i -e "/^\s*$key\s*=.*$/d" "$file"
		else
			echo_debug "Key '$key' not found."
		fi
	fi
}
