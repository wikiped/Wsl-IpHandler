#!/usr/bin/env bash

# if [ -n "${DEBUG:-}" ]; then
# 	set -o xtrace
# fi

# if [ -n "${VERBOSE:-}" ]; then
# 	set -o verbose
# fi

error() {
	local parent_lineno="$1"
	local message="$2"
	local code="${3:-1}"
	if [[ -n "$message" ]] ; then
		echo "[Error] ${code} on or near line ${parent_lineno}: ${message}" 1>&2
	else
		echo "[Error] ${code} on or near line ${parent_lineno}" 1>&2
	fi
	exit "${code}"
}

echo_log() {
	level="${1:-'INFO'}"
	message="$2"
	parent_lineno="${3:+"${3}: "}"
	printf '[%s] %s%s\n' "$level" "$parent_lineno" "$message"
}

echo_verbose() {
	if [[ -n "${VERBOSE:-}" ]]; then
		echo_log "VERBOSE" "$1" "$2"
	fi
}

echo_debug() {
	if [[ -n "${DEBUG:-}" ]]; then
		echo_log "DEBUG" "$1" "$2"
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

set_config() {
	key=$1
	value=$2
	file='/etc/wsl.conf'
	# echo "Setting key: '$key' to '$value' in config file: '$file'"
	if [[ $key != "" ]]
	then
		replacement="$key = $value"

		test -f $file || (printf "[network]\n%s\n" "$replacement" > $file; return 0)
		# echo "Modifying existing config file..."

		if grep -Pqs "^\s*$key\s*=" $file &>/dev/null
		then
			# echo "Replacing existing key: $key"
			sed -i -e "s/^\s*$key\s*=.*/$replacement/g" $file
		else
			# echo "Adding key: $replacement"
			if grep -Pqs '^\[network\]' $file 2>/dev/null
			then
				# echo "To existing [network] section"
				sed -i -e "s/^\[network\].*/[network]\n$replacement/g" $file
			else
				# echo "To created [network] section"
				printf "\n[network]\n%s\n" "$replacement" >> $file
			fi
		fi
	fi
}
