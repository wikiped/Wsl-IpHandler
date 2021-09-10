#!/usr/bin/env bash

set -o errexit
set -o ignoreeof
set -o pipefail

# if [ -n "${DEBUG:-}" ]; then
# 	set -o xtrace
# fi

# if [ -n "${VERBOSE:-}" ]; then
# 	set -o verbose
# fi

dev='eth0'
win_hosts_edit_script='Should be substituted during installation by install-wsl-ip2hosts.sh'

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

trap 'error ${LINENO}' ERR

get_config() {
	key=$1
	test -z "$key" && error ${LINENO} "Key can not be empty in get_config"
	grep -Po --color=never "$key\s*=.*" /etc/wsl.conf 2>/dev/null | cut -d= -f2 | sed 's/^[[:space:]]*//' 2>/dev/null
}

get_ip_prefix() {
	# IP for this WSL2 instance to be included in Windows hosts file
	ip addr show dev $dev | grep -Po --color=never "inet \K[\d\./]+" 2>/dev/null | cut -d$'\n' -f1
}

ip_exists() {
	set +o pipefail
	local ip_addr=$1
	if ip addr show dev $dev | grep -Po "inet \K[\d\./]+" 2>/dev/null | grep -qF "$ip_addr"
	then
		set -o pipefail
		true
	else
		set -o pipefail
		false
	fi
}

get_new_ip_prefix() {
	start_ip=${1%/*}
	suffix=$(echo "$1" | grep -Po --color=never '/\K[\d]+$')
	suffix=${suffix:=24}
	three_octets=$(echo "$start_ip" | cut -d. -f1-3)
	last_octet=$(echo "$start_ip" | cut -d. -f4)
	offset=$2
	test "$offset" -gt 0 || error ${LINENO} "get_new_ip_prefix: offset must be > 0 -> not: $offset" 1
	test "$offset" -lt 255 || error ${LINENO} "get_new_ip_prefix: offset must be < 255 -> not: $offset" 2
	new_octet=$((last_octet + offset))
	if [[ $new_octet -gt 255 ]]
	then
		new_octet=$((new_octet - 255))
	fi
	echo "${three_octets}.${new_octet}/${suffix}"
}

ip_addr_add() {
	case $# in
		1)
			ip_prefix=$1
			;;
		2)
			ip_prefix="${1}/${2}"
			;;
		*)
			error ${LINENO} "ip_addr_add needs either 1: 'id_address/suffix' or 2: 'id_address' 'suffix' paramenter(s)." 3
			;;
	esac

	label="${dev}:ip2hosts"  # Number of symbols after ':' must not exceed 10!
	ip addr add "$ip_prefix" broadcast + dev $dev label $label
}

ip_addr_del() {
	case $# in
		1 )
			ip_prefix=$1
			;;
		2 )
			ip_prefix="${1}/${2}"
			;;
		* )
			error ${LINENO} "ip_addr_add needs either 1: 'id_address/suffix' or 2: 'id_address' 'suffix' paramenter(s)." 4
			;;
	esac

	ip addr del "$ip_prefix" dev $dev
}

get_nameserver_ip() {
	tail -1 /etc/resolv.conf | cut -d' ' -f2 2>/dev/null || error ${LINENO} "Error parsing IP" 5
}

get_default_gateway_ip() {
	ip route show | grep --color=never '^default.*' | grep -Po '\b[\d\.]+\b' 2>/dev/null
}

get_gateway_prefix_length() {
	ip route show | grep -Po --color=never '^[\d\./]+' | cut -d/ -f2
}

add_entry_to_hosts() {
	hostname=$1
	ip=$2
	if grep "$hostname" /etc/hosts &>/dev/null
	then
		# if the domain name is in /etc/hosts - replace it
		sed -i "/$hostname/ s/.*/$ip\t$hostname/" /etc/hosts
	else
		# if not - add it
		printf "%s\t%s\n" "$ip" "$hostname" >> /etc/hosts
	fi
}

process_wsl_host_and_ip_with_offset() {
	wsl_host="${1:?'wsl_host is required to process_wsl_host_and_ip_with_offset'}"
	gateway_ip_with_prefix="${2:?'gateway_ip_with_prefix is required to process_wsl_host_and_ip_with_offset'}"
	offset="${3:?'offset is required to process_wsl_host_and_ip_with_offset'}"
	current_ip_addr="$(get_ip_prefix)"

	if [[ $offset -gt 0 ]]
	then
		new_ip_prefix=$(get_new_ip_prefix "$gateway_ip_with_prefix" "$offset")
		test $? = 0 || error ${LINENO} "(get_new_ip_prefix $gateway_ip_with_prefix $offset) failed." 13
		echo_verbose "Obtained IP with Offset=$offset, Old IP: $current_ip_addr, New IP: $new_ip_prefix, Gateway IP: $gateway_ip_with_prefix"
	else
		new_ip_prefix=$current_ip_addr
		echo_verbose "Offset=0; Nothing to change, current IP: $current_ip_addr, Gateway IP: $gateway_ip_with_prefix"
	fi

	if [[ ! $(ip_exists "$new_ip_prefix") ]]
	then
		ip_addr_del "$current_ip_addr" || error ${LINENO} "(ip_addr_del $current_ip_addr) failed." 14
		echo_verbose "Deleted existing IP address: $current_ip_addr"

		ip_addr_add "$new_ip_prefix" || error ${LINENO} "(ip_addr_add $new_ip_prefix) failed." 15
		echo_verbose "Added new IP address: $new_ip_prefix"
	else
		echo_verbose "IP address $new_ip_prefix already exists!"
	fi
}

process_windows_host_and_ip() {
	windows_ip="${1:?'windows_ip is required to process_windows_host_and_ip'}"
	windows_ip="${windows_ip%/*}"  # Remove suffix
	windows_host="${2:?'windows_host is required to process_windows_host_and_ip'}"

	add_entry_to_hosts "$windows_host" "$windows_ip"

	if [[ $(get_default_gateway_ip) != "$windows_ip" ]]
	then
		ip route add default via "$windows_ip" dev $dev
		test $? = 0 || error ${LINENO} "(ip route add default via $windows_ip dev $dev) failed." 16
	fi
}

run_powershell_script_to_edit_windows_hosts() {
	ps_script="${1:?'script path is required for run_powershell_script_to_edit_windows_hosts'}"
	ip_address="${2:?'ip_address is required for run_powershell_script_to_edit_windows_hosts'}"
	ip_address="${ip_address%/*}"  # Remove suffix
	wsl_host="${3:?'wsl_host is required for run_powershell_script_to_edit_windows_hosts'}"
	test -f "$(wslpath "$ps_script")" || error ${LINENO} "PowerShell script to edit windows hosts file not found: '$ps_script'"

	# Use PowerShellCore if installed, otherwise fallback to Windows Powershell
	psexe="$(type -p pwsh.exe || type -p powershell.exe)"
	# psexe="/mnt/c/Program Files/PowerShell/7/pwsh.exe"
	test $? = 0 -o -z "$psexe" || error ${LINENO} 'Could not locate PowerShell executable.' 17

	#echo "${psexe}" "${ps_script}" "${ip_address%/*}" "${wsl_host}"
	"${psexe}" "${ps_script}" "${ip_address}" "${wsl_host}"
	test $? = 0 || error ${LINENO} "Error executing ${ps_script} ${ip_address} ${wsl_host}" 16

	echo_verbose "Added ${ip_address} ${wsl_host} to windows hosts file!"
}

main() {
	# Process Local IP and Host
	offset=$(get_config 'ip_offset')
	test "$offset" -ge 0 -a "$offset" -lt 255 || error ${LINENO} "$offset -> is not valid ip offset!" 9

	gateway_ip=$(get_default_gateway_ip)
	test $? = 0 || error ${LINENO} "'get_default_gateway_ip' failed." 10

	gateway_prefix=$(get_gateway_prefix_length)
	test $? = 0 || error ${LINENO} "'get_gateway_prefix_length' failed." 10
	test $? = 0 || error ${LINENO} "'get_gateway_prefix_length' failed." 10

	gateway_ip_with_prefix="$gateway_ip/$gateway_prefix"
	test -n "$gateway_ip_with_prefix" || error ${LINENO} "No gateway IP found!" 11

	wsl_host="$(get_config 'wsl_host')"
	test $? = 0 || error ${LINENO} "Failed to get wsl_host from /etc/wsl.conf/" 12

	process_wsl_host_and_ip_with_offset "$wsl_host" "$gateway_ip_with_prefix" "$offset"

	# Process locally Windows Host and IP
	windows_ip="$(get_nameserver_ip)"
	test $? || error ${LINENO} "get_nameserver_ip failed" 7

	windows_host="$(get_config 'windows_host')"
	test $? = 0 || error ${LINENO} 'Failed to get windows_host from /etc/wsl.conf. Aborting...' 8

	process_windows_host_and_ip "$windows_ip" "$windows_host"

	# Process local Host and IP on Windows
	run_powershell_script_to_edit_windows_hosts "$win_hosts_edit_script" "$new_ip_prefix" "$wsl_host"

	echo "Host name: $wsl_host IP Address: ${new_ip_prefix%/*}"
}

main
