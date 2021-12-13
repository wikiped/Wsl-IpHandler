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
		"ubuntu" )
			type ip &>/dev/null || sudo_run apt -y -q install net-tools
			;;
		"fedora" )
			type ip &>/dev/null || sudo_run yum -y -q install iproute
			type ping &>/dev/null || sudo_run yum -y -q install iputils
			;;
		*)
			error ${LINENO} "Only Ubuntu and Fedora are supported. Terminating..." 6
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

set_config() {
	local key=$1
	local value=$2
	local file=${3:-'/etc/wsl.conf'}
	echo_debug "Setting key: '$key' to '$value' in config file: '$file'"
	if [[ $key != "" ]]
	then
		local replacement="$key = $value"

		test -f "$file" || (printf "[network]\n%s\n" "$replacement" > "$file"; return 0)
		echo_debug "Modifying existing config file..." ${LINENO}

		if grep -Pqs "^\s*$key\s*=" "$file" &>/dev/null
		then
			echo_debug "Replacing existing key: $key" ${LINENO}
			sed -i -e "s/^\s*$key\s*=.*/$replacement/g" "$file"
		else
			echo_debug "Adding key: $replacement" ${LINENO}
			if grep -Pqs '^\[network\]' "$file" 2>/dev/null
			then
				echo_debug "To existing [network] section" ${LINENO}
				sed -i -e "s/^\[network\].*/[network]\n$replacement/g" "$file"
			else
				echo_debug "To created [network] section" ${LINENO}
				printf "\n[network]\n%s\n" "$replacement" >> "$file"
			fi
		fi
	fi
}

remove_config() {
	local key=$1
	local file=${2:-'/etc/wsl.conf'}
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
